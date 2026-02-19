#ifndef _LWIPOPTS_H
#define _LWIPOPTS_H

// Standard configuration for Pico W LwIP (Background Mode)

#define NO_SYS                      1
#define LWIP_TIMEVAL_PRIVATE        0 // Add this line

#ifndef LWIP_SOCKET
#define LWIP_SOCKET                 0
#endif
#ifndef LWIP_NETCONN
#define LWIP_NETCONN                0
#endif
#if PICO_CYW43_ARCH_POLL
#define MEM_LIBC_MALLOC             1
#else
#define MEM_LIBC_MALLOC             0
#endif
#ifndef MEM_ALIGNMENT
#define MEM_ALIGNMENT               4
#endif
#ifndef MEM_SIZE
#define MEM_SIZE                    8192 // Increased from 4000
#endif
#ifndef MEMP_NUM_TCP_SEG
#define MEMP_NUM_TCP_SEG            36 // Increased from 32
#endif
#ifndef MEMP_NUM_ARP_QUEUE
#define MEMP_NUM_ARP_QUEUE          10
#endif
#ifndef PBUF_POOL_SIZE
#define PBUF_POOL_SIZE              16 // Changed from 24
#endif
#ifndef LWIP_ARP
#define LWIP_ARP                    1
#endif
#ifndef LWIP_ETHERNET
#define LWIP_ETHERNET               1
#endif
#ifndef LWIP_IPV4
#define LWIP_IPV4                   1
#endif
#ifndef LWIP_TCP
#define LWIP_TCP                    1
#endif
#ifndef LWIP_UDP
#define LWIP_UDP                    1
#endif
#ifndef LWIP_DNS
#define LWIP_DNS                    1
#endif
#ifndef LWIP_DHCP
#define LWIP_DHCP                   1 // Explicitly enabled
#endif

// TCP Tuning Parameters
#define TCP_MSS                     1460
#define TCP_SND_BUF                 (8 * TCP_MSS)
#define TCP_SND_QUEUELEN            ((4 * (TCP_SND_BUF) + (TCP_MSS - 1)) / (TCP_MSS))
#define TCP_WND                     (4 * TCP_MSS)

#define LWIP_DEBUG                  0 // Add this line

#endif