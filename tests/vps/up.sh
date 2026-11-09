#!/bin/bash
# Starts the stand and leaves the test keys and CA certificate outside the plugin folder.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
STATE="${SURE_BAR_VPS_STATE:-$HOME/.cache/sure-bar-vps}"
mkdir -p "$STATE"
docker compose up -d --quiet-pull
for _ in $(seq 1 60); do
  [ "$(docker compose exec -T web curl -s -o /dev/null -w '%{http_code}' localhost:3000/up 2>/dev/null)" = 200 ] && break
  sleep 3
done
if [ ! -s "$STATE/keys" ] || ! docker compose exec -T web bin/rails runner 'exit(User.exists?(email: "vps@example.test") ? 0 : 1)' 2>/dev/null; then
  docker compose exec -T web bin/rails runner - < seed.rb 2>/dev/null | grep '^KEY ' > "$STATE/keys"
fi
curl -fsS -o /dev/null -X POST 127.0.0.1:18474/reset
curl -s -o /dev/null -X POST 127.0.0.1:18474/proxies -d '{"name":"vps","listen":"0.0.0.0:18443","upstream":"caddy:443","enabled":true}'
for _ in $(seq 1 30); do
  docker compose exec -T caddy cat /data/caddy/pki/authorities/local/root.crt > "$STATE/ca.crt" 2>/dev/null && [ -s "$STATE/ca.crt" ] && break
  curl -sk -o /dev/null --resolve 127.0.0.1.nip.io:18443:127.0.0.1 https://127.0.0.1.nip.io:18443/up || true
  sleep 1
done
mkdir -p "$STATE/certs"
cp "$STATE/ca.crt" "$STATE/certs"/ca-certificates.crt
cp "$STATE/ca.crt" "$STATE/certs"/caddy.pem
openssl rehash "$STATE/certs" >/dev/null 2>&1 || true
echo "ready: https://127.0.0.1.nip.io:18443"
