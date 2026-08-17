#!/usr/bin/env python3
"""Reverse proxy for ollama that keeps the system prefix cached.

llama-server reuses a cached sequence only when the new prompt extends it, so
after a conversation leaves [system][user][assistant] in the slot, the next
conversation's [system][user'] diverges and the whole system prompt is
recomputed -- measured at 0.65 s against 0.19 s here, on every command.

After each /api/chat we replay that exact request with the conversation
stripped: system message and tools only. That is a prefix of what is cached, so
it costs ~0.1 s, and it leaves the slot holding exactly the prefix, so the next
conversation extends it. Replaying the caller's own payload rather than
rebuilding it means the bytes match by construction, including tool schemas,
and it keeps matching when Home Assistant's prompt changes.
"""
import json, os, threading, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = os.environ.get("PRIMER_UPSTREAM", "http://127.0.0.1:11435")
HOST     = os.environ.get("PRIMER_HOST", "127.0.0.1")
PORT     = int(os.environ.get("PRIMER_PORT", "11434"))

_lock = threading.Lock()

def prime(payload):
    sys_msgs = [m for m in payload.get("messages", []) if m.get("role") == "system"]
    if not sys_msgs or not payload.get("model"):
        return
    body = {"model": payload["model"], "messages": sys_msgs, "stream": False,
            "options": {**payload.get("options", {}), "num_predict": 1},
            "keep_alive": payload.get("keep_alive", -1)}
    if "tools" in payload:
        body["tools"] = payload["tools"]
    req = urllib.request.Request(UPSTREAM + "/api/chat",
                                 data=json.dumps(body).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    with _lock:                      # never race a real request
        try:
            urllib.request.urlopen(req, timeout=300).read()
        except Exception:
            pass

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass

    def _relay(self, method):
        body = None
        n = int(self.headers.get("Content-Length") or 0)
        if n:
            body = self.rfile.read(n)
        req = urllib.request.Request(UPSTREAM + self.path, data=body, method=method)
        for k, v in self.headers.items():
            if k.lower() not in ("host", "content-length", "connection", "accept-encoding"):
                req.add_header(k, v)
        try:
            with _lock:
                pass                 # wait for any in-flight prime to finish
            r = urllib.request.urlopen(req, timeout=3600)
        except urllib.error.HTTPError as e:
            data = e.read()
            self.send_response(e.code)
            self.send_header("Content-Type", e.headers.get("Content-Type", "application/json"))
            self.send_header("Content-Length", str(len(data)))
            self.end_headers(); self.wfile.write(data)
            return
        except Exception:
            self.send_response(502); self.send_header("Content-Length", "0")
            self.end_headers()
            return

        self.send_response(r.status)
        self.send_header("Content-Type", r.headers.get("Content-Type", "application/json"))
        self.send_header("Transfer-Encoding", "chunked")   # stream through
        self.end_headers()
        try:
            while True:
                chunk = r.read(4096)
                if not chunk:
                    break
                self.wfile.write(b"%X\r\n%s\r\n" % (len(chunk), chunk))
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n"); self.wfile.flush()
        except Exception:
            return

        if method == "POST" and self.path.rstrip("/") == "/api/chat" and body:
            try:
                payload = json.loads(body)
            except Exception:
                return
            threading.Thread(target=prime, args=(payload,), daemon=True).start()

    def do_GET(self):    self._relay("GET")
    def do_POST(self):   self._relay("POST")
    def do_DELETE(self): self._relay("DELETE")
    def do_HEAD(self):   self._relay("HEAD")

if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
