# titanic

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Flask backend (Poetry + Waitress/Gunicorn)

Server runs Python API and serves Flutter Web build from `build/web`.

1. Install dependencies with Poetry:
   - `cd backend`
   - `poetry install`
2. Build Flutter web app:
   - `cd ..`
   - `flutter build web`
3. Run on Windows (Waitress, tuned for ~200 concurrent users):
   - `cd backend`
   - `poetry run python serve.py`
4. Run on Linux/macOS (Gunicorn):
   - `poetry run gunicorn -w 4 --threads 50 -k gthread -b 192.168.10.10:8080 app:app`
5. Local dev run (without production server):
   - `poetry run python app.py`

Waitress tuning (optional via env):
- `WAITRESS_THREADS` (default `32`)
- `WAITRESS_CONNECTION_LIMIT` (default `1000`)
- `WAITRESS_BACKLOG` (default `2048`)
- `WAITRESS_CHANNEL_TIMEOUT` (default `120`)
- `WAITRESS_CLEANUP_INTERVAL` (default `30`)

Available endpoints:
- `GET /` (Flutter web app)
- `GET /api`
- `GET /api/health`
