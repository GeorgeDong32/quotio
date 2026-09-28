#!/bin/bash
# qa-port.sh — mechanical companion for the ported-build supervised QA.
# Run this AFTER launching the ported Debug build and clicking "Always
# Allow" on the keychain prompt. Checks the Phase 9 checklist items that
# do not need eyeballing; prints PASS/FAIL per item.
set -uo pipefail

APP="${1:-$HOME/Coding/quotio/.portbuild/DerivedData/Build/Products/Debug/Quotio.app}"
BRIDGE_PORT="${BRIDGE_PORT:-8080}"
INTERNAL_PORT="${INTERNAL_PORT:-18080}"
CONFIG="$HOME/Library/Application Support/Quotio/config.yaml"
HISTORY="$HOME/Library/Application Support/Quotio/request-history.json"
VIRTUAL_MODEL="${VIRTUAL_MODEL:-haiku}"

pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; FAILED=1; }
FAILED=0

echo "== ported-build QA companion (bridge $BRIDGE_PORT / binary $INTERNAL_PORT) =="

# 1. Processes and ports.
[ -d "$APP" ] || fail "app bundle not found: $APP"
lsof -ti tcp:"$BRIDGE_PORT" >/dev/null 2>&1 && pass "bridge listening on $BRIDGE_PORT" || fail "bridge not listening on $BRIDGE_PORT"
lsof -ti tcp:"$INTERNAL_PORT" >/dev/null 2>&1 && pass "proxy binary listening on $INTERNAL_PORT" || fail "binary not listening on $INTERNAL_PORT"
pgrep -f "Helpers/quotio-cli" >/dev/null && pass "Rust helper running" || fail "Rust helper not running"

# 2. API key from config (never printed).
API_KEY="$(awk '/^api-keys:/{f=1;next} f&&/^- /{gsub(/[-" ]/,"",$0); print; exit} f&&NF&&!/^-/{exit}' "$CONFIG" 2>/dev/null)"
[ -n "$API_KEY" ] && pass "read api key from config" || fail "could not read api key from $CONFIG"

# 3. Management health through the bridge (transparent forwarding).
if [ -n "$API_KEY" ]; then
    MGMT_KEY="$(security find-generic-password -s 'dev.quotio.desktop.local-management' -a 'local-management-key' -w 2>/dev/null)"
    if [ -n "$MGMT_KEY" ]; then
        code="$(curl -s -o /dev/null -w '%{http_code}' -m 8 -H "Authorization: Bearer $MGMT_KEY" \
            "http://127.0.0.1:$BRIDGE_PORT/v0/management/debug" 2>/dev/null)"
        [ "$code" = "200" ] && pass "management /debug via bridge -> 200" || fail "management /debug via bridge -> ${code:-no-response}"
    else
        echo "[SKIP] management key not readable from this terminal (expected; the app itself holds it)"
    fi

    # 4. Model list through the bridge.
    code="$(curl -s -o /tmp/qa-models.json -w '%{http_code}' -m 8 \
        -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:$BRIDGE_PORT/v1/models" 2>/dev/null)"
    [ "$code" = "200" ] && pass "/v1/models via bridge -> 200" || fail "/v1/models via bridge -> ${code:-no-response}"
fi

# 5. One real request with a virtual model (fallback routing path).
if [ -n "$API_KEY" ]; then
    before="$(python3 -c "import json;print(len(json.load(open('$HISTORY')).get('entries',[])))" 2>/dev/null || echo 0)"
    code="$(curl -s -o /tmp/qa-chat.json -w '%{http_code}' -m 60 \
        -H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json' \
        -d "{\"model\":\"$VIRTUAL_MODEL\",\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" \
        "http://127.0.0.1:$BRIDGE_PORT/v1/chat/completions" 2>/dev/null)"
    if [ "$code" = "200" ]; then
        pass "chat completion via virtual model '$VIRTUAL_MODEL' -> 200"
    else
        fail "chat completion via '$VIRTUAL_MODEL' -> ${code:-no-response} ($(head -c 120 /tmp/qa-chat.json 2>/dev/null))"
    fi
    sleep 2
    after="$(python3 -c "import json;print(len(json.load(open('$HISTORY')).get('entries',[])))" 2>/dev/null || echo 0)"
    [ "$after" -gt "$before" ] && pass "request logged (history $before -> $after; check the Request Logs page for the fallback trace)" \
        || echo "[NOTE] history count unchanged ($before) — open the Request Logs page to eyeball the trace"
fi

# 6. Upgrade continuity.
[ "$(defaults read dev.quotio.desktop proxyPort 2>/dev/null)" = "$BRIDGE_PORT" ] \
    && pass "proxyPort stays $BRIDGE_PORT" || fail "proxyPort drifted: $(defaults read dev.quotio.desktop proxyPort 2>/dev/null)"
defaults read dev.quotio.desktop fallbackConfiguration >/dev/null 2>&1 \
    && pass "fallbackConfiguration intact" || fail "fallbackConfiguration missing"

echo "== result: $([ $FAILED -eq 0 ] && echo ALL CHECKS PASSED || echo SEE FAILURES ABOVE) =="
echo "Remaining eyeball items: Request Logs trace detail, Gemini Quota page, light/dark."
exit $FAILED
