#!/usr/bin/env bash
# telegram-noobz-create.sh <user> <password> <expired_days> <bandwidth_GB> <limit_device> [reset_mode]
set -euo pipefail

PROTOCOL_DEFAULT="tcp_mux_ssl_direct"
NGINX_XRAY_FILE="/opt/marzban/xray.conf"
DOMAIN_FILE="/root/domain"
NOOBZ_CONF="/etc/noobzvpns/config.toml"
TG_CONF="/etc/gegevps/bin/telegram_config.conf"
LOG_DIR="/var/log/addnoobz"
tunnel_name="NOOBZ"
tunnel_type="NOOBZ"

if [[ -z "$USERNAME" || -z "$PASSWORD" || -z "$EXPIRED" ]]; then
    echo "Usage: $0 <username> <password> <expired_days>"
    exit 1
fi

USERNAME="${1}"
PASSWORD="${2}"
EXPIRED="${3}" # days
QUOTA="${4}"
CYCLE="${5}"
TRANSPORT="${6}"
EXPIRED_TIMESTAMP_BOT="${7}"

USER="$USERNAME"; PASS="$PASSWORD"; EXP_DAYS="$EXPIRED"; BW_GB="$QUOTA"; LIM_DEV="3"
RESET_MODE="${CYCLE:-monthly}"   # daily|monthly|yearly|none

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Need command: $1"; exit 1; }; }
need noobzvpns
command -v jq >/dev/null 2>&1 || { apt-get update -y >/dev/null 2>&1 || true; apt-get install -y jq >/dev/null 2>&1 || { echo "Install jq manually."; exit 1; }; }
command -v curl >/dev/null 2>&1 || { apt-get update -y >/dev/null 2>&1 || true; apt-get install -y curl >/dev/null 2>&1 || { echo "Install curl manually."; exit 1; }; }

mkdir -p "$LOG_DIR"

# Domain
if [[ -s "$DOMAIN_FILE" ]]; then
  DOMAIN="$(tr -d ' \t\r\n' < "$DOMAIN_FILE")"
else
  DOMAIN="$(hostname -f 2>/dev/null || hostname)"
fi

# Identifier
IDENTIFIER="$(grep -E '^\s*identifier\s*=' "$NOOBZ_CONF" 2>/dev/null | head -n1 | sed -E 's/.*=\s*"([^"]+)".*/\1/')"
[[ -n "${IDENTIFIER}" ]] || IDENTIFIER="$(grep -E 'identifier' "$NOOBZ_CONF" 2>/dev/null | head -n1 | sed -E 's/.*=\s*"([^"]+)".*/\1/')"
[[ -n "${IDENTIFIER}" ]] || IDENTIFIER="noobz"

# Payload path (optional best-effort)
PAYLOAD_PATH="/lingvpn-noobz"
if [[ -f "$NGINX_XRAY_FILE" ]]; then
  block="$(awk '$0 ~ /server\s*{/ {ins=1} ins{buf=buf $0 ORS} $0 ~ /}/ && ins{ins=0; print buf; buf=""}' "$NGINX_XRAY_FILE" \
          | awk '/listen[^;]*12000/ {hit=1} {if(hit) print}' | head -n 500)"
  loc="$(sed -nE 's/.*location\s+\/([^[:space:]\{]+).*/\1/p' <<<"$block" | head -n1)"
  [[ -n "$loc" ]] && PAYLOAD_PATH="/$loc"
fi

# Expired (human)
NOW_EPOCH="$(date +%s)"
EXP_EPOCH=$(( NOW_EPOCH + EXP_DAYS * 86400 ))
EXP_DATE="$(date -d "@$EXP_EPOCH" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date -r "$EXP_EPOCH" '+%Y-%m-%d %H:%M:%S %Z')"

# === Execute add (JSON output) ===
set +e
JSON_OUT="$(noobzvpns -j add "$USER" -p "$PASS" -e "$EXP_DAYS" -b "$BW_GB" -d "$LIM_DEV" 2>&1)"
RET=$?
set -e

ACTION="$(echo "$JSON_OUT" | jq -r '.[0] | keys[0]' 2>/dev/null || true)"
ERRVAL="$(echo "$JSON_OUT" | jq -r '.[0][keys[0]].error // empty' 2>/dev/null || true)"

# group kondisi biar jelas
if [[ $RET -ne 0 || ( -n "${ERRVAL:-}" && "$ERRVAL" != "null" ) ]]; then
  echo "noobzvpns add FAILED"
  echo "Action : ${ACTION:-unknown}"
  echo "Error  : ${ERRVAL:-<none>}"
  echo "Raw    : $JSON_OUT"
  exit 1
fi

# Optional verify (non-fatal)
noobzvpns print "$USER" >/dev/null 2>&1 || true

# === Jadwalkan auto-reset + simpan schedule JSON ===
SCHED_SUMMARY="(auto-reset disabled)"
SCHED_DIR="/etc/noobzvpns/schedules"
mkdir -p "$SCHED_DIR"

# Ambil issued time dari noobzvpns print USER (format string)
ISSUED_RAW="$(noobzvpns print "$USER" 2>/dev/null | sed -nE 's/^[[:space:]]*-issued[[:space:]]*:[[:space:]]*(.*)$/\1/p' | head -n1)"
# Konversi ke epoch (fallback 0)
ISSUED_TS="$(date -d "$ISSUED_RAW" +%s 2>/dev/null || echo 0)"

# fungsi bantu hitung next_run dari issued + strategy
calc_next() {
  local base="$1" mode="$2"
  case "$mode" in
    daily)   date -d "$base +1 day"    '+%s' 2>/dev/null ;;
    monthly) date -d "$base +1 month"  '+%s' 2>/dev/null ;;
    yearly)  date -d "$base +1 year"   '+%s' 2>/dev/null ;;
    *)       echo "" ;;
  esac
}

if [[ "$RESET_MODE" == "none" ]]; then
  # hapus schedule user jika ada
  rm -f "$SCHED_DIR/${USER}.json" 2>/dev/null || true
  SCHED_SUMMARY="Auto-Reset : none (disabled)"
else
  # tambahkan/aktifkan systemd timer (opsional)
  if command -v nvpn_schedule_reset >/dev/null 2>&1; then
    nvpn_schedule_reset add "$USER" "$RESET_MODE" >/dev/null 2>&1 || true
  fi

  # hitung next_run (estimasi pertama = issued + interval)
  if [[ -n "$ISSUED_RAW" ]]; then
    NEXT_TS="$(calc_next "$ISSUED_RAW" "$RESET_MODE")"
  else
    NEXT_TS=""
  fi
  if [[ -n "${NEXT_TS:-}" ]]; then
    NEXT_HUMAN="$(date -d "@$NEXT_TS" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$NEXT_TS")"
  else
    NEXT_HUMAN=""
  fi

  # tulis file schedule
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

# Subs page (pakai token scope=passwd)
if command -v nvpn_make_link >/dev/null 2>&1; then
  SUBS="$(nvpn_make_link "$USER" "$EXP_DAYS" 1)"
else
  SUBS="(nvpn_make_link not found)"
fi

# Build summary text
PROTO="$PROTOCOL_DEFAULT"; SNI="$DOMAIN"
SERVER_SSL="${DOMAIN}:443"; SERVER_PLAIN="${DOMAIN}:80"; CLIENT_USER="${USER}@${IDENTIFIER}"

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

echo -e "HTML_CODE"
echo -e "<b>+++++ ${tunnel_name} WS over Xray Account Created +++++</b>"
echo -e "Username: <code>${CLIENT_USER}</code>"
echo -e "Password: <code>${PASSWORD}</code>"
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

# === 2) SIMPAN KE FILE LOG ===
LOG_FILE="${LOG_DIR}/${USER}.txt"
printf "%s\n" "$SUMMARY" > "$LOG_FILE"

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
