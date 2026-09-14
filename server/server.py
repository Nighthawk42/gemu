#!/usr/bin/env python3
"""
GMod Multi-Emulator Local Server
Serves static files from ../web with CORS and proper MIME types for ROMs and cores.
"""

import os
import sys
import json
import mimetypes
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse, unquote

PORT = int(os.environ.get("PORT", 8080))
WEB_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "web"))

# Ensure proper MIME types
mimetypes.init()
mimetypes.add_type("application/javascript", ".js")
mimetypes.add_type("application/octet-stream", ".smc")
mimetypes.add_type("application/octet-stream", ".sfc")
mimetypes.add_type("application/octet-stream", ".srm")
mimetypes.add_type("application/octet-stream", ".state")
mimetypes.add_type("application/octet-stream", ".gba")
mimetypes.add_type("application/octet-stream", ".nes")
mimetypes.add_type("application/octet-stream", ".bin")
for extension in (".gb", ".gbc", ".md", ".gen"):
    mimetypes.add_type("application/octet-stream", extension)

class EmuRequestHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        pathname = unquote(parsed.path)

        if pathname == "/api/status":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            data = json.dumps({
                "status": "ok",
                "service": "gmod-emu-server",
                "version": "1.0.0"
            })
            self.wfile.write(data.encode("utf-8"))
            return

        if pathname == "/api/roms":
            roms_json_path = os.path.join(WEB_DIR, "roms.json")
            if os.path.exists(roms_json_path):
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                with open(roms_json_path, "rb") as f:
                    self.wfile.write(f.read())
            else:
                self.send_response(404)
                self.end_headers()
            return

        super().do_GET()

def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), EmuRequestHandler)
    print(f"[gmod-emu-server] Serving {WEB_DIR} on http://localhost:{PORT}")
    print("[gmod-emu-server] Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[gmod-emu-server] Shutting down.")
        server.server_close()

if __name__ == "__main__":
    main()
