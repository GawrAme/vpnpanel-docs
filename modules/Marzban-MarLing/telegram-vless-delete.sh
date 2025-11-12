#!/usr/bin/env bash
set -euo pipefail

# === Konfigurasi Telegram (opsional) ===
if [[ -f "/etc/gegevps/bin/telegram_config.conf" ]]; then
  # shellcheck disable=SC1091
  source "/etc/gegevps/bin/telegram_config.conf"
else
  TELEGRAM_BOT_TOKEN=""
  TELEGRAM_CHAT_ID=""
fi

# === Tools / Paths ===
LVMZ_BIN="${LVMZ_BIN:-/usr/local/sbin/lingvpn_mz}"

# Pastikan jq ada (dipakai untuk cek eksistensi user via --json)
command -v jq >/dev/null 2>&1 || { echo "Need: jq" >&2; exit 1; }

# Runner robust untuk lingvpn_mz
run_lvmz() {
  if [[ -x "$LVMZ_BIN" ]]; then
    "$LVMZ_BIN" "$@"
    return $?
  fi
  local pybin
  pybin="$(command -v python3 || command -v python || true)"
  [[ -n "$pybin" ]] || { echo "ERROR: python3 tidak ditemukan" >&2; return 127; }
  "$pybin" "$LVMZ_BIN" "$@"
}

# === Helpers ===
html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

tg_send() {
  local RAW_TEXT="$1"
  [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$(printf '%s' "$RAW_TEXT")" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
}

die() { echo "ERROR: $*" >&2; exit 1; }

# === Argumen (kompat dengan bot) ===
USERNAME="${1:-}"
PASSWORD="${2:-}"                # tidak digunakan, hanya untuk echo back
EXPIRED="${3:-}"                 # tidak digunakan
TRANSPORT="${4:-}"               # tidak digunakan
EXPIRED_TIMESTAMP_BOT="${5:-}"   # tidak digunakan

if [[ -z "$USERNAME" || -z "$PASSWORD" || -z "$EXPIRED" ]]; then
  echo "Usage: $0 <username> <password> <expired_days> [transport] [expired_timestamp_bot]"
  exit 1
fi

# Validasi username basic
if ! [[ "$USERNAME" =~ ^[A-Za-z0-9_]{3,32}$ ]]; then
  msg="Username tidak valid. Hanya huruf/angka/underscore (_), panjang 3–32."
  echo "$msg" >&2
  tg_send "$(printf '%s\n' \
    "Hapus akun <b>GAGAL</b>!" \
    "-=================================-" \
    "Username : $(printf '%s' "$USERNAME" | html_escape)" \
    "Detail   : $(printf '%s' "$msg" | html_escape)")"
  exit 1
fi

tunnel_name="VLess"
current_date="$(date '+%Y-%m-%d %H:%M:%S')"
DOMAIN="$(cat /root/domain 2>/dev/null || echo '-')"

# Pastikan binary ada
[[ -x "$LVMZ_BIN" || -f "$LVMZ_BIN" ]] || die "lingvpn_mz tidak ditemukan di $LVMZ_BIN"
chmod +x "$LVMZ_BIN" 2>/dev/null || true

# === Cek user ada atau tidak ===
if ! run_lvmz list --limit 5000 --json 2>/dev/null | jq -e --arg u "$USERNAME" '.[] | select(.username==$u)' >/dev/null; then
  msg="User tidak ditemukan: ${USERNAME}"
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

# === DELETE via lingvpn_mz ===
out_del="$(run_lvmz delete "$USERNAME" 2>&1)" || {
  # gagal
  tg_send "$(printf '%s\n' \
    "Hapus akun <b>GAGAL</b>!" \
    "-=================================-" \
    "Username : $(printf '%s' "$USERNAME" | html_escape)" \
    "Domain   : $(printf '%s' "$DOMAIN" | html_escape)" \
    "Protocol : $(printf '%s' "$tunnel_name" | html_escape)" \
    "Waktu    : $(printf '%s' "$current_date" | html_escape)" \
    "Detail   : $(printf '%s' "$out_del" | html_escape)")"
  die "lingvpn_mz delete gagal: $out_del"
}

# === Sukses ===
detail_msg="Akun berhasil dihapus."
tg_send "$(printf '%s\n' \
  "Hapus akun <b>BERHASIL</b>!" \
  "-=================================-" \
  "Username : $(printf '%s' "$USERNAME" | html_escape)" \
  "Domain   : $(printf '%s' "$DOMAIN" | html_escape)" \
  "Protocol : $(printf '%s' "$tunnel_name" | html_escape)" \
  "Waktu    : $(printf '%s' "$current_date" | html_escape)" \
  "Status   : $(printf '%s' "$detail_msg" | html_escape)")"

# === Output ke VM (kompat) ===
echo "HTML_CODE"
echo "<b>+++++ Trial ${tunnel_name} Deleted +++++</b>"
echo "Username: <code>${USERNAME}</code>"
echo "Password: <code>${PASSWORD}</code>"
echo "Domain: <code>${DOMAIN}</code>"
echo "================================="
echo "Waktu Penghapusan: ${current_date}"
echo "Status: ${detail_msg}"
echo "<b>+++++ End of Account Details +++++</b>"
