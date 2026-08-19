# Titanic

Titanic — это проект “клиент + бекенд”:

- **Flutter (web/mobile)** — фронтенд, работающий через **Supabase** (auth/data/realtime).
- **Python/Flask** — поднимает HTTP сервер в локальной сети и **раздаёт билд Flutter web** из `build/web`, плюс даёт небольшой health-check API.

## Архитектура

1. `flutter build web --release` собирает фронтенд в `build/web`.
2. `backend/serve.py` (Waitress) или `backend/app.py`/Gunicorn поднимают Flask и:
   - раздают статику Flutter web (`GET /`, любые `/<path>`),
   - предоставляют API endpoints (`/api`, `/api/health`).

## Стек

- Flutter / Dart
- `supabase_flutter`
- Python 3.11+
- Flask + Gunicorn (Linux/macOS) / Waitress (Windows)
- Supabase DB — схема и функции в `schema.sql`

## Требования

- Flutter SDK
- Python + Poetry (`poetry install`)
- Supabase (рекомендуется локально через Supabase CLI)
- Для web-сборки CI: нужен Chrome (используется GitHub Actions)

## Конфигурация

### Flutter: переменные для Supabase (build-time)

Приложение использует `--dart-define`:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Пример для запуска:

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL="http://localhost:8000" \
  --dart-define=SUPABASE_ANON_KEY="YOUR_ANON_KEY"
```

Для сборки web:

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL="http://localhost:8000" \
  --dart-define=SUPABASE_ANON_KEY="YOUR_ANON_KEY"
```

> Примечание: если значения не передать, приложение переключится на dev-поведение (в т.ч. с fallback URL и ключом). Для продакшена **обязательно** передавайте оба значения.

### Backend: переменные окружения

По умолчанию сервер слушает **`0.0.0.0:8080`**:

- `HOST` (default: `0.0.0.0`)
- `PORT` (default: `8080`)

Настройка Waitress (для Windows и/или при запуске через `serve.py`):

- `WAITRESS_THREADS` (default: `32`)
- `WAITRESS_CONNECTION_LIMIT` (default: `1000`)
- `WAITRESS_BACKLOG` (default: `2048`)
- `WAITRESS_CHANNEL_TIMEOUT` (default: `120`)
- `WAITRESS_CLEANUP_INTERVAL` (default: `30`)

## Локальная разработка (рекомендуемый сценарий)

### 1) Поднимите Supabase

Обычно:

```bash
supabase init
supabase start
```

По умолчанию Supabase local доступен по `http://localhost:8000`.

### 2) Соберите Flutter web

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL="http://localhost:8000" \
  --dart-define=SUPABASE_ANON_KEY="YOUR_ANON_KEY"
```

### 3) Запустите backend

```bash
cd backend
poetry install
poetry run python serve.py
```

После этого откройте:

- `http://localhost:8080/`
- `http://localhost:8080/api/health`

## API endpoints

- `GET /` — Flutter web app
- `GET /api` — сервисный health (кратко)
- `GET /api/health` — `{"status": "healthy"}`

## Supabase: схема БД

Примените `schema.sql` в SQL Editor вашего Supabase проекта.

## Деплой (GitHub Actions → Vercel)

CI workflow `./.github/workflows/build-and-deploy.yml` собирает Flutter web и деплоит статику из `build/web`.

В GitHub Secrets нужны:

- `VERCEL_TOKEN`
- `VERCEL_ORG_ID`
- `VERCEL_PROJECT_ID`

Также, чтобы Flutter собрался с корректными настройками Supabase:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

## Нагрузочное тестирование (backend)

См. `backend/test/README.md`.
