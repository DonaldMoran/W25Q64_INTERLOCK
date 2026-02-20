#include <stdio.h>
#include <time.h>
#include <string.h>
#include "pico/stdlib.h"
#include "bus.h"
#include "cmd_defs.h"
#include "hardware/watchdog.h"
#include "pico/cyw43_arch.h"
#include "lwip/tcp.h"
#include "lwip/udp.h"
#include "lwip/dns.h"
#include "hardware/rtc.h"
#include "pico/util/datetime.h"
#include "w25q64.h"

// --- Wi-Fi Configuration ---
#define WIFI_SSID "YOUR_SSID"        // Replace with your Wi-Fi SSID
#define WIFI_PASSWORD "YOUR_WIFI_PASS" // Replace with your Wi-Fi password

// Forward declarations from w25q64.c
void w25q_init_hardware();
bool test_spi_communication(uint32_t address, uint32_t test_pattern);
extern struct lfs_config w25q_cfg;
#include "lfs.h"

lfs_t lfs;
static bool fs_mounted = false;

// Add near top with other globals (around line 40)
typedef enum {
    STATE_IDLE,
    STATE_SAVEMEM_STREAM,
    STATE_LOADMEM_STREAM
} pico_state_t;


// --- FILE HANDLE SYSTEM ---
#define MAX_OPEN_FILES 4

typedef struct {
    bool used;
    lfs_file_t file;
} file_handle_t;

file_handle_t open_files[MAX_OPEN_FILES];

void init_handles() {
    for (int i = 0; i < MAX_OPEN_FILES; i++) {
        open_files[i].used = false;
    }
}

pico_state_t current_state = STATE_IDLE;
uint16_t stream_bytes_remaining = 0;
lfs_file_t stream_file;
#define SAVEMEM_BUF_SIZE 256
uint8_t savemem_buf[SAVEMEM_BUF_SIZE];
uint16_t savemem_buf_pos = 0;
uint16_t savemem_buf_fill = 0;

// --- HTTP CLIENT HELPERS ---
#define HTTP_BUF_SIZE 32768
uint8_t http_buf[HTTP_BUF_SIZE]; // Static buffer for downloads

// File server IP and Port (hardcoded on Pico side)
#define FILE_SERVER_IP "192.168.100.197"
#define FILE_SERVER_PORT 8000

typedef struct {
    bool complete;
    bool connected;
    bool error;
    size_t received;
} http_req_t;

static err_t http_recv_cb(void *arg, struct tcp_pcb *tpcb, struct pbuf *p, err_t err) {
    http_req_t *req = (http_req_t *)arg;
    if (!p) {
        req->complete = true;
        return ERR_OK;
    }
    if (p->tot_len > 0) {
        if (req->received + p->tot_len <= HTTP_BUF_SIZE) {
            pbuf_copy_partial(p, http_buf + req->received, p->tot_len, 0);
            req->received += p->tot_len;
            tcp_recved(tpcb, p->tot_len);
        } else {
            req->error = true; // Buffer overflow
            req->complete = true;
            tcp_abort(tpcb);
            return ERR_ABRT;
        }
    }
    pbuf_free(p);
    return ERR_OK;
}

static err_t http_connected_cb(void *arg, struct tcp_pcb *tpcb, err_t err) {
    http_req_t *req = (http_req_t *)arg;
    if (err == ERR_OK) {
        req->connected = true;
    } else {
        req->error = true;
        req->complete = true;
    }
    return ERR_OK;
}

static void http_err_cb(void *arg, err_t err) {
    http_req_t *req = (http_req_t *)arg;
    req->error = true;
    req->complete = true;
}

// --- NTP HELPERS ---
#define NTP_SERVER "pool.ntp.org"
#define NTP_PORT 123
#define NTP_MSG_LEN 48
#define NTP_DELTA 2208988800 // Seconds between 1900 and 1970

typedef struct {
    bool complete;
    bool error;
    uint32_t timestamp;
} ntp_req_t;

static void ntp_recv_cb(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port) {
    ntp_req_t *req = (ntp_req_t *)arg;
    if (p && p->tot_len == NTP_MSG_LEN) {
        uint8_t mode = pbuf_get_at(p, 0) & 0x07;
        if (mode == 4) { // Server mode
            uint32_t seconds = pbuf_get_at(p, 40) << 24 | pbuf_get_at(p, 41) << 16 | pbuf_get_at(p, 42) << 8 | pbuf_get_at(p, 43);
            req->timestamp = seconds - NTP_DELTA;
            req->complete = true;
        }
    }
    pbuf_free(p);
}

int main() {
    stdio_init_all();
    sleep_ms(2000);

    bus_init();
    w25q_init_hardware();
    uint8_t jedec_id[3];
    w25q_read_jedec_id(jedec_id);
    printf("JEDEC ID: %02X %02X %02X\n", jedec_id[0], jedec_id[1], jedec_id[2]);
    
    init_handles();
    rtc_init();
    
    // Initialize Wi-Fi Chip
    if (cyw43_arch_init()) {
        printf("Wi-Fi init failed!\n");
    }
    cyw43_arch_enable_sta_mode();

    printf("Pico online (Unified Firmware)\n");

    // Buffers for Command Processing
    uint8_t cmd_id;
    uint8_t arg_len;
    uint8_t arg_buf[256];
    
    // Buffers for Response
    uint8_t resp_buf[1024]; // Large enough for a directory listing

    while (1) {
        cyw43_arch_poll(); // Essential for Wi-Fi background operations

    // --- NEW: Handle streaming state ---
    if (current_state == STATE_SAVEMEM_STREAM) {
        uint8_t data = bus_read_byte();
        savemem_buf[savemem_buf_pos++] = data;
        stream_bytes_remaining--;

        // Write to file if buffer is full OR if this is the last data byte
        if (savemem_buf_pos == SAVEMEM_BUF_SIZE || stream_bytes_remaining == 0) {
            int written = lfs_file_write(&lfs, &stream_file, savemem_buf, savemem_buf_pos);
            if (written != savemem_buf_pos) {
                lfs_file_close(&lfs, &stream_file); // Attempt to close
                bus_write_byte(STATUS_ERR);
                bus_write_byte(0); bus_write_byte(0);
                current_state = STATE_IDLE;
                bus_reset_handshake();
                continue;
            }
            savemem_buf_pos = 0; // Reset buffer
        }

        if (stream_bytes_remaining == 0) {
            // Now perform the slow file close operation
            int err = lfs_file_close(&lfs, &stream_file);

            // And send the final status to the waiting 6502
            if(err){
                printf("SAVEMEM: File close failed, err=%d\n", err);
                bus_write_byte(STATUS_ERR);
                bus_write_byte(0); bus_write_byte(0);
            } else {
                printf("SAVEMEM: Complete\n");
                bus_write_byte(STATUS_OK);
                bus_write_byte(0); bus_write_byte(0);
            }
            current_state = STATE_IDLE;
            bus_reset_handshake();
        }
        continue; // Skip normal command processing
    }
    
    // --- NEW: Handle LOADMEM streaming state ---
    if (current_state == STATE_LOADMEM_STREAM) {
        if (stream_bytes_remaining > 0) {
            // Refill buffer if empty
            if (savemem_buf_pos >= savemem_buf_fill) {
                lfs_ssize_t read = lfs_file_read(&lfs, &stream_file, savemem_buf, 
                                               (stream_bytes_remaining > SAVEMEM_BUF_SIZE) ? SAVEMEM_BUF_SIZE : stream_bytes_remaining);
                if (read <= 0) {
                    // Error or unexpected EOF. Fill with 0 to prevent 6502 hang.
                    memset(savemem_buf, 0, SAVEMEM_BUF_SIZE);
                    read = (stream_bytes_remaining > SAVEMEM_BUF_SIZE) ? SAVEMEM_BUF_SIZE : stream_bytes_remaining;
                }
                savemem_buf_fill = read;
                savemem_buf_pos = 0;
            }
            
            bus_write_byte(savemem_buf[savemem_buf_pos++]);
            stream_bytes_remaining--;
        } 
        
        if (stream_bytes_remaining == 0) {
             lfs_file_close(&lfs, &stream_file);
             printf("LOADMEM: Complete\n");
             current_state = STATE_IDLE;
             bus_reset_handshake();
        }
        continue;
    }
    
    
    
    
    



        // ----------------------------------------------------------

        //Test communication
        if (!w25q_cfg.block_cycles){
            bool comms_ok = test_spi_communication(0x0, 0x12345678);
            if (!comms_ok) printf("SPI communication test failed!\n");
        }


        // ----------------------------------------------------------
        // 1. Read Command Header (ID + Length)
        // ----------------------------------------------------------
        cmd_id = bus_read_byte();
        arg_len = bus_read_byte();

        // ----------------------------------------------------------
        // 2. Read Arguments (if any)
        // ----------------------------------------------------------
        for (int i = 0; i < arg_len; i++) {
            arg_buf[i] = bus_read_byte();
        }
        // Null-terminate for safety if args are treated as strings
        arg_buf[arg_len] = 0; 

        printf("CMD: 0x%02X, Len: %d\n", cmd_id, arg_len);

        // ----------------------------------------------------------
        // 3. Dispatch / Execute
        // ----------------------------------------------------------
        // Protocol: [STATUS] [LEN_LO] [LEN_HI] [DATA...]
        uint8_t *payload_ptr = &resp_buf[3];
        uint16_t payload_len = 0;

        resp_buf[0] = STATUS_OK; // Default status

        switch (cmd_id) {
            case CMD_PING:
                // Simple Echo
                memcpy(payload_ptr, "PONG", 4);
                payload_len = 4;
                break;
                
            case CMD_GET_VERSION:
                {
                    const char *ver = "PicoDOS v1.0";
                    memcpy(payload_ptr, ver, strlen(ver));
                    payload_len = strlen(ver);
                    resp_buf[0] = STATUS_OK;
                }
                break;

            case CMD_SYS_STATUS:
                {
                    // 1. FS Status
                    char fs_str[32];
                    if (fs_mounted) {
                        snprintf(fs_str, sizeof(fs_str), "MOUNTED (%dKB)", (int)((w25q_cfg.block_count * w25q_cfg.block_size) / 1024));
                    } else {
                        strcpy(fs_str, "NOT MOUNTED");
                    }

                    datetime_t t;

                    // 2. Net Status
                    char net_str[64];
                    if (cyw43_tcpip_link_status(&cyw43_state, CYW43_ITF_STA) == CYW43_LINK_UP) {
                        const char *ip = ip4addr_ntoa(netif_ip4_addr(netif_list));
                        snprintf(net_str, sizeof(net_str), "UP (%s)", ip);
                    } else {
                        strcpy(net_str, "DOWN");
                    }

                    // 3. Time
                    char time_str[32];
                    if (rtc_get_datetime(&t)) {
                        snprintf(time_str, sizeof(time_str), "%04d-%02d-%02d %02d:%02d:%02d",
                            t.year, t.month, t.day, t.hour, t.min, t.sec);
                    } else {
                        strcpy(time_str, "NOT SET");
                    }

                    // Format Output
                    int len = snprintf((char*)payload_ptr, 1024, 
                        "SYSTEM STATUS\r\n"
                        "-------------\r\n"
                        "FS:   %s\r\n"
                        "NET:  %s\r\n"
                        "TIME: %s\r\n"
                        "FREE: %d bytes\r\n",
                        fs_str, net_str, time_str, 0);

                    resp_buf[0] = STATUS_OK;
                    payload_len = len;
                }
                break;

            case CMD_RESET:
                // Enable the watchdog, then wait for it to timeout and reset the device
                watchdog_enable(1, 1); // Timeout after 1ms, pause on debug
                // We should never get here.
                while(1);
                break;

            case CMD_FS_MOUNT:
                {
                    int err = lfs_mount(&lfs, &w25q_cfg);
                    if (err != 0) {
                        printf("LittleFS: Mount failed (%d). Attempting format...\n", err);
                        int format_err = lfs_format(&lfs, &w25q_cfg);
                        if (format_err == 0) {
                            printf("LittleFS: Format successful. Attempting mount again...\n");
                            err = lfs_mount(&lfs, &w25q_cfg);
                        } else {
                            printf("LittleFS: Format failed (%d), possible hardware issue.\n", format_err);
                        }
                    }

                    if (err == 0) {
                        fs_mounted = true;
                        resp_buf[0] = STATUS_OK;
                    } else {
                        printf("LittleFS: Final mount attempt failed (%d).\n", err);
                        resp_buf[0] = STATUS_ERR;
                    }
                    payload_len = 0;
                }
                break;

            case CMD_FS_FORMAT:
                {
                    int format_err = lfs_format(&lfs, &w25q_cfg);
                    if (format_err == 0) {
                        printf("LittleFS: Format successful.\n");
                        resp_buf[0] = STATUS_OK;
                    } else {
                        printf("LittleFS: Format failed (%d), possible hardware issue.\n", format_err);
                        resp_buf[0] = STATUS_ERR;
                    }
                    payload_len = 0;
                }
                break;

            case CMD_FS_LIST:
                {
                    // Prevent hang if FS is not mounted
                    if (!fs_mounted) {
                        resp_buf[0] = STATUS_ERR;
                        payload_len = 0;
                        break;
                    }

                    lfs_dir_t dir;
                    struct lfs_info info;
                    
                    // Use root "/" if no path provided, otherwise use arg_buf
                    const char *path = (arg_len == 0) ? "/" : (const char *)arg_buf;

                    int err = lfs_dir_open(&lfs, &dir, path);
                    if (err) {
                        resp_buf[0] = STATUS_ERR;
                        payload_len = 0;
                    } else {
                        char *out = (char *)payload_ptr;
                        size_t max_space = sizeof(resp_buf) - 4; // Reserve space for header
                        size_t written = 0;

                        while (written < max_space) {
                            int res = lfs_dir_read(&lfs, &dir, &info);
                            if (res <= 0) break; // End of directory or error

                            if (strcmp(info.name, ".") == 0 || strcmp(info.name, "..") == 0) continue;

                            // Retro Format: "FILENAME.EXT   <DIR>" or "FILENAME.EXT   1234"
                            int len;
                            if (info.type == LFS_TYPE_DIR) {
                                len = snprintf(out + written, max_space - written, "%-12s   <DIR>\n", info.name);
                            } else {
                                len = snprintf(out + written, max_space - written, "%-12s %7ld\n", info.name, info.size);
                            }
                            
                            if (len > 0) written += len;
                        }
                        lfs_dir_close(&lfs, &dir);
                        
                        resp_buf[0] = STATUS_OK;
                        payload_len = written;
                    }
                }
                break;

            case CMD_FS_REMOVE:
                {
                    // Works for files and empty directories
                    const char *path = (const char *)arg_buf;
                    int err = lfs_remove(&lfs, path);
                    resp_buf[0] = (err == 0) ? STATUS_OK : STATUS_ERR;
                    payload_len = 0;
                }
                break;

            case CMD_FS_MKDIR:
                {
                    const char *path = (const char *)arg_buf;
                    int err = lfs_mkdir(&lfs, path);
                    resp_buf[0] = (err == 0) ? STATUS_OK : STATUS_ERR;
                    payload_len = 0;
                }
                break;

            case CMD_FS_TOUCH:
                {
                    // Open with CREAT | RDWR ensures existence without truncating
                    lfs_file_t file;
                    const char *path = (const char *)arg_buf;
                    int err = lfs_file_open(&lfs, &file, path, LFS_O_RDWR | LFS_O_CREAT);
                    if (err == 0) {
                        lfs_file_close(&lfs, &file);
                        resp_buf[0] = STATUS_OK;
                    } else {
                        resp_buf[0] = STATUS_ERR;
                    }
                    payload_len = 0;
                }
                break;

            case CMD_FS_RENAME:
                {
                    // Expects: "oldname\0newname"
                    const char *old_path = (const char *)arg_buf;
                    const char *new_path = old_path + strlen(old_path) + 1;
                    
                    // Basic safety check that we didn't run off the buffer
                    if ((uint8_t*)new_path >= arg_buf + arg_len) {
                        resp_buf[0] = STATUS_ERR;
                    } else {
                        int err = lfs_rename(&lfs, old_path, new_path);
                        resp_buf[0] = (err == 0) ? STATUS_OK : STATUS_ERR;
                    }
                    payload_len = 0;
                }
                break;

            case CMD_FS_APPEND:
                {
                    // Expects: "filename\0data..."
                    const char *path = (const char *)arg_buf;
                    const uint8_t *data = (const uint8_t *)(path + strlen(path) + 1);
                    int data_len = arg_len - (strlen(path) + 1);

                    if (data_len < 0) {
                        resp_buf[0] = STATUS_ERR;
                    } else {
                        lfs_file_t file;
                        int err = lfs_file_open(&lfs, &file, path, LFS_O_WRONLY | LFS_O_CREAT | LFS_O_APPEND);
                        if (err == 0) {
                            lfs_file_write(&lfs, &file, data, data_len);
                            lfs_file_close(&lfs, &file);
                            resp_buf[0] = STATUS_OK;
                        } else {
                            resp_buf[0] = STATUS_ERR;
                        }
                    }
                    payload_len = 0;
                }
                break;

            case CMD_FS_COPY:
                {
                    // Expects: "src\0dst"
                    const char *src_path = (const char *)arg_buf;
                    const char *dst_path = src_path + strlen(src_path) + 1;

                    if ((uint8_t*)dst_path >= arg_buf + arg_len) {
                        resp_buf[0] = STATUS_ERR;
                    } else {
                        lfs_file_t f_src, f_dst;
                        int err_src = lfs_file_open(&lfs, &f_src, src_path, LFS_O_RDONLY);
                        int err_dst = lfs_file_open(&lfs, &f_dst, dst_path, LFS_O_WRONLY | LFS_O_CREAT | LFS_O_TRUNC);

                        if (err_src == 0 && err_dst == 0) {
                            // Use the response buffer as a scratchpad for copying
                            // We can use the area after the header (3 bytes)
                            uint8_t *copy_buf = &resp_buf[3]; 
                            lfs_ssize_t read_len;
                            while ((read_len = lfs_file_read(&lfs, &f_src, copy_buf, sizeof(resp_buf) - 3)) > 0) {
                                lfs_file_write(&lfs, &f_dst, copy_buf, read_len);
                            }
                            resp_buf[0] = STATUS_OK;
                        } else {
                            resp_buf[0] = STATUS_ERR;
                        }
                        if (err_src == 0) lfs_file_close(&lfs, &f_src);
                        if (err_dst == 0) lfs_file_close(&lfs, &f_dst);
                    }
                    payload_len = 0;
                }
                break;

            case CMD_FS_OPEN:
                {
                    // Args: [Filename]
                    // Returns: [HandleID] [SizeLO] [SizeHI] [Size3] [Size4]
                    int handle = -1;
                    for (int i = 0; i < MAX_OPEN_FILES; i++) {
                        if (!open_files[i].used) { handle = i; break; }
                    }

                    if (handle == -1) {
                        resp_buf[0] = STATUS_ERR; // Too many open files
                    } else {
                        const char *path = (const char *)arg_buf;
                        // Open for Read/Write, Create if missing
                        int err = lfs_file_open(&lfs, &open_files[handle].file, path, LFS_O_RDWR | LFS_O_CREAT);
                        if (err) {
                            resp_buf[0] = STATUS_ERR;
                        } else {
                            open_files[handle].used = true;
                            lfs_soff_t size = lfs_file_size(&lfs, &open_files[handle].file);
                            
                            resp_buf[0] = STATUS_OK;
                            payload_ptr[0] = (uint8_t)handle;
                            payload_ptr[1] = size & 0xFF;
                            payload_ptr[2] = (size >> 8) & 0xFF;
                            payload_ptr[3] = (size >> 16) & 0xFF;
                            payload_ptr[4] = (size >> 24) & 0xFF;
                            payload_len = 5;
                        }
                    }
                }
                break;

            case CMD_FS_CLOSE:
                {
                    // Args: [Handle]
                    uint8_t h = arg_buf[0];
                    if (h < MAX_OPEN_FILES && open_files[h].used) {
                        lfs_file_close(&lfs, &open_files[h].file);
                        open_files[h].used = false;
                        resp_buf[0] = STATUS_OK;
                    } else {
                        resp_buf[0] = STATUS_ERR;
                    }
                    payload_len = 0;
                }
                break;

            case CMD_FS_READ:
                {
                    // Args: [Handle] [LenLO] [LenHI]
                    uint8_t h = arg_buf[0];
                    uint16_t req_len = arg_buf[1] | (arg_buf[2] << 8);

                    if (h < MAX_OPEN_FILES && open_files[h].used) {
                        // Cap read length to available buffer space
                        if (req_len > sizeof(resp_buf) - 3) req_len = sizeof(resp_buf) - 3;

                        lfs_ssize_t read_len = lfs_file_read(&lfs, &open_files[h].file, payload_ptr, req_len);
                        if (read_len < 0) {
                            resp_buf[0] = STATUS_ERR;
                        } else {
                            resp_buf[0] = STATUS_OK;
                            payload_len = read_len;
                        }
                    } else {
                        resp_buf[0] = STATUS_ERR;
                    }
                }
                break;

            case CMD_FS_WRITE:
                {
                    // Args: [Handle] [Data...]
                    uint8_t h = arg_buf[0];
                    if (h < MAX_OPEN_FILES && open_files[h].used && arg_len > 0) {
                        // Data starts at arg_buf[1], length is arg_len - 1
                        lfs_ssize_t res = lfs_file_write(&lfs, &open_files[h].file, &arg_buf[1], arg_len - 1);
                        resp_buf[0] = (res < 0) ? STATUS_ERR : STATUS_OK;
                    } else {
                        resp_buf[0] = STATUS_ERR;
                    }
                    payload_len = 0;
                }
                break;

            case CMD_FS_SEEK:
                {
                    // Args: [Handle] [Offset(4)] [Whence]
                    uint8_t h = arg_buf[0];
                    int32_t offset = arg_buf[1] | (arg_buf[2] << 8) | (arg_buf[3] << 16) | (arg_buf[4] << 24);
                    int whence = arg_buf[5]; // 0=SET, 1=CUR, 2=END

                    if (h < MAX_OPEN_FILES && open_files[h].used) {
                        lfs_soff_t res = lfs_file_seek(&lfs, &open_files[h].file, offset, whence);
                        if (res < 0) {
                            resp_buf[0] = STATUS_ERR;
                        } else {
                            resp_buf[0] = STATUS_OK;
                            // Return new position
                            payload_ptr[0] = res & 0xFF;
                            payload_ptr[1] = (res >> 8) & 0xFF;
                            payload_ptr[2] = (res >> 16) & 0xFF;
                            payload_ptr[3] = (res >> 24) & 0xFF;
                            payload_len = 4;
                        }
                    } else {
                        resp_buf[0] = STATUS_ERR;
                    }
                }
                break;

            case CMD_FS_TELL:
                {
                    // Args: [Handle]
                    uint8_t h = arg_buf[0];
                    if (h < MAX_OPEN_FILES && open_files[h].used) {
                        lfs_soff_t res = lfs_file_tell(&lfs, &open_files[h].file);
                        if (res < 0) {
                            resp_buf[0] = STATUS_ERR;
                        } else {
                            resp_buf[0] = STATUS_OK;
                            payload_ptr[0] = res & 0xFF;
                            payload_ptr[1] = (res >> 8) & 0xFF;
                            payload_ptr[2] = (res >> 16) & 0xFF;
                            payload_ptr[3] = (res >> 24) & 0xFF;
                            payload_len = 4;
                        }
                    } else {
                        resp_buf[0] = STATUS_ERR;
                    }
                }
                break;

            case CMD_FS_STAT:
                {
                    // Args: [Path]
                    // Returns: [Type(1)] [Size(4)]
                    // Type: 1=Reg, 2=Dir
                    struct lfs_info info;
                    const char *path = (const char *)arg_buf;
                    int err = lfs_stat(&lfs, path, &info);
                    if (err == 0) {
                        resp_buf[0] = STATUS_OK;
                        payload_ptr[0] = info.type;
                        payload_ptr[1] = info.size & 0xFF;
                        payload_ptr[2] = (info.size >> 8) & 0xFF;
                        payload_ptr[3] = (info.size >> 16) & 0xFF;
                        payload_ptr[4] = (info.size >> 24) & 0xFF;
                        payload_len = 5;
                    } else {
                        resp_buf[0] = STATUS_ERR;
                    }
                }
                break;

            case CMD_FS_SIZE:
                {
                    // Args: None
                    // Returns: [BlockSize(4)] [BlockCount(4)]
                    resp_buf[0] = STATUS_OK;
                    
                    // Block Size
                    payload_ptr[0] = w25q_cfg.block_size & 0xFF;
                    payload_ptr[1] = (w25q_cfg.block_size >> 8) & 0xFF;
                    payload_ptr[2] = (w25q_cfg.block_size >> 16) & 0xFF;
                    payload_ptr[3] = (w25q_cfg.block_size >> 24) & 0xFF;
                    
                    // Block Count
                    payload_ptr[4] = w25q_cfg.block_count & 0xFF;
                    payload_ptr[5] = (w25q_cfg.block_count >> 8) & 0xFF;
                    payload_ptr[6] = (w25q_cfg.block_count >> 16) & 0xFF;
                    payload_ptr[7] = (w25q_cfg.block_count >> 24) & 0xFF;
                    payload_len = 8;
                }
                break;

            case CMD_FS_SYNC:
                {
                    uint8_t h = arg_buf[0];
                    if (h < MAX_OPEN_FILES && open_files[h].used) {
                        int err = lfs_file_sync(&lfs, &open_files[h].file);
                        resp_buf[0] = (err == 0) ? STATUS_OK : STATUS_ERR;
                    } else {
                        resp_buf[0] = STATUS_ERR;
                    }
                }
                break;

            case CMD_FS_UNMOUNT:
                {
                    int u_err = lfs_unmount(&lfs);
                    if (u_err == 0) fs_mounted = false;
                    resp_buf[0] = (u_err == 0) ? STATUS_OK : STATUS_ERR;
                }
                break;

            // --- NETWORK COMMANDS ---
            
            case CMD_NET_STATUS:
                // Returns 0x00 (OK) if connected, 0xFF (ERR) if not
                if (cyw43_tcpip_link_status(&cyw43_state, CYW43_ITF_STA) == CYW43_LINK_UP) {
                    resp_buf[0] = STATUS_OK;
                } else {
                    resp_buf[0] = STATUS_ERR;
                }
                payload_len = 0;
                break;

            case CMD_NET_CONNECT:
                {
                    // Turn LED off before attempting
                  cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, 0);

                    //Hardcoded SSID and Password
                    const char *ssid = WIFI_SSID;
                    const char *pass = WIFI_PASSWORD;

                    // Args: "SSID\0PASSWORD"
                    //const char *ssid = (const char *)arg_buf;
                    // const char *pass = ssid + strlen(ssid) + 1;
                    
                    printf("Connecting to Wi-Fi: %s\n", ssid);
                    
                    int err = -1; // Initialize with an error
                    for (int i = 0; i < 3; i++) { // Try up to 3 times
                        err = cyw43_arch_wifi_connect_timeout_ms(ssid, pass, CYW43_AUTH_WPA2_AES_PSK, 30000);
                        if (err == 0) {
                            break; // Success
                        }
                        printf("Wi-Fi connect failed, attempt %d. Error: %d. Retrying...\n", i + 1, err);
                        sleep_ms(1000); // Small delay before retrying
                    }
                    
                    if (err == 0) {
                        resp_buf[0] = STATUS_OK;
                        payload_len = 0;
                        cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, 1); // Turn on LED
                        printf("Wi-Fi connected successfully!\n");
                    } else {
                        resp_buf[0] = STATUS_ERR;
                        // Copy 4-byte error code to payload
                        memcpy(payload_ptr, &err, 4);
                        payload_len = 4;
                        printf("Wi-Fi connection failed after multiple attempts. Last error: %d\n", err);
                    }
                }
                break;

            case CMD_NET_GET_IP:
                {
                    // Returns IP address as string "192.168.1.105"
                    const char *ip_str = ip4addr_ntoa(netif_ip4_addr(netif_list));
                    
                    size_t len = strlen(ip_str);
                    memcpy(payload_ptr, ip_str, len);
                    resp_buf[0] = STATUS_OK;
                    payload_len = len;
                }
                break;

            case CMD_NET_HTTP_GET:
                {
                    // Args: [IP]\0[Port]\0[RemotePath]\0[LocalPath]
                    // Example: "192.168.1.5", "8000", "/game.bin", "game.bin"
                    
                    const char *ip_str = (const char *)arg_buf;
                    const char *port_str = ip_str + strlen(ip_str) + 1;
                    const char *remote_path = port_str + strlen(port_str) + 1;
                    const char *local_path = remote_path + strlen(remote_path) + 1;

                    ip_addr_t remote_ip;
                    if (!ipaddr_aton(ip_str, &remote_ip)) {
                        resp_buf[0] = STATUS_ERR;
                        payload_len = 0;
                        break;
                    }
                    int port = atoi(port_str);

                    printf("HTTP GET %s:%d%s -> %s\n", ip_str, port, remote_path, local_path);

                    struct tcp_pcb *pcb = tcp_new();
                    http_req_t req = {0};
                    
                    tcp_arg(pcb, &req);
                    tcp_recv(pcb, http_recv_cb);
                    tcp_err(pcb, http_err_cb);

                    cyw43_arch_lwip_begin();
                    tcp_connect(pcb, &remote_ip, port, http_connected_cb);
                    cyw43_arch_lwip_end();

                    // Wait for connection
                    int timeout = 0;
                    while (!req.connected && !req.error && timeout++ < 5000) sleep_ms(1);

                    if (req.connected) {
                        char request[256];
                        snprintf(request, sizeof(request), "GET %s HTTP/1.0\r\nHost: %s\r\n\r\n", remote_path, ip_str);
                        
                        cyw43_arch_lwip_begin();
                        tcp_write(pcb, request, strlen(request), TCP_WRITE_FLAG_COPY);
                        tcp_output(pcb);
                        cyw43_arch_lwip_end();

                        // Wait for download to complete
                        timeout = 0;
                        while (!req.complete && timeout++ < 10000) sleep_ms(1); // 10s timeout
                    }

                    if (pcb) tcp_close(pcb);

                    if (req.error || !req.complete) {
                        resp_buf[0] = STATUS_ERR;
                    } else {
                        // Find HTTP Body (Double CRLF)
                        uint8_t *body = NULL;
                        size_t body_len = 0;
                        for (size_t i = 0; i < req.received - 3; i++) {
                            if (http_buf[i] == '\r' && http_buf[i+1] == '\n' && 
                                http_buf[i+2] == '\r' && http_buf[i+3] == '\n') {
                                body = &http_buf[i+4];
                                body_len = req.received - (i + 4);
                                break;
                            }
                        }

                        if (body) {
                            lfs_file_t file;
                            int err = lfs_file_open(&lfs, &file, local_path, LFS_O_WRONLY | LFS_O_CREAT | LFS_O_TRUNC);
                            if (err == 0) {
                                lfs_file_write(&lfs, &file, body, body_len);
                                lfs_file_close(&lfs, &file);
                                resp_buf[0] = STATUS_OK;
                            } else {
                                resp_buf[0] = STATUS_ERR;
                            }
                        } else {
                            resp_buf[0] = STATUS_ERR; // Header not found
                        }
                    }
                    payload_len = 0;
                }
                break;

            case CMD_NET_HTTP_POST:
                {
                    // Args: [IP]\0[Port]\0[LocalPath]\0[RemotePath]
                    const char *ip_str = (const char *)arg_buf;
                    const char *port_str = ip_str + strlen(ip_str) + 1;
                    const char *local_path = port_str + strlen(port_str) + 1;
                    const char *remote_path = local_path + strlen(local_path) + 1;

                    ip_addr_t remote_ip;
                    if (!ipaddr_aton(ip_str, &remote_ip)) {
                        resp_buf[0] = STATUS_ERR;
                        payload_len = 0;
                        break;
                    }
                    int port = atoi(port_str);

                    // 1. Open Local File
                    lfs_file_t file;
                    if (lfs_file_open(&lfs, &file, local_path, LFS_O_RDONLY) != 0) {
                        resp_buf[0] = STATUS_ERR; // File not found
                        payload_len = 0;
                        break;
                    }
                    lfs_soff_t file_size = lfs_file_size(&lfs, &file);

                    printf("HTTP POST %s -> %s:%d%s (Size: %ld)\n", local_path, ip_str, port, remote_path, file_size);

                    // 2. Connect
                    struct tcp_pcb *pcb = tcp_new();
                    http_req_t req = {0};
                    tcp_arg(pcb, &req);
                    tcp_recv(pcb, http_recv_cb); // We still need to read the "200 OK" response
                    tcp_err(pcb, http_err_cb);

                    cyw43_arch_lwip_begin();
                    tcp_connect(pcb, &remote_ip, port, http_connected_cb);
                    cyw43_arch_lwip_end();

                    int timeout = 0;
                    while (!req.connected && !req.error && timeout++ < 5000) sleep_ms(1);

                    if (req.connected) {
                        // 3. Send Headers
                        char header[256];
                        snprintf(header, sizeof(header), 
                            "POST %s HTTP/1.0\r\nHost: %s\r\nContent-Length: %ld\r\n\r\n", 
                            remote_path, ip_str, file_size);
                        
                        cyw43_arch_lwip_begin();
                        tcp_write(pcb, header, strlen(header), TCP_WRITE_FLAG_COPY);
                        cyw43_arch_lwip_end();

                        // 4. Stream File Body
                        lfs_soff_t sent = 0;
                        while (sent < file_size && !req.error) {
                            // Check available TCP buffer space
                            cyw43_arch_lwip_begin();
                            u16_t available = tcp_sndbuf(pcb);
                            cyw43_arch_lwip_end();

                            if (available == 0) {
                                sleep_ms(1);
                                continue;
                            }

                            // Read chunk from file
                            u16_t chunk_size = (file_size - sent > available) ? available : (file_size - sent);
                            if (chunk_size > sizeof(http_buf)) chunk_size = sizeof(http_buf);

                            lfs_file_read(&lfs, &file, http_buf, chunk_size);

                            // Write chunk to TCP
                            cyw43_arch_lwip_begin();
                            err_t wr_err = tcp_write(pcb, http_buf, chunk_size, TCP_WRITE_FLAG_COPY);
                            if (wr_err == ERR_OK) {
                                tcp_output(pcb);
                            }
                            cyw43_arch_lwip_end();

                            if (wr_err != ERR_OK) {
                                req.error = true;
                                break;
                            }
                            sent += chunk_size;
                        }

                        // 5. Wait for Server Response (to ensure it finished)
                        timeout = 0;
                        while (!req.complete && !req.error && timeout++ < 10000) sleep_ms(1);
                    }

                    if (pcb) tcp_close(pcb);
                    lfs_file_close(&lfs, &file);
                    resp_buf[0] = (req.error || !req.complete) ? STATUS_ERR : STATUS_OK;
                    payload_len = 0;
                }
                break;

            case CMD_NET_DISCONNECT:
                {
                    int err = cyw43_wifi_leave(&cyw43_state, CYW43_ITF_STA);
                    resp_buf[0] = (err == 0) ? STATUS_OK : STATUS_ERR;
                    payload_len = 0;
                }
                break;

            case CMD_NET_TIME:
                {
                    // Args: None
                    // Returns: "YYYY-MM-DD HH:MM:SS"
                    
                    struct udp_pcb *pcb = udp_new();
                    ntp_req_t req = {0};
                    
                    udp_recv(pcb, ntp_recv_cb, &req);
                    
                    ip_addr_t ntp_ip;
                    int err = dns_gethostbyname(NTP_SERVER, &ntp_ip, NULL, NULL);
                    
                    if (err == ERR_OK) {
                        struct pbuf *p = pbuf_alloc(PBUF_TRANSPORT, NTP_MSG_LEN, PBUF_RAM);
                        uint8_t *req_pkt = (uint8_t *)p->payload;
                        memset(req_pkt, 0, NTP_MSG_LEN);
                        req_pkt[0] = 0x1B; // LI=0, VN=3, Mode=3 (Client)
                        
                        cyw43_arch_lwip_begin();
                        udp_sendto(pcb, p, &ntp_ip, NTP_PORT);
                        cyw43_arch_lwip_end();
                        pbuf_free(p);
                        
                        // Wait for response
                        int timeout = 0;
                        while (!req.complete && timeout++ < 5000) sleep_ms(1);
                    }
                    
                    udp_remove(pcb);
                    
                    if (req.complete) {
                        time_t rawtime = (time_t)req.timestamp;
                        struct tm *ptm = gmtime(&rawtime);
                        if (ptm) {
                            // Sync Pico RTC
                            datetime_t t = {
                                .year  = ptm->tm_year + 1900,
                                .month = ptm->tm_mon + 1,
                                .day   = ptm->tm_mday,
                                .dotw  = ptm->tm_wday,
                                .hour  = ptm->tm_hour,
                                .min   = ptm->tm_min,
                                .sec   = ptm->tm_sec
                            };
                            rtc_set_datetime(&t);

                            size_t len = strftime((char*)payload_ptr, 64, "%Y-%m-%d %H:%M:%S", ptm);
                            resp_buf[0] = STATUS_OK;
                            payload_len = len;
                        } else {
                            resp_buf[0] = STATUS_ERR;
                            payload_len = 0;
                        }
                    } else {
                        // Timeout or DNS error
                        resp_buf[0] = STATUS_ERR;
                        payload_len = 0;
                    }
                }
                break;
            
            case CMD_DOWNLOAD_SIMPLE:
                {
                    // Args: [RemotePath]\0[LocalPath] (LocalPath is ignored, but part of struct)
                    const char *remote_path_arg = (const char *)arg_buf;
                    // const char *local_path_arg = remote_path_arg + strlen(remote_path_arg) + 1; // Not used here

                    ip_addr_t remote_ip;
                    if (!ipaddr_aton(FILE_SERVER_IP, &remote_ip)) {
                        resp_buf[0] = STATUS_ERR;
                        payload_len = 0;
                        break;
                    }

                    struct tcp_pcb *pcb = tcp_new();
                    http_req_t req = {0};
                    
                    tcp_arg(pcb, &req);
                    tcp_recv(pcb, http_recv_cb);
                    tcp_err(pcb, http_err_cb);

                    cyw43_arch_lwip_begin();
                    tcp_connect(pcb, &remote_ip, FILE_SERVER_PORT, http_connected_cb);
                    cyw43_arch_lwip_end();

                    // Wait for connection
                    int timeout = 0;
                    while (!req.connected && !req.error && timeout++ < 5000) sleep_ms(1);

                    if (req.connected) {
                        char request[256];
                        snprintf(request, sizeof(request), "GET %s HTTP/1.0\r\nHost: %s\r\n\r\n", remote_path_arg, FILE_SERVER_IP);
                        
                        cyw43_arch_lwip_begin();
                        tcp_write(pcb, request, strlen(request), TCP_WRITE_FLAG_COPY);
                        tcp_output(pcb);
                        cyw43_arch_lwip_end();

                        // Wait for download to complete
                        timeout = 0;
                        while (!req.complete && timeout++ < 10000) sleep_ms(1); // 10s timeout
                    }

                    if (pcb) tcp_close(pcb);

                    if (req.error || !req.complete) {
                        resp_buf[0] = STATUS_ERR;
                        payload_len = 0;
                    } else {
                        // Find HTTP Body (Double CRLF)
                        uint8_t *body = NULL;
                        size_t body_len = 0;
                        for (size_t i = 0; i < req.received - 3; i++) {
                            if (http_buf[i] == '\r' && http_buf[i+1] == '\n' && 
                                http_buf[i+2] == '\r' && http_buf[i+3] == '\n') {
                                body = &http_buf[i+4];
                                body_len = req.received - (i + 4);
                                break;
                            }
                        }

                        if (body) {
                            // Copy raw body to resp_buf
                            size_t copy_len = body_len;
                            if (copy_len > (sizeof(resp_buf) - 3)) copy_len = (sizeof(resp_buf) - 3);
                            memcpy(payload_ptr, body, copy_len);
                            resp_buf[0] = STATUS_OK;
                            payload_len = copy_len;
                        } else {
                            resp_buf[0] = STATUS_ERR; // Header not found or empty body
                            payload_len = 0;
                        }
                    }
                }
                break;

			case CMD_FS_SAVEMEM:
			{
			    // Parse args: filename (null-terminated) + 2-byte length (little-endian)
			    char *filename = (char *)arg_buf;
			    
			    // Find the null terminator to locate length bytes
			    int filename_len = strlen(filename);
			    uint16_t length = arg_buf[filename_len + 1] | (arg_buf[filename_len + 2] << 8);
			    
			    // Validate
			    if (!fs_mounted) {
			        printf("SAVEMEM: FS not mounted\n");
			        bus_write_byte(STATUS_ERR);
			        bus_write_byte(0); bus_write_byte(0);
			        break;
			    }
			    
			    if (length == 0 || length > 65535) {
			        printf("SAVEMEM: Invalid length %d\n", length);
			        bus_write_byte(STATUS_ERR);
			        bus_write_byte(0); bus_write_byte(0);
			        break;
			    }
			    
			    printf("SAVEMEM: File='%s', Length=%u\n", filename, length);
			    
			    // Open file (create/overwrite)
			    int err = lfs_file_open(&lfs, &stream_file, filename,
			                           LFS_O_WRONLY | LFS_O_CREAT | LFS_O_TRUNC);
			    if (err < 0) {
			        printf("SAVEMEM: File open failed, err=%d\n", err);
			        bus_write_byte(STATUS_ERR);
			        bus_write_byte(0); bus_write_byte(0);
			        break;
			    }
			    
			    // Send OK header (ready signal)
			    bus_write_byte(STATUS_OK);
			    bus_write_byte(0);
			    bus_write_byte(0);
			    
			    // Enter streaming state
			    stream_bytes_remaining = length;
			    current_state = STATE_SAVEMEM_STREAM;
			    savemem_buf_pos = 0; // Reset buffer index
			    printf("SAVEMEM: Ready to receive %u bytes\n", length);
			    bus_reset_handshake();
			    continue;
			}

            case CMD_FS_LOADMEM:
            {
                // Args: [Filename]
                char *filename = (char *)arg_buf;

                // Truncate at first space (for RUN command with args)
                char *p = strchr(filename, ' ');
                if (p) *p = 0;
                
                if (!fs_mounted) {
                    printf("LOADMEM: FS not mounted\n");
                    bus_write_byte(STATUS_ERR);
                    bus_write_byte(0); bus_write_byte(0);
                    break;
                }

                printf("LOADMEM: File='%s'\n", filename);

                int err = lfs_file_open(&lfs, &stream_file, filename, LFS_O_RDONLY);
                if (err < 0) {
                    printf("LOADMEM: File open failed, err=%d\n", err);
                    bus_write_byte(STATUS_ERR); // Or STATUS_NO_FILE
                    bus_write_byte(0); bus_write_byte(0);
                    break;
                }

                lfs_soff_t size = lfs_file_size(&lfs, &stream_file);
                if (size > 65535) size = 65535; // Cap at 64KB for 6502 safety

                // Send OK header + Length
                bus_write_byte(STATUS_OK);
                bus_write_byte(size & 0xFF);
                bus_write_byte((size >> 8) & 0xFF);

                // Enter streaming state
                stream_bytes_remaining = (uint16_t)size;
                current_state = STATE_LOADMEM_STREAM;
                savemem_buf_pos = 0;
                savemem_buf_fill = 0; // Force refill
                
                printf("LOADMEM: Sending %d bytes\n", (int)size);
                bus_reset_handshake();
                continue;
            }















            default:
                resp_buf[0] = STATUS_ERR;
                payload_len = 0;
                break;
        }

        // ----------------------------------------------------------
        // 4. Send Response using per‑byte handshake (no burst)
        // ----------------------------------------------------------
        resp_buf[1] = payload_len & 0xFF;        // Length Low
        resp_buf[2] = (payload_len >> 8) & 0xFF; // Length High

        // Send each byte individually
        for (int i = 0; i < 3 + payload_len; i++) {
            bus_write_byte(resp_buf[i]);
        }

        // Reset handshake lines to idle for next command
        bus_reset_handshake();
    }
}
