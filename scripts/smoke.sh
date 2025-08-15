#!/usr/bin/env bash
set -Eeuo pipefail

: "${FRONTEND_URL:=http://localhost:3000/}"
: "${BACKEND_URL:=http://localhost:9000/fortunes}"
: "${TIMEOUT_SECS:=90}"

log(){ echo "[$(date +%H:%M:%S)] $*"; }

wait_for_200() {
  local url="$1" code="" deadline=$(( $(date +%s) + TIMEOUT_SECS ))
  log "Waiting for 200 from $url (timeout ${TIMEOUT_SECS}s)…"
  while [[ $(date +%s) -lt $deadline ]]; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)
    [[ "$code" == "200" ]] && { log "✅ 200 from $url"; return 0; }
    sleep 2
  done
  log "❌ Timeout waiting for $url (last code: ${code:-none})"
  return 1
}

must_contain() {
  local url="$1" needle="$2"
  log "Checking that $url contains '${needle}'"
  curl -fsS "$url" | grep -iq -- "$needle" && { log "✅ Found '${needle}'"; return 0; }
  log "❌ '${needle}' not found at $url"; return 1
}

main() {
  wait_for_200 "$FRONTEND_URL"
  must_contain "$FRONTEND_URL" "fortune" || must_contain "$FRONTEND_URL" "cookie"
  wait_for_200 "$BACKEND_URL"
}
main "$@"
