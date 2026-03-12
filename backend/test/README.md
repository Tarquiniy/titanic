# Нагрузочное тестирование в локальной сети

В этой папке лежит готовый набор для нагрузочного тестирования в LAN.

## Файлы

- `load_test.py` - основной скрипт теста
- `scenario.local.json` - сценарий по умолчанию
- `run_local_network.ps1` - запуск через PowerShell
- `results/` - отчеты (`.json` + `.txt`)

## 1) Подготовка сервисов

1. Запустите Supabase (Docker) и сервер приложения.
2. Убедитесь, что приложение доступно в LAN:
   - `http://192.168.10.10:8080/`
   - `http://192.168.10.10:8080/api/health`

## 2) Запуск теста по умолчанию (ровно 200 одновременных)

From repository root:

```powershell
powershell -ExecutionPolicy Bypass -File backend/test/run_local_network.ps1
```

## 3) Кастомный запуск

```powershell
powershell -ExecutionPolicy Bypass -File backend/test/run_local_network.ps1 `
  -BaseUrl "http://192.168.10.10:8080" `
  -Concurrency 200 `
  -DurationSeconds 120 `
  -RampUpSeconds 30 `
  -TimeoutSeconds 5 `
  -Endpoints "/api/health:7,/:3"
```

## 4) Прямой запуск Python (опционально)

```powershell
cd backend
poetry run python test/load_test.py --scenario test/scenario.local.json
```

## 5) Что смотреть в отчете

- `requests_per_second` - пропускная способность
- `error_rate_percent` - процент ошибок
- `latency_ms.p95` и `latency_ms.p99` - хвостовые задержки
- `status_codes` - распределение HTTP-кодов
- `errors` - сетевые/транспортные ошибки

## Рекомендованный базовый порог

- `error_rate_percent < 1.0`
- `p95 < 500 ms` for `/api/health`
- stable throughput without growth of transport errors
