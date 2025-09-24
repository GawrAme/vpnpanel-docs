#!/usr/bin/env bash
set -euo pipefail

# === Konfigurasi Telegram ===
if [[ -f "/etc/gegevps/bin/telegram_config.conf" ]]; then
  # shellcheck disable=SC1091
  source "/etc/gegevps/bin/telegram_config.conf"
else
  TELEGRAM_BOT_TOKEN=""
  TELEGRAM_CHAT_ID=""
fi

# Escape HTML sederhana untuk parse_mode=HTML
html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Kirim pesan ke Telegram (auto urlencode teks)
tg_send() {
  local RAW_TEXT="$1"
  [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$(printf '%s' "$RAW_TEXT")" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
}

# === Argumen ===
USERNAME="${1:-}"
PASSWORD="${2:-}"
EXPIRED="${3:-}"              # tidak terpakai untuk delete, tetap diterima biar kompatibel
TRANSPORT="${4:-}"            # tidak terpakai
EXPIRED_TIMESTAMP_BOT="${5:-}"# tidak terpakai

if [[ -z "$USERNAME" || -z "$PASSWORD" || -z "$EXPIRED" ]]; then
  echo "Usage: $0 <username> <password> <expired_days> [transport] [expired_timestamp_bot]"
  exit 1
fi

tunnel_name="VLESS"
tunnel_type="VLESS"
limit_gb="2"
limit_bytes=$((limit_gb * 1024 * 1024 * 1024))

current_date="$(date '+%Y-%m-%d %H:%M:%S')"
DOMAIN="$(cat /root/domain 2>/dev/null || echo '-')"

api_host="127.0.0.1"
api_port="YOUR_API_PORT"
api_username="YOUR_API_USERNAME"
api_password="YOUR_API_PASSWORD"

# === Ambil token ===
api_token="$(
  curl -sSkL -X 'POST' \
    "http://${api_host}:${api_port}/api/admin/token" \
    -H 'accept: application/json' \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d "grant_type=password&username=${api_username}&password=${api_password}&scope=&client_id=&client_secret=" \
  | jq -r '.access_token // empty'
)"

if [[ -z "$api_token" ]]; then
  msg="Gagal mendapatkan API token (cek kredensial atau API)."
  echo "$msg"
  tg_send "$(printf '%s\n' \
    "Hapus akun <b>GAGAL</b>!" \
    "-=================================-" \
    "Username : $(printf '%s' "$USERNAME" | html_escape)" \
    "Domain   : $(printf '%s' "$DOMAIN" | html_escape)" \
    "Protocol : $(printf '%s' "$tunnel_name" | html_escape)" \
    "Waktu    : $(printf '%s' "$current_date" | html_escape)" \
    "Detail   : $(printf '%s' "$msg" | html_escape)")"
  exit 1
fi

# === DELETE user ===
response_file="$(mktemp /tmp/"${USERNAME}"_trojan.XXXXXX.json)"
trap 'rm -f "$response_file" 2>/dev/null || true' EXIT

http_response="$(
  curl -sSkL -w "%{http_code}" -o "${response_file}" -X 'DELETE' \
    "http://${api_host}:${api_port}/api/user/${USERNAME}" \
    -H "Authorization: Bearer ${api_token}"
)"

# Baca body respons
res_json="$(cat "${response_file}" || echo '')"

# Cek keberhasilan (200/204 dianggap sukses)
if [[ "$http_response" != "200" && "$http_response" != "204" ]]; then
  error_detail="$(jq -r '.detail // .message // .error // empty' <<<"$res_json" 2>/dev/null || true)"
  [[ -z "$error_detail" ]] && error_detail="Unknown error / HTTP ${http_response}"

  echo "API Response Error (${http_response}): ${error_detail}"

  # Telegram: notifikasi gagal
  tg_send "$(printf '%s\n' \
    "Hapus akun <b>GAGAL</b>!" \
    "-=================================-" \
    "Username : $(printf '%s' "$USERNAME" | html_escape)" \
    "Domain   : $(printf '%s' "$DOMAIN" | html_escape)" \
    "Protocol : $(printf '%s' "$tunnel_name" | html_escape)" \
    "Durasi   : $(printf '%s' "$EXPIRED" | html_escape)" \
    "Waktu    : $(printf '%s' "$current_date" | html_escape)" \
    "HTTP Code: $(printf '%s' "$http_response" | html_escape)" \
    "Detail   : $(printf '%s' "$error_detail" | html_escape)")"
  exit 1
fi

# Sukses
detail_msg="$(jq -r '.detail // .message // "Akun berhasil dihapus."' <<<"$res_json" 2>/dev/null || echo "Akun berhasil dihapus.")"

# Telegram: notifikasi berhasil
tg_send "$(printf '%s\n' \
  "Hapus akun Trial <b>BERHASIL</b>!" \
  "-=================================-" \
  "Username : $(printf '%s' "$USERNAME" | html_escape)" \
  "Domain   : $(printf '%s' "$DOMAIN" | html_escape)" \
  "Protocol : $(printf '%s' "$tunnel_name" | html_escape)" \
  "Waktu    : $(printf '%s' "$current_date" | html_escape)" \
  "Status   : $(printf '%s' "$detail_msg" | html_escape)")"

# === Output ke VM (jangan dihilangkan) ===
echo "HTML_CODE"
echo "<b>+++++ Trial ${tunnel_name} Deleted +++++</b>"
echo "Username: <code>${USERNAME}</code>"
echo "Password: <code>${PASSWORD}</code>"
echo "Domain: <code>${DOMAIN}</code>"
echo "Data Limit (sebelum hapus): <code>${limit_gb}</code> GB"
echo "================================="
echo "Waktu Penghapusan: ${current_date}"
echo "Status: ${detail_msg}"
echo "<b>+++++ End of Account Details +++++</b>"
