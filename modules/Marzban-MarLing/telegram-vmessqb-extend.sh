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
    local RAW_TEXT="${1:-}"
    [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] || return 0
    curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=$(printf '%s' "$RAW_TEXT")" \
        --data-urlencode "parse_mode=HTML" \
        --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
}

die() { echo "ERROR: $*" >&2; exit 1; }

# === Marzban API helper (buat ambil password & subs, optional) ===
get_marzban_api_port() {
    local env_file="/opt/marzban/.env"
    [[ -r "$env_file" ]] || { echo "7879"; return; }

    local port
    port="$(grep -E '^[[:space:]]*UVICORN_PORT[[:space:]]*=' "$env_file" \
             | tail -n1 \
             | sed -E 's/.*=[[:space:]]*["'\'']?([0-9]+).*/\1/')"

    if [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "$port"
    else
        echo "7879"
    fi
}
API_HOST="${API_HOST:-127.0.0.1}"
API_PORT="${API_PORT:-$(get_marzban_api_port)}"
API_BASE="http://${API_HOST}:${API_PORT}/api"
TOKEN_FILE="${TOKEN_FILE:-/root/token.json}"
ACCESS_TOKEN="$(jq -r '.access_token // empty' "$TOKEN_FILE" 2>/dev/null || true)"

api_get_user() {
    local uname="$1"
    [[ -n "$ACCESS_TOKEN" ]] || return 1
    curl -sS -f \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "$API_BASE/user/$uname"
}

# === Args ===
USERNAME="${1:-}"
PASSWORD_IGNORED="${2:-}"
DAYS="${3:-}"
QUOTA_IGNORED="${4:-}"
CYCLE_IGNORED="${5:-}"
TRANSPORT_IGNORED="${6:-}"
EXPIRED_TS_IGNORED="${7:-}"

if [[ -z "$USERNAME" || -z "$PASSWORD_IGNORED" || -z "$DAYS" ]]; then
    echo "Usage: $0 <USERNAME> <PASSWORD_IGNORED> <DAYS> <QUOTA_IGNORED> <CYCLE_IGNORED> <TRANSPORT_IGNORED> <EXPIRED_TS_IGNORED>" >&2
    exit 1
fi

# === Validasi username & DAYS ===
if ! [[ "$USERNAME" =~ ^[A-Za-z0-9_]{3,32}$ ]]; then
    echo "Username tidak valid. Hanya huruf/angka/underscore (_), panjang 3–32." >&2
    exit 1
fi
if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
    echo "DAYS harus angka." >&2
    exit 1
fi
if [[ "$DAYS" -eq 0 ]]; then
    echo "DAYS 0 tidak ada efek. Isi minimal 1." >&2
    exit 1
fi

# === Cek binary lingvpn_mz ===
[[ -x "$LVMZ_BIN" || -f "$LVMZ_BIN" ]] || die "lingvpn_mz tidak ditemukan di $LVMZ_BIN"
chmod +x "$LVMZ_BIN" 2>/dev/null || true
# === Domain & IP (opsional info) ===
DOMAIN="$(cat /root/domain 2>/dev/null || echo example.com)"
current_date="$(date '+%Y-%m-%d %H:%M:%S')"
tunnel_name="VMess"

# === Ambil info user via API (kalau bisa) ===
user_json=""
if [[ -n "$ACCESS_TOKEN" ]]; then
    if ! user_json="$(api_get_user "$USERNAME" 2>/dev/null)"; then
        echo "Username '$USERNAME' tidak ditemukan (API Marzban)." >&2
        exit 1
    fi
else
    # fallback: cek minimal ada via lingvpn_mz list
    if ! run_lvmz list --limit 2000 --json 2>/dev/null \
        | jq -e --arg u "$USERNAME" '.[] | select(.username==$u)' >/dev/null; then
        echo "Username '$USERNAME' tidak ditemukan." >&2
        exit 1
    fi
fi

# Ambil password & subs (kalau user_json tersedia)
vmess_pass="-"
SUBS="https://${DOMAIN}/sub"
if [[ -n "$user_json" ]]; then
    vmess_pass="$(echo "$user_json" | jq -r '.proxies.vmess.id // "-"')"
    sub_rel="$(echo "$user_json" | jq -r '.subscription_url // ""')"

    if [[ -n "$sub_rel" && "$sub_rel" == /* ]]; then
        SUBS="https://${DOMAIN}${sub_rel}"
    elif [[ -n "$sub_rel" ]]; then
        SUBS="$sub_rel"
    fi
fi

# === Extend hari via lingvpn_mz extend --days --json ===
extend_args=( extend "$USERNAME" --days "$DAYS" --json )

extend_json="$(run_lvmz "${extend_args[@]}" 2>&1)" || {
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        mapfile -t MSG <<EOF
Perpanjang akun <b>GAGAL</b>!
-=================================-
Username: $(printf '%s' "$USERNAME" | html_escape)
Domain: $(printf '%s' "$DOMAIN" | html_escape)
Protocol: $(printf '%s' "$tunnel_name" | html_escape)
Tambah Hari: $(printf '%s' "$DAYS" | html_escape)
Waktu: $(printf '%s' "$current_date" | html_escape)
Detail: $(printf '%s' "$extend_json" | html_escape)
EOF
        tg_send "$(printf '%s\n' "${MSG[@]}")"
    fi
    die "lingvpn_mz extend gagal: $extend_json"
}

# Pastikan JSON valid
if ! echo "$extend_json" | jq -e . >/dev/null 2>&1; then
    die "Output extend bukan JSON: $extend_json"
fi

# Ambil expire baru dari extend_json
new_expire_ts="$(echo "$extend_json" | jq -r '.new_expire // 0')"
new_expire_utc_str="$(echo "$extend_json" | jq -r '.new_expire_utc // ""')"

# Expire human (pakai new_expire_ts kalau ada, fallback ke new_expire_utc_str)
if [[ "$new_expire_ts" =~ ^[0-9]+$ && "$new_expire_ts" -gt 0 ]]; then
    expire_human="$(date -d "@${new_expire_ts}" '+%Y-%m-%d %H:%M:%S')"
elif [[ -n "$new_expire_utc_str" && "$new_expire_utc_str" != "null" ]]; then
    expire_human="$new_expire_utc_str"
else
    expire_human="Unknown"
fi

# === Notifikasi BERHASIL ===
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
    mapfile -t OK <<EOF
Perpanjang akun Quota Based <b>BERHASIL</b>!
-=================================-
<b>+++++ ${tunnel_name} Extend (Hari) +++++</b>
Username: $(printf '%s' "$USERNAME" | html_escape)
Domain: $(printf '%s' "$DOMAIN" | html_escape)
UUID: $(printf '%s' "$vmess_pass" | html_escape)
Tambah Hari: $(printf '%s' "$DAYS" | html_escape) Hari
Protocol: $(printf '%s' "$tunnel_name" | html_escape)
Waktu Update: $(printf '%s' "$current_date" | html_escape)
Subscription: $(printf '%s' "$SUBS" | html_escape)
Expired Baru: $(printf '%s' "$expire_human" | html_escape)
EOF
    tg_send "$(printf '%s\n' "${OK[@]}")"
fi

# === Output ke STDOUT (HTML-ish) ===
echo "HTML_CODE"
echo "<b>+++++ Quota Based ${tunnel_name} Extend (Hari) +++++</b>"
echo "Username: <code>${USERNAME}</code>"
echo "UUID: <code>${vmess_pass}</code>"
echo "Domain: <code>${DOMAIN}</code>"
echo "Tambah Hari: <code>${DAYS}</code> Hari"
echo "Cek Kuota: ${SUBS}"
echo "================================="
echo "Masa Aktif Baru : ${expire_human}"
echo "<b>+++++ End of Extend Details +++++</b>"
