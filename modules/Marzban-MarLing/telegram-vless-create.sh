#!/usr/bin/env bash
set -euo pipefail

# === Config Telegram (optional) ===
source "/etc/gegevps/bin/telegram_config.conf" 2>/dev/null || true

# === Tools / Paths ===
LVMZ_BIN="${LVMZ_BIN:-/usr/local/sbin/lingvpn_mz}"

# Pastikan jq ada (dipakai untuk parsing JSON)
command -v jq >/dev/null 2>&1 || { echo "Need: jq" >&2; exit 1; }

# Runner robust untuk lingvpn_mz
run_lvmz() {
  # Jika executable langsung, panggil langsung
  if [[ -x "$LVMZ_BIN" ]]; then
    "$LVMZ_BIN" "$@"
    return $?
  fi
  # Jika bukan executable, coba lewat python3/python
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
  local RAW_TEXT="${1:-}"
  [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] || return 0
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$(printf '%s' "$RAW_TEXT")" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
}

die() { echo "ERROR: $*" >&2; exit 1; }

# === Args ===
USERNAME="${1:-}"
PASSWORD_IGNORED="${2:-}"
EXPIRED="${3:-}"

[[ -n "$USERNAME" && -n "${EXPIRED}" ]] || {
  echo "Usage: $0 <username> <ignored_password> <expired_days>" >&2
  exit 1
}

# === Validasi username (tanpa karakter spesial) ===
if ! [[ "$USERNAME" =~ ^[A-Za-z0-9_]{3,32}$ ]]; then
  echo "Username tidak valid. Hanya huruf/angka/underscore (_), panjang 3–32." >&2
  exit 1
fi

# === Cek binary ===
[[ -x "$LVMZ_BIN" || -f "$LVMZ_BIN" ]] || die "lingvpn_mz tidak ditemukan di $LVMZ_BIN"
# upayakan executable kalau memungkinkan
chmod +x "$LVMZ_BIN" 2>/dev/null || true

# === Cek duplikat username via lingvpn_mz list --json ===
if run_lvmz list --limit 2000 --json 2>/dev/null \
   | jq -e --arg u "$USERNAME" '.[] | select(.username==$u)' >/dev/null; then
  echo "Username '$USERNAME' sudah ada. Pilih nama lain." >&2
  exit 1
fi

# === Konfigurasi default ===
tunnel_name="VLess"
limit_gb="${limit_gb:-1024}"
RESET_STRAT="${RESET_STRAT:-month}"
MAX_DEV="${MAX_DEV:-3}"

# === Domain & IP (opsional info) ===
DOMAIN="$(cat /root/domain 2>/dev/null || echo example.com)"
IP_FILE="/tmp/myip.txt"
if [[ -s "$IP_FILE" ]]; then
  IP_ADDR="$(cat "$IP_FILE" 2>/dev/null || true)"
else
  IP_ADDR="$(curl -s4 ifconfig.me || true)"
  [[ -n "$IP_ADDR" ]] && echo "$IP_ADDR" > "$IP_FILE" || true
fi

current_date="$(date '+%Y-%m-%d %H:%M:%S')"

# === Susun argumen lingvpn_mz add ===
args=( add "$USERNAME" --proto vless --reset "$RESET_STRAT" )

# --- PILIH PLUGIN SESUAI KEBIJAKAN TCP ---
# < 90 hari TIDAK dapat akses Trojan TCP
if [[ "$EXPIRED" =~ ^[0-9]+$ && "$EXPIRED" -ge 90 ]]; then
  # >= 90 hari → izinkan TCP via 'all'
  args+=( --plugin all )
else
  # < 90 hari → eksklusikan TCP → sebutkan ws/grpc/hu saja
  args+=( --plugin ws grpc hu )
fi

# Days / Always-on
if [[ "$EXPIRED" =~ ^[1-9][0-9]*$ ]]; then
  args+=( --days "$EXPIRED" )
else
  args+=( --always-on )
fi

# Quota
if [[ "$limit_gb" =~ ^[1-9][0-9]*$ ]]; then
  args+=( --quota-gb "$limit_gb" )
else
  args+=( --unlimited )
fi

#maxdev
args+=( --max-dev "${MAX_DEV}" )

#note
args+=( --note "CREATED AT ${current_date}" )

# Output JSON (untuk ambil password/links)
args+=( --json )

# === Eksekusi tambah user via lingvpn_mz ===
resp_json="$(run_lvmz "${args[@]}" 2>&1)" || {
  # kirim notifikasi gagal
  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
    mapfile -t MSG <<EOF
Pembuatan akun <b>GAGAL</b>!
-=================================-
Username : $(printf '%s' "$USERNAME" | html_escape)
Domain   : $(printf '%s' "$DOMAIN" | html_escape)
Protocol : $(printf '%s' "$tunnel_name" | html_escape)
Durasi   : $(printf '%s' "$EXPIRED" | html_escape)
Waktu    : $(printf '%s' "$current_date" | html_escape)
Detail   : $(printf '%s' "$resp_json" | html_escape)
EOF
    tg_send "$(printf '%s\n' "${MSG[@]}")"
  fi
  die "lingvpn_mz add gagal: $resp_json"
}

# Pastikan JSON valid
if ! echo "$resp_json" | jq -e . >/dev/null 2>&1; then
  die "Output bukan JSON: $resp_json"
fi

# === Ambil field dari JSON ===
expire_ts="$(echo "$resp_json" | jq -r '.expire // 0')"
vless_uuid="$(echo "$resp_json" | jq -r '.proxies.vless.id // "-"')"
sub_rel="$(echo "$resp_json" | jq -r '.subscription_url // ""')"
created_at="$(echo "$resp_json" | jq -r '.created_at // .createdAt // ""')"

# Format subscription URL
if [[ -n "$sub_rel" && "$sub_rel" == /* ]]; then
  SUBS="https://${DOMAIN}${sub_rel}"
else
  SUBS="${sub_rel:-https://${DOMAIN}/sub}"
fi

# Expire to human
if [[ "$expire_ts" =~ ^[0-9]+$ && "$expire_ts" -gt 0 ]]; then
  expire_human="$(date -d "@${expire_ts}" '+%Y-%m-%d %H:%M:%S')"
else
  expire_human="AlwaysON"
fi

# === Notifikasi BERHASIL ===
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
  mapfile -t OK <<EOF
Pembuatan akun <b>BERHASIL</b>!
-=================================-
<b>+++++ $(printf '%s' "$tunnel_name" | html_escape) Account Created +++++</b>
Username   : $(printf '%s' "$USERNAME" | html_escape)
Domain     : $(printf '%s' "$DOMAIN" | html_escape)
UUID       : $(printf '%s' "$vless_uuid" | html_escape)
Durasi     : $(printf '%s' "$EXPIRED" | html_escape) Hari
Protocol   : $(printf '%s' "$tunnel_name" | html_escape)
Akun dibuat pada : $(printf '%s' "$current_date" | html_escape)
Subscription: $(printf '%s' "$SUBS" | html_escape)
Expired     : $(printf '%s' "$expire_human" | html_escape)
EOF
  tg_send "$(printf '%s\n' "${OK[@]}")"
fi

# === (Opsional) Tambahkan ke konfigurasi lokal jika perlu ===
if command -v addconfig-vless.sh >/dev/null 2>&1; then
  # PASSWORD_IGNORED diganti password asli dari lingvpn_mz
  addconfig-vless.sh "${USERNAME}" "${vless_uuid}" "${EXPIRED}" || true
fi

# === Output ke STDOUT (HTML-ish) ===
echo "HTML_CODE"
echo "<b>+++++ ${tunnel_name} Account Created +++++</b>"
echo "Username: <code>${USERNAME}</code>"
echo "UUID: <code>${vless_uuid}</code>"
echo "Domain: <code>${DOMAIN}</code>"
if [[ "$EXPIRED" =~ ^[0-9]+$ && "$EXPIRED" -ge 90 && -n "${IP_ADDR:-}" ]]; then
  echo "IP Address: <code>${IP_ADDR}</code>"
fi
echo "Data Limit: <code>${limit_gb}</code> GB"
echo "Max Device: ${MAX_DEV} Device [1STB atau 2HP]"
echo "Cek Kuota : ${SUBS}"
echo "================================="
echo "Masa Aktif: ${expire_human}"
echo "<b>+++++ End of Account Details +++++</b>"
