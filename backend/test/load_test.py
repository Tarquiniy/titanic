from __future__ import annotations

import argparse
import http.client
import json
import random
import ssl
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


@dataclass(frozen=True)
class Endpoint:
    path: str
    weight: int = 1


class EndpointChooser:
    def __init__(self, endpoints: list[Endpoint]) -> None:
        if not endpoints:
            raise ValueError("At least one endpoint is required")
        total = 0
        self._cumulative: list[tuple[int, str]] = []
        for item in endpoints:
            if item.weight <= 0:
                continue
            total += item.weight
            self._cumulative.append((total, item.path))
        if total <= 0:
            raise ValueError("Endpoint weights must be > 0")
        self._total_weight = total

    def pick(self) -> str:
        value = random.randint(1, self._total_weight)
        for cumulative, path in self._cumulative:
            if value <= cumulative:
                return path
        return self._cumulative[-1][1]


class Stats:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.started_at = time.perf_counter()
        self.finished_at = self.started_at
        self.total = 0
        self.success = 0
        self.failed = 0
        self.latencies_ms: list[float] = []
        self.status_codes: dict[str, int] = {}
        self.errors: dict[str, int] = {}

    def record(self, latency_ms: float, status_code: int | None, error: str | None) -> None:
        with self._lock:
            self.total += 1
            self.latencies_ms.append(latency_ms)
            if status_code is not None:
                key = str(status_code)
                self.status_codes[key] = self.status_codes.get(key, 0) + 1
                if 200 <= status_code < 400:
                    self.success += 1
                else:
                    self.failed += 1
            else:
                self.failed += 1

            if error:
                self.errors[error] = self.errors.get(error, 0) + 1

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            now = time.perf_counter()
            elapsed = max(now - self.started_at, 1e-9)
            return {
                "total": self.total,
                "success": self.success,
                "failed": self.failed,
                "rps": self.total / elapsed,
            }

    def close(self) -> None:
        self.finished_at = time.perf_counter()

    def summary(self) -> dict[str, Any]:
        elapsed = max(self.finished_at - self.started_at, 1e-9)
        latencies = sorted(self.latencies_ms)

        def percentile(p: float) -> float:
            if not latencies:
                return 0.0
            index = int(round((p / 100.0) * (len(latencies) - 1)))
            return latencies[index]

        return {
            "duration_seconds": elapsed,
            "total_requests": self.total,
            "successful_requests": self.success,
            "failed_requests": self.failed,
            "error_rate_percent": (self.failed / self.total * 100.0) if self.total else 0.0,
            "requests_per_second": self.total / elapsed,
            "latency_ms": {
                "min": latencies[0] if latencies else 0.0,
                "avg": sum(latencies) / len(latencies) if latencies else 0.0,
                "p50": percentile(50),
                "p90": percentile(90),
                "p95": percentile(95),
                "p99": percentile(99),
                "max": latencies[-1] if latencies else 0.0,
            },
            "status_codes": dict(sorted(self.status_codes.items())),
            "errors": dict(sorted(self.errors.items())),
        }


def _create_connection(parsed_url: Any, timeout_seconds: float) -> http.client.HTTPConnection:
    if parsed_url.scheme == "https":
        context = ssl.create_default_context()
        return http.client.HTTPSConnection(parsed_url.hostname, parsed_url.port, timeout=timeout_seconds, context=context)
    return http.client.HTTPConnection(parsed_url.hostname, parsed_url.port, timeout=timeout_seconds)


def _worker(
    worker_id: int,
    parsed_url: Any,
    chooser: EndpointChooser,
    method: str,
    timeout_seconds: float,
    stop_time: float,
    stats: Stats,
    ramp_delay_seconds: float,
) -> None:
    if ramp_delay_seconds > 0:
        time.sleep(ramp_delay_seconds)

    connection: http.client.HTTPConnection | None = None
    headers = {"Connection": "keep-alive", "Accept": "*/*"}

    while time.perf_counter() < stop_time:
        if connection is None:
            try:
                connection = _create_connection(parsed_url, timeout_seconds)
            except Exception as exc:
                stats.record(0.0, None, f"connect:{type(exc).__name__}")
                continue

        path = chooser.pick()
        start = time.perf_counter()
        try:
            connection.request(method, path, headers=headers)
            response = connection.getresponse()
            response.read()
            latency_ms = (time.perf_counter() - start) * 1000.0
            stats.record(latency_ms, int(response.status), None)
        except Exception as exc:
            latency_ms = (time.perf_counter() - start) * 1000.0
            stats.record(latency_ms, None, f"request:{type(exc).__name__}")
            try:
                connection.close()
            except Exception:
                pass
            connection = None

    if connection is not None:
        try:
            connection.close()
        except Exception:
            pass


def _parse_endpoints(raw: str) -> list[Endpoint]:
    result: list[Endpoint] = []
    for chunk in raw.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        if ":" in chunk:
            path, weight_raw = chunk.rsplit(":", 1)
            weight = int(weight_raw.strip())
        else:
            path = chunk
            weight = 1
        path = path.strip()
        if not path.startswith("/"):
            path = f"/{path}"
        result.append(Endpoint(path=path, weight=weight))
    return result


def _load_scenario(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def _format_summary_text(config: dict[str, Any], summary: dict[str, Any]) -> str:
    latency = summary["latency_ms"]
    lines = [
        "Итоги нагрузочного теста",
        "========================",
        f"цель: {config['base_url']}",
        f"одновременных пользователей: {config['concurrency']}",
        f"длительность_сек: {config['duration_seconds']}",
        f"плавный_разгон_сек: {config['ramp_up_seconds']}",
        f"таймаут_сек: {config['timeout_seconds']}",
        f"метод: {config['method']}",
        f"эндпоинты: {config['endpoints_spec']}",
        "",
        f"всего_запросов: {summary['total_requests']}",
        f"успешных_запросов: {summary['successful_requests']}",
        f"ошибочных_запросов: {summary['failed_requests']}",
        f"доля_ошибок_проц: {summary['error_rate_percent']:.2f}",
        f"запросов_в_секунду: {summary['requests_per_second']:.2f}",
        "",
        "задержка_мс:",
        f"  min: {latency['min']:.2f}",
        f"  avg: {latency['avg']:.2f}",
        f"  p50: {latency['p50']:.2f}",
        f"  p90: {latency['p90']:.2f}",
        f"  p95: {latency['p95']:.2f}",
        f"  p99: {latency['p99']:.2f}",
        f"  max: {latency['max']:.2f}",
        "",
        f"коды_http: {summary['status_codes']}",
        f"ошибки: {summary['errors']}",
    ]
    return "\n".join(lines) + "\n"


def run_load_test(
    base_url: str,
    concurrency: int,
    duration_seconds: int,
    timeout_seconds: float,
    method: str,
    endpoints: list[Endpoint],
    ramp_up_seconds: int,
    show_progress: bool,
) -> dict[str, Any]:
    parsed = urlparse(base_url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError("base_url must start with http:// or https://")
    if not parsed.hostname:
        raise ValueError("base_url must include host")
    if parsed.port is None:
        parsed = parsed._replace(port=(443 if parsed.scheme == "https" else 80))

    chooser = EndpointChooser(endpoints)
    stats = Stats()
    workers: list[threading.Thread] = []
    stop_time = time.perf_counter() + duration_seconds

    for i in range(concurrency):
        delay = (ramp_up_seconds * i / concurrency) if ramp_up_seconds > 0 else 0.0
        t = threading.Thread(
            target=_worker,
            args=(
                i,
                parsed,
                chooser,
                method,
                timeout_seconds,
                stop_time,
                stats,
                delay,
            ),
            daemon=True,
        )
        workers.append(t)
        t.start()

    if show_progress:
        while time.perf_counter() < stop_time:
            snap = stats.snapshot()
            print(
                f"[прогресс] всего={snap['total']} успешно={snap['success']} "
                f"ошибок={snap['failed']} rps={snap['rps']:.1f}"
            )
            time.sleep(1)

    for t in workers:
        t.join()

    stats.close()
    return stats.summary()


def main() -> None:
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="Нагрузочное тестирование для backend/web в локальной сети")
    parser.add_argument("--scenario", default=str(script_dir / "scenario.local.json"), help="Путь к JSON-сценарию")
    parser.add_argument("--base-url", default=None, help="URL цели, например http://192.168.10.10:8080")
    parser.add_argument("--concurrency", type=int, default=None, help="Количество одновременных воркеров")
    parser.add_argument("--duration", type=int, default=None, help="Длительность теста в секундах")
    parser.add_argument("--timeout", type=float, default=None, help="Таймаут одного запроса в секундах")
    parser.add_argument("--method", default=None, help="HTTP метод")
    parser.add_argument(
        "--endpoints",
        default=None,
        help="Список эндпоинтов через запятую с весами, например /api/health:8,/:2",
    )
    parser.add_argument("--ramp-up", type=int, default=None, help="Плавный разгон нагрузки в секундах")
    parser.add_argument("--no-progress", action="store_true", help="Отключить вывод прогресса каждую секунду")
    args = parser.parse_args()

    scenario = _load_scenario(Path(args.scenario))
    base_url = args.base_url or scenario.get("base_url", "http://192.168.10.10:8080")
    concurrency = args.concurrency or int(scenario.get("concurrency", 200))
    duration_seconds = args.duration or int(scenario.get("duration_seconds", 60))
    timeout_seconds = args.timeout or float(scenario.get("timeout_seconds", 5.0))
    method = (args.method or scenario.get("method", "GET")).upper()
    endpoints_spec = args.endpoints or scenario.get("endpoints", "/api/health:8,/:2")
    ramp_up_seconds = args.ramp_up if args.ramp_up is not None else int(scenario.get("ramp_up_seconds", 0))
    show_progress = not args.no_progress

    endpoints = _parse_endpoints(endpoints_spec)
    config = {
        "base_url": base_url,
        "concurrency": concurrency,
        "duration_seconds": duration_seconds,
        "timeout_seconds": timeout_seconds,
        "method": method,
        "endpoints_spec": endpoints_spec,
        "ramp_up_seconds": ramp_up_seconds,
        "scenario_file": str(Path(args.scenario).resolve()),
    }

    print("[нагрузочный-тест] конфигурация:")
    print(json.dumps(config, indent=2, ensure_ascii=False))

    started_at = datetime.now(timezone.utc).isoformat()
    summary = run_load_test(
        base_url=base_url,
        concurrency=concurrency,
        duration_seconds=duration_seconds,
        timeout_seconds=timeout_seconds,
        method=method,
        endpoints=endpoints,
        ramp_up_seconds=ramp_up_seconds,
        show_progress=show_progress,
    )
    finished_at = datetime.now(timezone.utc).isoformat()

    result = {
        "started_at_utc": started_at,
        "finished_at_utc": finished_at,
        "config": config,
        "summary": summary,
    }

    results_dir = script_dir / "results"
    results_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    json_path = results_dir / f"load_test_{stamp}.json"
    txt_path = results_dir / f"load_test_{stamp}.txt"

    json_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    txt_path.write_text(_format_summary_text(config, summary), encoding="utf-8")

    print("[нагрузочный-тест] выполнено")
    print(f"[нагрузочный-тест] json: {json_path}")
    print(f"[нагрузочный-тест] text: {txt_path}")
    print(_format_summary_text(config, summary))


if __name__ == "__main__":
    main()
