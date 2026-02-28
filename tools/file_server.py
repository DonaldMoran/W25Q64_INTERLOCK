#!/usr/bin/env python3
"""
Pico W Remote Filesystem Server

Supports:
- GET /                          → HTML directory listing
- GET /file.txt                  → serve file
- GET /dir/                      → directory listing
- POST /file.txt                 → create or overwrite file
- POST /dir/                     → create directory
- POST with X-Append: true       → append to file
- DELETE /file.txt               → delete file
- DELETE /dir/                   → delete empty directory

Run: python3 file_server.py
"""

from http.server import SimpleHTTPRequestHandler, HTTPServer
import os
import urllib.parse
import socket
import shutil

# === CHANGE THIS TO YOUR SHARED DIRECTORY ===
DIRECTORY = "/home/noneya/shared"

class PicoFileHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    # ------------------------------------------------------------------
    # Directory listing (root or subdir)
    # ------------------------------------------------------------------
    def list_directory(self, path):
        try:
            files = os.listdir(path)
        except OSError:
            self.send_error(404, "No permission to list directory")
            return None

        files.sort(key=lambda a: a.lower())

        # Check for PicoDOS User-Agent and return plain text
        if self.headers.get('User-Agent') == 'PicoDOS':
            self.send_response(200)
            self.send_header("Content-type", "text/plain; charset=utf-8")
            self.end_headers()
            for name in files:
                fullname = os.path.join(path, name)
                if os.path.isdir(fullname):
                    self.wfile.write(f"{name}/\n".encode("utf-8"))
                else:
                    self.wfile.write(f"{name}\n".encode("utf-8"))
            return None

        # Build relative path for display
        rel_path = os.path.relpath(path, DIRECTORY)
        if rel_path == ".":
            rel_path = ""
        display_path = f"/{rel_path}" if rel_path else "/"

        self.send_response(200)
        self.send_header("Content-type", "text/html; charset=utf-8")
        self.end_headers()

        html = f"""
        <!DOCTYPE HTML>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <title>Directory listing for {display_path}</title>
            <style>
                body {{ font-family: monospace; margin: 40px; }}
                a {{ text-decoration: none; color: #0066cc; }}
                a:hover {{ text-decoration: underline; }}
                li {{ margin: 4px 0; }}
            </style>
        </head>
        <body>
            <h1>Directory listing for {display_path}</h1>
            <hr>
            <ul>
        """

        # Parent directory link (unless at root)
        if rel_path:
            parent = os.path.normpath(os.path.join(rel_path, ".."))
            parent_url = f"/{parent}/" if parent != "." else "/"
            html += f'<li><a href="{urllib.parse.quote(parent_url)}">../</a></li>\n'

        for name in files:
            fullname = os.path.join(path, name)
            display_name = name + "/" if os.path.isdir(fullname) else name
            url = urllib.parse.quote(name + ("/" if os.path.isdir(fullname) else ""))
            html += f'<li><a href="{url}">{display_name}</a></li>\n'

        html += """
            </ul>
            <hr>
        </body>
        </html>
        """
        self.wfile.write(html.encode("utf-8"))
        return None

    # ------------------------------------------------------------------
    # GET
    # ------------------------------------------------------------------
    def do_GET(self):
        if ".." in self.path:
            self.send_error(403, "Forbidden")
            return

        if self.path == "/" or self.path.endswith("/"):
            f = self.list_directory(os.path.join(DIRECTORY, self.path.lstrip("/").rstrip("/")))
            if f is None:
                return
            else:
                self.send_error(404, "Not found")
                return

        super().do_GET()

    # ------------------------------------------------------------------
    # POST - create/overwrite, append, mkdir
    # ------------------------------------------------------------------
    #def do_POST(self):
    #    if ".." in self.path:
    #        self.send_error(403, "Forbidden")
    #        return
    #    # === DEBUG LOGGING ===
    #    print(f"[SERVER DEBUG] POST received:")
    #    print(f"  Path: '{self.path}'")
    #    print(f"  Headers: {dict(self.headers)}")
    #    print(f"  X-Mkdir: {self.headers.get('X-Mkdir', 'NOT SET')}")
    #    
    #    length = int(self.headers.get('Content-Length', 0))
    #    data = self.rfile.read(length) if length > 0 else b""
    #
    #    filepath = os.path.join(DIRECTORY, self.path.lstrip("/"))
    #    print(f"  Full path: '{filepath}'")
    #    # === END DEBUG ===
    #    length = int(self.headers.get('Content-Length', 0))
    #    data = self.rfile.read(length) if length > 0 else b""
    #
    #    filepath = os.path.join(DIRECTORY, self.path.lstrip("/"))
    #    is_mkdir = self.headers.get("X-Mkdir", "").lower() == "true"
    #    
    #    if self.path.endswith("/") or is_mkdir:
    #        try:
    #            os.makedirs(filepath, exist_ok=True)
    #            self.send_response(201)
    #            self.send_header("Content-type", "text/plain")
    #            self.end_headers()
    #            self.wfile.write(b"Directory created")
    #            return
    #        except Exception as e:
    #            self.send_error(500, f"Failed to create directory: {e}")
    #            return
    #
    #    append = self.headers.get("X-Append", "").lower() == "true"
    #    mode = "ab" if append else "wb"
    #
    #    try:
    #        with open(filepath, mode) as f:
    #            f.write(data)
    #        self.send_response(200)
    #        self.send_header("Content-type", "text/plain")
    #        self.end_headers()
    #        self.wfile.write(b"OK")
    #    except Exception as e:
    #        self.send_error(500, f"Failed to write file: {e}")

    def do_POST(self):
        if ".." in self.path:
            self.send_error(403, "Forbidden")
            return
            
        # === DEBUG LOGGING ===
        print(f"[SERVER DEBUG] POST received:")
        print(f"  Path: '{self.path}'")
        print(f"  Headers: {dict(self.headers)}")
        print(f"  X-Mkdir: {self.headers.get('X-Mkdir', 'NOT SET')}")
        
        length = int(self.headers.get('Content-Length', 0))
        data = self.rfile.read(length) if length > 0 else b""
    
        filepath = os.path.join(DIRECTORY, self.path.lstrip("/"))
        print(f"  Full path: '{filepath}'")
        print(f"  Data length actually read: {len(data)}")
        # === END DEBUG ===
        
        # REMOVE THESE DUPLICATE LINES:
        # length = int(self.headers.get('Content-Length', 0))
        # data = self.rfile.read(length) if length > 0 else b""

        filepath = os.path.join(DIRECTORY, self.path.lstrip("/"))
        is_mkdir = self.headers.get("X-Mkdir", "").lower() == "true"
        
        # Handle RENAME operation via custom header
        rename_dest = self.headers.get("X-Rename-To")
        if rename_dest:
            try:
                dest_path = os.path.join(DIRECTORY, rename_dest.lstrip('/'))
                os.rename(filepath, dest_path)
                self.send_response(200)
                self.send_header("Content-type", "text/plain")
                self.end_headers()
                self.wfile.write(b"Renamed")
            except Exception as e:
                self.send_error(500, f"Rename failed: {e}")
            return

        # Handle COPY operation via custom header
        copy_dest = self.headers.get("X-Copy-To")
        if copy_dest:
            try:
                dest_path = os.path.join(DIRECTORY, copy_dest.lstrip('/'))
                shutil.copy2(filepath, dest_path)
                self.send_response(200)
                self.send_header("Content-type", "text/plain")
                self.end_headers()
                self.wfile.write(b"Copied")
            except Exception as e:
                self.send_error(500, f"Copy failed: {e}")
            return

        if self.path.endswith("/") or is_mkdir:
            try:
                os.makedirs(filepath, exist_ok=True)
                self.send_response(201)
                self.send_header("Content-type", "text/plain")
                self.end_headers()
                self.wfile.write(b"Directory created")
                return
            except Exception as e:
                self.send_error(500, f"Failed to create directory: {e}")
                return

        append = self.headers.get("X-Append", "").lower() == "true"
        mode = "ab" if append else "wb"

        try:
            with open(filepath, mode) as f:
                f.write(data)
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK")
        except Exception as e:
            self.send_error(500, f"Failed to write file: {e}")

    # ------------------------------------------------------------------
    # DELETE - file or empty directory
    # ------------------------------------------------------------------
    def do_DELETE(self):
        if ".." in self.path:
            self.send_error(403, "Forbidden")
            return

        filepath = os.path.join(DIRECTORY, self.path.lstrip("/"))

        # ========== MINIMAL DEBUG ==========
        print(f"[SERVER] DELETE: '{self.path}' (ends with /: {self.path.endswith('/')})")
        # ========== END DEBUG ==========

        if not os.path.exists(filepath):
            self.send_error(404, "Not found")
            return

        try:
            if os.path.isdir(filepath):
                if not self.path.endswith("/"):
                    self.send_error(400, "Use trailing / to delete directory")
                    return
                os.rmdir(filepath)
            else:
                os.remove(filepath)

            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Deleted")
        except IsADirectoryError:
            self.send_error(400, "Directory not empty")
        except PermissionError:
            self.send_error(403, "Permission denied")
        except Exception as e:
            self.send_error(500, f"Delete failed: {e}")

# ========================
# Start server
# ========================
if __name__ == "__main__":
    os.makedirs(DIRECTORY, exist_ok=True)
    os.chdir(DIRECTORY)

    PORT = 8000
    server_address = ("0.0.0.0", PORT)

    # Auto-detect local IP
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        local_ip = "127.0.0.1"

    HTTPServer.allow_reuse_address = True
    httpd = HTTPServer(server_address, PicoFileHandler)

    print(f"Pico W Remote Filesystem Server running")
    print(f"URL: http://{local_ip}:{PORT}/")
    print(f"Serving: {os.path.abspath(DIRECTORY)}")
    print("Supported: DIR, GET, POST, APPEND, MKDIR, DEL, RMDIR, CD")
    print("Press Ctrl+C to stop")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
        httpd.server_close()
