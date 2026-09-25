"""Serve an exported web build the way Vercel will serve it.

Usage: python tools/serve_web.py <web-build-dir> [port]

`python -m http.server` is not good enough for testing a Godot web export:

  * on Windows it answers `.js` with `text/plain` (the MIME database follows a
    polluted registry entry), and an AudioWorklet module served as text/plain is
    rejected by the browser -- Godot then quietly falls back to its dummy audio
    driver, so a perfectly good build looks silent;
  * it sends none of the headers `vercel.json` sends.

So the rehearsal server below pins the MIME types that matter (javascript,
wasm, pck) and mirrors the production headers. If the export works here it
works on Vercel, and a failure here is reproducible instead of mysterious.
"""

import functools
import http.server
import pathlib
import sys

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".png": "image/png",
    ".json": "application/json",
}

HEADERS = {
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
    "X-Content-Type-Options": "nosniff",
    # **本地调试一律不缓存。** 天真的静态服务不发 Cache-Control，浏览器就会
    # 用启发式缓存把 index.pck / index.js 留在本地：改完代码刷新页面，
    # 看到的还是上一次的构建——界面还是豆腐块、鼠标还是锁不住，
    # 而人对着一个已经修好的构建找 bug。
    "Cache-Control": "no-cache, must-revalidate",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def guess_type(self, path):
        suffix = pathlib.Path(path).suffix.lower()
        if suffix in MIME:
            return MIME[suffix]
        return super().guess_type(path)

    def end_headers(self):
        for key, value in HEADERS.items():
            self.send_header(key, value)
        super().end_headers()

    def log_message(self, fmt, *args):
        pass


def main() -> None:
    directory = sys.argv[1]
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8100
    handler = functools.partial(Handler, directory=directory)
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), handler) as httpd:
        print("serving %s at http://127.0.0.1:%d/" % (directory, port), flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
