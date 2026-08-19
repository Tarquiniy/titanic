import os

from waitress import serve

from app import app


def _env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        return default


def main() -> None:
    host = os.getenv("HOST", "0.0.0.0")
    port = _env_int("PORT", 8080)

    # Tuned for ~200 simultaneous users on a single instance.
    threads = _env_int("WAITRESS_THREADS", 32)
    connection_limit = _env_int("WAITRESS_CONNECTION_LIMIT", 1000)
    backlog = _env_int("WAITRESS_BACKLOG", 2048)
    channel_timeout = _env_int("WAITRESS_CHANNEL_TIMEOUT", 120)
    cleanup_interval = _env_int("WAITRESS_CLEANUP_INTERVAL", 30)

    serve(
        app,
        host=host,
        port=port,
        threads=threads,
        connection_limit=connection_limit,
        backlog=backlog,
        channel_timeout=channel_timeout,
        cleanup_interval=cleanup_interval,
    )


if __name__ == "__main__":
    main()
