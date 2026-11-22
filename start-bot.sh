#!/bin/sh
set -eu
# Keep the operator's config intact and readable at its original path.
exec python - <<'PY'
import json
import os
import socket
import sys
import time
from pathlib import Path

source = Path(os.environ.get("BOT_CONFIG", "/run/bridge/config.json"))
config = json.loads(source.read_text(encoding="utf-8-sig"))
if os.getuid() == 0:
    os.setgroups([])
    os.setgid(10001)
    os.setuid(10001)
host = os.environ["LOCAL_API_HOST"]
config.setdefault("LOCAL_API", {}).update(
    enabled=True, host=host, port=8081, start_server=False
)
token_key = {"bridge.py": "TELEGRAM_BOT_TOKEN", "bridge2.py": "TG_BOT_TOKEN"}[
    os.environ["BOT_ENTRY"]
]
if not config.get(token_key):
    raise SystemExit(f"Missing {token_key} in bot config")
for _ in range(30):
    try:
        with socket.create_connection((host, 8081), timeout=2):
            break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit("Local Telegram Bot API did not open port 8081")
os.umask(0o077)
Path("config.json").write_text(json.dumps(config, ensure_ascii=False), encoding="utf-8")
entry = os.environ["BOT_ENTRY"]
directory = Path(os.environ.get("BOT_DIRECTORY", "/app"))
os.execv(sys.executable, [sys.executable, str(directory / entry)])
PY
