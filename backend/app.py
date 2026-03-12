import os
from pathlib import Path

from flask import Flask, jsonify, send_from_directory

WEB_BUILD_DIR = (Path(__file__).resolve().parent.parent / "build" / "web").resolve()

app = Flask(__name__)


@app.get("/api")
def api_index():
    return jsonify({"service": "titanic-backend", "status": "ok"})


@app.get("/api/health")
def health():
    return jsonify({"status": "healthy"})


@app.route("/", defaults={"path": ""})
@app.route("/<path:path>")
def serve_flutter(path: str):
    if not WEB_BUILD_DIR.exists():
        return (
            "Flutter web build not found. Run: flutter build web",
            404,
        )

    requested = WEB_BUILD_DIR / path
    if path and requested.exists() and requested.is_file():
        return send_from_directory(WEB_BUILD_DIR, path)

    return send_from_directory(WEB_BUILD_DIR, "index.html")


if __name__ == "__main__":
    app.run(
        host=os.getenv("HOST", "192.168.10.10"),
        port=int(os.getenv("PORT", "8080")),
        debug=False,
    )
