#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

case "${1:-}" in
    1|rubika) bots=(rubika); dashboard=0 ;;
    2|bale) bots=(bale); dashboard=0 ;;
    3|both) bots=(rubika bale); dashboard=0 ;;
    4|all) bots=(rubika bale); dashboard=1 ;;
    *) echo "Usage: sudo bash install-systemd.sh {1|2|3|4}" >&2; exit 2 ;;
esac
if [[ $EUID != 0 || ! -d /run/systemd/system ]]; then
    echo "Run as root on a Linux host booted with systemd." >&2
    exit 1
fi

mkdir -p config sources
[[ -f .env ]] || (umask 077; cp .env.example .env)
for bot in "${bots[@]}"; do
    if [[ ! -f config/$bot.json ]]; then
        echo "Create config/$bot.json using the bot repository's documented settings." >&2
        exit 1
    fi
done
if (( dashboard )) && [[ ! -f config/dashboard-start.sh ]]; then
    echo "Create config/dashboard-start.sh using the dashboard repository's native launch command." >&2
    exit 1
fi

apt-get update
apt-get install -y ca-certificates git python3 python3-venv ffmpeg libstdc++6 zlib1g
clone() {
    local repo=$1
    if [[ ! -d sources/$repo ]]; then
        runuser -u "${SUDO_USER:-root}" -- git clone "https://github.com/shiny222/$repo.git" "sources/$repo"
    fi
}

# Let Git use the invoking user's credentials when sudo was used.
if [[ -n ${SUDO_USER:-} && $(stat -c %u sources) == 0 ]]; then
    chown "$SUDO_USER" sources
fi
if [[ -z ${TELEGRAM_API_BINARY:-} ]]; then
    clone telegram-bot-api
fi
api_binary=${TELEGRAM_API_BINARY:-sources/telegram-bot-api/telegram-bot-api}
if [[ ! -f $api_binary ]]; then
    echo "Supply a compatible Linux executable via TELEGRAM_API_BINARY." >&2
    exit 1
fi
for bot in "${bots[@]}"; do clone "telegram-to-$bot"; done
if (( dashboard )); then clone dashbord-bale-rubika; fi

id telegram-bridge >/dev/null 2>&1 || useradd --system --user-group --no-create-home --shell /usr/sbin/nologin telegram-bridge
app=/opt/telegram-bridges
state=/var/lib/telegram-bridges
install -d -m 0755 "$app" "$state"
install -d -m 0750 -o telegram-bridge -g telegram-bridge "$state/api"
install -d -m 0750 /etc/telegram-bridges
umask 077
api_env=$(mktemp /etc/telegram-bridges/api.XXXXXX)
trap 'rm -f -- "$api_env"' EXIT
python3 - "$api_env" "${bots[@]}" <<'PY'
import json
import re
import sys
from pathlib import Path

settings = {}
for line in Path(".env").read_text(encoding="utf-8-sig").splitlines():
    key, _, value = line.strip().partition("=")
    settings[key] = value.strip()
api_id = settings.get("TELEGRAM_API_ID", "")
api_hash = settings.get("TELEGRAM_API_HASH", "")
if not re.fullmatch(r"[1-9][0-9]*", api_id) or not re.fullmatch(r"[0-9a-fA-F]{32}", api_hash):
    raise SystemExit("Set TELEGRAM_API_ID and TELEGRAM_API_HASH in .env (plain KEY=value).")
tokens = []
for bot in sys.argv[2:]:
    config = json.loads(Path(f"config/{bot}.json").read_text(encoding="utf-8-sig"))
    key = "TG_BOT_TOKEN" if bot == "bale" else "TELEGRAM_BOT_TOKEN"
    if not config.get(key):
        raise SystemExit(f"Missing {key} in config/{bot}.json")
    tokens.append(config[key])
if len(tokens) != len(set(tokens)):
    raise SystemExit("Rubika and Bale need distinct Telegram bot tokens for polling.")
Path(sys.argv[1]).write_text(f"TELEGRAM_API_ID={api_id}\nTELEGRAM_API_HASH={api_hash}\n")
PY
mv -f -- "$api_env" /etc/telegram-bridges/api.env
umask 022

install -m 0755 "$api_binary" "$app/telegram-bot-api"
runuser -u telegram-bridge -- "$app/telegram-bot-api" --help >/dev/null
cat >/etc/systemd/system/telegram-bridge-api.service <<UNIT
[Unit]
Description=Local Telegram Bot API for the bridges
Wants=network-online.target
After=network-online.target

[Service]
User=telegram-bridge
WorkingDirectory=$state/api
EnvironmentFile=/etc/telegram-bridges/api.env
ExecStart=$app/telegram-bot-api --local --http-ip-address=127.0.0.1 --http-port=8081 --dir=$state/api --temp-dir=$state/api
Restart=on-failure
RestartSec=5s
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
UNIT

services=(telegram-bridge-api.service)
for bot in "${bots[@]}"; do
    source_dir=sources/telegram-to-$bot
    entry=bridge.py
    [[ $bot != bale ]] || entry=bridge2.py
    install -d -m 0755 "$app/$bot"
    install -d -m 0750 -o telegram-bridge -g telegram-bridge "$state/$bot"
    install -m 0644 "$source_dir/$entry" "$app/$bot/$entry"
    install -m 0755 start-bot.sh "$app/$bot/start-bot.sh"
    install -m 0640 -g telegram-bridge config/"$bot".json "$state/$bot/source.json"
    python3 -m venv "$app/$bot/venv"
    if [[ -f $source_dir/requirements.txt ]]; then
        "$app/$bot/venv/bin/pip" install -r "$source_dir/requirements.txt"
    else
        "$app/$bot/venv/bin/pip" install python-telegram-bot==21.6 requests httpx
    fi
    cat >"/etc/systemd/system/telegram-bridge-$bot.service" <<UNIT
[Unit]
Description=Telegram to $bot bridge
Wants=telegram-bridge-api.service
After=telegram-bridge-api.service

[Service]
User=telegram-bridge
WorkingDirectory=$state/$bot
Environment=LOCAL_API_HOST=127.0.0.1
Environment=BOT_ENTRY=$entry
Environment=BOT_CONFIG=$state/$bot/source.json
Environment=BOT_DIRECTORY=$app/$bot
Environment=PATH=$app/$bot/venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=PYTHONUNBUFFERED=1
ExecStart=$app/$bot/start-bot.sh
Restart=always
RestartSec=5s
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
UNIT
    services+=("telegram-bridge-$bot.service")
done

if (( dashboard )); then
    install -d -m 0750 -o telegram-bridge -g telegram-bridge "$state/dashboard"
    install -d -m 0755 "$app/dashboard"
    cp -a sources/dashbord-bale-rubika/. "$app/dashboard/"
    install -m 0755 config/dashboard-start.sh "$app/dashboard/start-dashboard.sh"
    cat >/etc/systemd/system/telegram-bridge-dashboard.service <<UNIT
[Unit]
Description=Telegram bridge dashboard
Wants=telegram-bridge-rubika.service telegram-bridge-bale.service
After=telegram-bridge-rubika.service telegram-bridge-bale.service

[Service]
User=telegram-bridge
WorkingDirectory=$app/dashboard
Environment=TELEGRAM_API_URL=http://127.0.0.1:8081
Environment=DASHBOARD_STATE_DIR=$state/dashboard
ExecStart=$app/dashboard/start-dashboard.sh
Restart=on-failure
RestartSec=5s
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
UNIT
    services+=(telegram-bridge-dashboard.service)
fi

systemctl daemon-reload
systemctl enable "${services[@]}"
systemctl restart "${services[@]}"
for component in dashboard rubika bale; do
    service=telegram-bridge-$component.service
    if [[ " ${services[*]} " != *" $service "* && -f /etc/systemd/system/$service ]]; then
        systemctl disable --now "$service"
    fi
done
systemctl --no-pager status "${services[@]}"
