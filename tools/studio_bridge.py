"""Local bridge for Roblox Studio: GET serves repo files, POST /dump/<name> saves JSON to dump dir."""
import http.server
import sys
from pathlib import Path

REPO = Path(sys.argv[1]).resolve()
DUMP = Path(sys.argv[2]).resolve()
DUMP.mkdir(parents=True, exist_ok=True)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(REPO), **kwargs)

    def do_POST(self):
        name = self.path.split("?")[0].rsplit("/", 1)[-1]
        if not name.replace("_", "").isalnum():
            self.send_error(400)
            return
        length = int(self.headers.get("Content-Length", 0))
        (DUMP / f"{name}.json").write_bytes(self.rfile.read(length))
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", 34999), Handler).serve_forever()
