# Telegram bridge deployment

| Scenario | Components |
| --- | --- |
| 1 | Rubika and local Telegram Bot API |
| 2 | Bale and local Telegram Bot API |
| 3 | Rubika, Bale and local Telegram Bot API |
| 4 | Rubika, Bale, dashboard and local Telegram Bot API |

## Prepare configuration

1. Copy `.env.example` to `.env`. Set `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` to your Telegram application credentials without quotes.
2. Create `config/rubika.json` and/or `config/bale.json` using the selected bot repositories' documented settings. Use different Telegram bot tokens when both bots poll concurrently. Stop any duplicate polling instance. If a token previously ran against Telegram's hosted Bot API, call the hosted API's `logOut` for that token before switching.
3. The installers clone selected repositories into `sources/` and reuse existing checkouts. You can place copies there first. The verified legacy entry points are `bridge.py` for Rubika and `bridge2.py` for Bale. The local API build expects a Linux amd64 executable at `sources/telegram-bot-api/telegram-bot-api`.

Keep `.env` and the bot JSON files private. The launchers set `LOCAL_API.enabled`, `host`, `port` and `start_server` in a runtime copy of each bot config.

## Docker

Use Docker with the Compose plugin, BuildKit, Linux containers and Git. Run the command for your operating system from this directory, substituting your scenario number.

```sh
bash install-docker.sh 3
```

```bat
install-docker.bat 3
```

Compose builds the images and brings up the selected services. Both bots reach `http://telegram-api:8081` over the project network. Port 8081 stays within Docker. Both bots mount the API media directory at the same absolute path the API returns. The API data volume survives container replacement.

```sh
docker compose --profile '*' ps
docker compose --profile '*' logs -f
```

Before changing scenarios, run `docker compose --profile '*' down` to stop the previous selection. Leave out `--volumes` to preserve Telegram API data.

## Linux systemd

Run on a Debian or Ubuntu host with systemd and a compatible Linux API binary. The installer uses apt for runtime dependencies, creates the `telegram-bridge` service account and enables the selected units at boot.

```sh
sudo bash install-systemd.sh 3
```

If you have a compatible binary already, pass it with `sudo TELEGRAM_API_BINARY=/path/to/telegram-bot-api bash install-systemd.sh 3`. The API listens on `127.0.0.1:8081`. Services are named `telegram-bridge-api.service`, `telegram-bridge-rubika.service`, `telegram-bridge-bale.service` and `telegram-bridge-dashboard.service`.

```sh
sudo journalctl -u telegram-bridge-api -u telegram-bridge-rubika -u telegram-bridge-bale -f
```

## Scenario 4 integration

The dashboard repository was inaccessible while this kit was built. Its launch command, port and button implementation need to be verified against the current dashboard source.

- Docker builds the dashboard's own Dockerfile. Set `DASHBOARD_CONTAINER_PORT` to its HTTP port, configure the application to bind to `0.0.0.0` inside its container, and open `http://127.0.0.1:8000` on the Docker host by default. Its server can resolve the Compose service names `rubika`, `bale` and `telegram-api`. Configure any HTTP control URLs in the dashboard's backend using the actual bot control ports. If the buttons invoke `systemctl` or launch local processes, they need a dashboard code change or a control adapter for Docker.
- For systemd, provide `config/dashboard-start.sh` with a shebang and the dashboard's foreground launch command. Install its runtime dependencies as documented by the dashboard repository. The unit uses the copied dashboard directory as its working directory and passes `TELEGRAM_API_URL` and `DASHBOARD_STATE_DIR` to the launcher. Map any service controls to the unit names above using the dashboard's supported mechanism.
