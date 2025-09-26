#!/usr/bin/env bash
# telegram-noobz-create.sh
# Usage (panel bot):
#   telegram-noobz-create.sh <user> <password> <expired_days> <bandwidth_GB> <cycle> [limit_device] [transport] [expired_ts]
#   - cycle: daily|monthly|yearly|none
#   - limit_device (opsional, default 3)
#   - transport (opsional, hanya label tampilan; default "WS over Xray")
#   - expired_ts (opsional, hanya info panel; tidak dipakai logika)
#
# Output:
#   - Cetak ringkasan ke stdout
#   - Cetak blok HTML dimulai dengan "HTML_CODE" untuk Telegram panel
#   - Kirim Telegram (jika TG_CONF terpasang)
#
set -euo pipefail

PROTOCOL_DEFAULT="tcp_mux_ssl_direct"
NGINX_XRAY_FILE="/opt/marzban/xray.conf"
DOMAIN_FILE="/root/domain"
NOOBZ_CONF="/etc/noobzvpns/config.toml"
TG_CONF="/etc/gegevps/bin/telegram_config.conf"
LOG_DIR="/var/log/addnoobz"
tunnel_name="NOOBZ"
tunnel_type="NOOBZ"

# ===== Helper =====
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Need command: $1"; exit 1; }; }

# ===== Args =====
if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <user> <password> <expired_days> <bandwidth_GB> <cycle> [transport] [expired_ts]" >&2
  exit 1
fi

USER="$1"
PASS="$2"
EXP_DAYS="$3"
BW_GB="$4"
RESET_MODE="$5"                 # daily|monthly|yearly|none
TRANSPORT="${6:-all}"           # hanya label tampilan
EXPIRED_TS_BOT="${7:-}"         # opsional, hanya info

LIM_DEV="3"
# ===== Check deps =====
need noobzvpns
command -v jq >/dev/null 2>&1 || { apt-get update -y >/dev/null 2>&1 || true; apt-get install -y jq >/dev/null 2>&1 || { echo "Install jq manually."; exit 1; }; }
command -v curl >/dev/null 2>&1 || { apt-get update -y >/dev/null 2>&1 || true; apt-get install -y curl >/dev/null 2>&1 || { echo "Install curl manually."; exit 1; }; }

mkdir -p "$LOG_DIR"

# ===== Domain =====
if [[ -s "$DOMAIN_FILE" ]]; then
  DOMAIN="$(tr -d ' \t\r\n' < "$DOMAIN_FILE")"
else
  DOMAIN="$(hostname -f 2>/dev/null || hostname)"
fi

# ===== Identifier (suffix username untuk login) =====
IDENTIFIER="$(grep -E '^\s*identifier\s*=' "$NOOBZ_CONF" 2>/dev/null | head -n1 | sed -E 's/.*=\s*"([^"]+)".*/\1/')"
[[ -n "${IDENTIFIER}" ]] || IDENTIFIER="$(grep -E 'identifier' "$NOOBZ_CONF" 2>/dev/null | head -n1 | sed -E 's/.*=\s*"([^"]+)".*/\1/')"
[[ -n "${IDENTIFIER}" ]] || IDENTIFIER="noobz"

# ===== Payload path (ambil dari xray.conf port 12000 jika ada) =====
PAYLOAD_PATH="/lingvpn-noobz"
if [[ -f "$NGINX_XRAY_FILE" ]]; then
  block="$(awk '$0 ~ /server\s*{/ {ins=1} ins{buf=buf $0 ORS} $0 ~ /}/ && ins{ins=0; print buf; buf=""}' "$NGINX_XRAY_FILE" \
          | awk '/listen[^;]*12000/ {hit=1} {if(hit) print}' | head -n 500)"
  loc="$(sed -nE 's/.*location\s+\/([^[:space:]\{]+).*/\1/p' <<<"$block" | head -n1)"
  [[ -n "$loc" ]] && PAYLOAD_PATH="/$loc"
fi

# ===== Hitung Expired human =====
NOW_EPOCH="$(date +%s)"
EXP_EPOCH=$(( NOW_EPOCH + EXP_DAYS * 86400 ))
EXP_DATE="$(date -d "@$EXP_EPOCH" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date -r "$EXP_EPOCH" '+%Y-%m-%d %H:%M:%S %Z')"

# ===== Add user (JSON) =====
set +e
JSON_OUT="$(noobzvpns -j add "$USER" -p "$PASS" -e "$EXP_DAYS" -b "$BW_GB" -d "$LIM_DEV" 2>&1)"
RET=$?
set -e

ACTION="$(echo "$JSON_OUT" | jq -r '.[0] | keys[0]' 2>/dev/null || true)"
ERRVAL="$(echo "$JSON_OUT" | jq -r '.[0][keys[0]].error // empty' 2>/dev/null || true)"

if [[ $RET -ne 0 || ( -n "${ERRVAL:-}" && "$ERRVAL" != "null" ) ]]; then
  echo "noobzvpns add FAILED"
  echo "Action : ${ACTION:-unknown}"
  echo "Error  : ${ERRVAL:-<none>}"
  echo "Raw    : $JSON_OUT"
  exit 1
fi

# Optional verify
noobzvpns print "$USER" >/dev/null 2>&1 || true

# ===== Auto-reset schedule (systemd) + tulis metadata JSON =====
SCHED_SUMMARY="(auto-reset disabled)"
SCHED_DIR="/etc/noobzvpns/schedules"
mkdir -p "$SCHED_DIR"

# Ambil issued dari print
ISSUED_RAW="$(noobzvpns print "$USER" 2>/dev/null | sed -nE 's/^[[:space:]]*-issued[[:space:]]*:[[:space:]]*(.*)$/\1/p' | head -n1)"
ISSUED_TS="$(date -d "$ISSUED_RAW" +%s 2>/dev/null || echo 0)"

calc_next() {
  local base="$1" mode="$2"
  case "$mode" in
    daily)   date -d "$base +1 day"    '+%s' 2>/dev/null ;;
    monthly) date -d "$base +1 month"  '+%s' 2>/dev/null ;;
    yearly)  date -d "$base +1 year"   '+%s' 2>/dev/null ;;
    *) echo "" ;;
  esac
}

if [[ "${RESET_MODE}" == "none" ]]; then
  rm -f "$SCHED_DIR/${USER}.json" 2>/dev/null || true
  SCHED_SUMMARY="Auto-Reset : none (disabled)"
else
  # aktifkan timer jika tersedia
  if command -v nvpn_schedule_reset >/dev/null 2>&1; then
    nvpn_schedule_reset add "$USER" "$RESET_MODE" >/dev/null 2>&1 || true
  fi
  # first guess untuk next_run
  if [[ -n "${ISSUED_RAW:-}" ]]; then
    NEXT_TS="$(calc_next "$ISSUED_RAW" "$RESET_MODE" || true)"
  else
    NEXT_TS=""
  fi
  if [[ -n "${NEXT_TS:-}" ]]; then
    NEXT_HUMAN="$(date -d "@$NEXT_TS" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$NEXT_TS")"
  else
    NEXT_HUMAN=""
  fi
  # simpan metadata schedule
  cat > "$SCHED_DIR/${USER}.json" <<JSON
{
  "username": "$(printf '%s' "$USER")",
  "strategy": "$(printf '%s' "$RESET_MODE")",
  "issued": "$(printf '%s' "$ISSUED_RAW")",
  "issued_ts": ${ISSUED_TS:-0},
  "next_run": "$(printf '%s' "${NEXT_HUMAN:-}")",
  "next_run_ts": ${NEXT_TS:-0}
}
JSON
  chmod 0644 "$SCHED_DIR/${USER}.json"
  SCHED_SUMMARY="Auto-Reset : ${RESET_MODE}$( [[ -n "${NEXT_HUMAN:-}" ]] && printf ' (next: %s)' "$NEXT_HUMAN" )"
fi

# ===== Subs page (token scope=passwd) =====
if command -v nvpn_make_link >/dev/null 2>&1; then
  SUBS="$(nvpn_make_link "$USER" "$EXP_DAYS" 1)"
else
  SUBS="(nvpn_make_link not found)"
fi

# ===== Build outputs =====
PROTO="$PROTOCOL_DEFAULT"
SNI="$DOMAIN"
SERVER_SSL="${DOMAIN}:443"
SERVER_PLAIN="${DOMAIN}:80"
CLIENT_USER="${USER}@${IDENTIFIER}"

SUMMARY=$(cat <<EOF
==================== NOOBZVPN USER ====================
Domain        : ${DOMAIN}
Protocol      : ${PROTO}
IP Family     : IPv4
SSL SNI       : ${SNI}
Server (SSL)  : ${SERVER_SSL}
Server (PLAIN): ${SERVER_PLAIN}
Username      : ${CLIENT_USER}
Password      : ${PASS}
Limit Device  : ${LIM_DEV}
Bandwidth     : ${BW_GB} GB
Expired in    : ${EXP_DAYS} hari
Expired Date  : ${EXP_DATE}
${SCHED_SUMMARY}
Payload (WS)  : GET ${PAYLOAD_PATH} HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Upgrade: Websocket[crlf]Connection: Keep-Alive[crlf]User-Agent: [ua][crlf][crlf]
Subs Page     : ${SUBS}
======================================================
EOF
)

# 1) Simpan log
LOG_FILE="${LOG_DIR}/${USER}.txt"
printf "%s\n" "$SUMMARY" > "$LOG_FILE"

# 2) Output HTML untuk Telegram panel (diparse pihak bot kamu)
echo -e "HTML_CODE"
echo -e "<b>+++++ ${tunnel_type} Account Created +++++</b>"
echo -e "Username: <code>${CLIENT_USER}</code>"
echo -e "Password: <code>${PASS}</code>"
echo -e "Protocol: ${PROTO}"
echo -e "Server (SSL): ${SERVER_SSL}"
echo -e "Server (PLAIN): ${SERVER_PLAIN}"
echo -e "Limit Device: ${LIM_DEV}"
echo -e "Bandwidth: ${BW_GB} GB"
echo -e "Expired in: ${EXP_DAYS} hari"
echo -e "Expired Date: ${EXP_DATE}"
echo -e "${SCHED_SUMMARY}"
echo -e "Payload (WS): <code>GET ${PAYLOAD_PATH} HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Upgrade: Websocket[crlf]Connection: Keep-Alive[crlf]User-Agent: [ua][crlf][crlf]</code>"
echo -e "Subs Page: ${SUBS}"
echo -e "<b>+++++ End of Account Details +++++</b>"

# === 3) KIRIM TELEGRAM (opsional, non-fatal) ===
if [[ -f "$TG_CONF" ]]; then
  # shellcheck disable=SC1090
  . "$TG_CONF" || true
  TG_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
  TG_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
  if [[ -n "$TG_TOKEN" && -n "$TG_CHAT_ID" ]]; then
    MSG_TITLE="NoobzVPN - User Added"
    MSG_BODY="$SUMMARY"
    MSG="<b>${MSG_TITLE}</b>%0A<pre>${MSG_BODY}</pre>"
    curl -sS -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=${TG_CHAT_ID}" \
      --data-urlencode "parse_mode=HTML" \
      --data-urlencode "disable_web_page_preview=true" \
      --data-urlencode "text=${MSG}" >/dev/null || echo "Warning: gagal kirim Telegram (di-skip)."
  else
    echo "Note: TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID belum di-set, skip Telegram."
  fi
else
  echo "Note: $TG_CONF tidak ditemukan, skip Telegram."
fi
