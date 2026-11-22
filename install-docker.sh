#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
case "${1:-}" in
    1|rubika) profile=rubika ;;
    2|bale) profile=bale ;;
    3|both) profile=both ;;
    4|all) profile=all ;;
    *) echo "Usage: bash install-docker.sh {1|2|3|4}" >&2; exit 2 ;;
esac

clone() {
    local repo=$1
    if [[ ! -d sources/$repo ]]; then
        git clone "https://github.com/shiny222/$repo.git" "sources/$repo"
    fi
}

mkdir -p sources config
clone telegram-bot-api
if [[ $profile != bale ]]; then clone telegram-to-rubika; fi
if [[ $profile != rubika ]]; then clone telegram-to-bale; fi
if [[ $profile == all ]]; then clone dashbord-bale-rubika; fi
if [[ ! -f .env ]]; then cp -n .env.example .env; fi
if [[ $profile != bale && ! -f config/rubika.json ]]; then
    echo "Create config/rubika.json from the Rubika repo's documented settings." >&2
    exit 1
fi
if [[ $profile != rubika && ! -f config/bale.json ]]; then
    echo "Create config/bale.json from the Bale repo's documented settings." >&2
    exit 1
fi
docker compose --profile "$profile" up -d --build --remove-orphans --wait
