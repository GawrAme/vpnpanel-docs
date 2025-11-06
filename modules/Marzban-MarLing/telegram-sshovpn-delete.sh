#!/usr/bin/env bash
set -euo pipefail

# === Telegram config ===
source "/etc/gegevps/bin/telegram_config.conf"

# Escape HTML sederhana
html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# Kirim pesan Telegram (aman untuk newline & karakter khusus)
tg_send() {
  local RAW_TEXT="${1:-}"
  [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$(printf '%s' "$RAW_TEXT")" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
}

# === Argumen (kompatibel panel) ===
USERNAME="${1:-}"
PASSWORD="${2:-}"
EXPIRED="${3:-}"
TRANSPORT="${4:-}"
EXPIRED_TIMESTAMP_BOT="${5:-}"

if [[ -z "$USERNAME" || -z "$PASSWORD" || -z "$EXPIRED" ]]; then
  echo "Usage: $0 <username> <password> <expired_days> [transport] [expired_timestamp_bot]" >&2
  exit 1
fi

LVCTL="${LVCTL:-/usr/local/sbin/lvctl}"
DOMAIN="$(test -f /root/domain && sed -n '1p' /root/domain || echo '-')"
NOW_H="$(date '+%Y-%m-%d %H:%M:%S')"

if [[ ! -x "$LVCTL" ]]; then
  msg="lvctl tidak ditemukan di $LVCTL"
  echo "$msg" >&2
  tg_send "$(printf '%s\n' \
    "Hapus akun SSH-WS <b>GAGAL</b>!" \
    "-=================================-" \
    "Username: $(printf '%s' "$USERNAME" | html_escape)" \
    "Domain: $(printf '%s' "$DOMAIN"   | html_escape)" \
    "Waktu: $(printf '%s' "$NOW_H"    | html_escape)" \
    "Detail: $(printf '%s' "$msg"      | html_escape)")"
  exit 1
fi

# Eksekusi hapus
DEL_OUT="$("$LVCTL" delete "$USERNAME" 2>&1)" || {
  tg_send "$(printf '%s\n' \
    "Hapus akun SSH-WS <b>GAGAL</b>!" \
    "-=================================-" \
    "Username: $(printf '%s' "$USERNAME" | html_escape)" \
    "Domain: $(printf '%s' "$DOMAIN"   | html_escape)" \
    "Waktu: $(printf '%s' "$NOW_H"    | html_escape)" \
    "Detail: $(printf '%s' "$DEL_OUT"  | html_escape)")"
  echo "$DEL_OUT" >&2
  exit 1
}

# Telegram: BERHASIL (ringkas)
tg_send "$(printf '%s\n' \
  "Hapus akun SSH-WS <b>BERHASIL</b>!" \
  "-=================================-" \
  "Username: $(printf '%s' "$USERNAME" | html_escape)" \
  "Domain: $(printf '%s' "$DOMAIN"   | html_escape)" \
  "Waktu: $(printf '%s' "$NOW_H"    | html_escape)")"

# Output ke panel (minimal)
echo -e "HTML_CODE"
echo -e "<b>+++++ SSH-WS Account Deleted +++++</b>"
echo -e "Username: <code>${USERNAME}</code>"
echo -e "Domain: <code>${DOMAIN}</code>"
echo -e "================================="
echo -e "Waktu Penghapusan: ${NOW_H}"
echo -e "<b>+++++ End of Details +++++</b>"
