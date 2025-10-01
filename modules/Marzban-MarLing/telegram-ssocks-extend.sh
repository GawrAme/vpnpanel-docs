#!/usr/bin/env bash
# Perpanjang akun SS2022 untuk integrasi bot Telegram (HTML_CODE output)
set -euo pipefail

USERNAME="${1:-}"; PASSWORD="${2:-}"; EXPIRED_DAYS="${3:-}"
[ -n "${USERNAME}" ] && [ -n "${PASSWORD}" ] && [ -n "${EXPIRED_DAYS}" ] || {
  echo "Usage: $0 <USERNAME> <PASSWORD> <EXPIRED_DAYS>" >&2
  exit 1
}

# ===== Konfigurasi =====
INBOUND_TAGS="${INBOUND_TAGS:-SSWS,SSWS-ANTIADS,SSWS-ANTIPORN}"
PRIMARY_TAG="${PRIMARY_TAG:-SSWS}"

XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_CFG="${XRAY_CFG:-/usr/local/etc/xray/config.json}"
XRAY_DB="${XRAY_DB:-/usr/local/etc/xray/database.json}"
XRAY_API="${XRAY_API:-127.0.0.1:10085}"

CLIENT_DIR="${CLIENT_DIR:-/var/www/html}"

SS_METHOD="${SS_METHOD:-2022-blake3-aes-128-gcm}"
SS_PORT="${SS_PORT:-443}"
HTTP_PORT="${HTTP_PORT:-80}"
ADD_DAYS="${EXPIRED_DAYS}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Need: $1"; exit 1; }; }
need jq
need ss2022ctl
[ -x "${XRAY_BIN}" ] || { echo "Xray binary not found: ${XRAY_BIN}"; exit 1; }
[ -f "${XRAY_CFG}" ] || { echo "Xray config not found: ${XRAY_CFG}"; exit 1; }
[ -f "${XRAY_DB}" ]  || { echo "DB not found: ${XRAY_DB}"; exit 1; }

# ===== Helper umum =====
get_domain(){
  if [ -f /root/domain ]; then awk 'NF{print; exit}' /root/domain
  else echo "example.com"; fi
}

# reset interval (hari) dari DB -> detik -> hari (dibulatkan ke atas)
get_reset_days(){
  jq -r --arg e "${USERNAME}" '.users[$e].reset_every_seconds // 0' "${XRAY_DB}" \
  | awk '{ d = ($1<=0)?0:int(($1+86399)/86400); print d }'
}

# Subscription URL via ss2022ctl
get_sub_url(){
  ss2022ctl link "$1" 2>/dev/null || true
}

# Format WIB
wib_from_epoch(){ TZ=Asia/Jakarta date -d "@$1" +"%Y-%m-%d %H:%M:%S WIB"; }
wib_now(){ TZ=Asia/Jakarta date +"%Y-%m-%d %H:%M:%S WIB"; }

# Temukan file config TXT (Clash) terbaru untuk USERNAME
find_latest_cfg_clash(){
  find "${CLIENT_DIR}" -maxdepth 1 -type f -name "*-${USERNAME}.txt" -printf "%T@ %p\n" 2>/dev/null \
    | sort -nr | awk 'NR==1{print $2}'
}

# Temukan file config JSON (v2rayNG) terbaru untuk USERNAME + TAG spesifik
json_link_for_tag(){ # $1=TAG
  local tag="$1"
  # Pola penamaan: <uuid>-<username>-<TAG>.json
  local f
  f="$(find "${CLIENT_DIR}" -maxdepth 1 -type f -name "*-${USERNAME}-${tag}.json" -printf "%T@ %p\n" 2>/dev/null \
        | sort -nr | awk 'NR==1{print $2}')"
  if [ -n "${f:-}" ]; then
    echo "https://$(get_domain)/$(basename "$f")"
  else
    echo "(config ${tag} belum ditemukan di ${CLIENT_DIR})"
  fi
}

# ===== Validasi user ada =====
if ! jq -e --arg e "${USERNAME}" '.users[$e]' "${XRAY_DB}" >/dev/null; then
  echo "User tidak ada di DB: ${USERNAME}" >&2
  exit 2
fi

# ===== Perpanjang lewat ss2022ctl =====
ss2022ctl renew "${USERNAME}" "${ADD_DAYS}" >/dev/null

# ===== Ambil data terkini dari DB =====
DOMAIN="$(get_domain)"
EXPIRE_AT="$(jq -r --arg e "${USERNAME}" '.users[$e].expire_at // 0' "${XRAY_DB}")"
EXPIRE_WIB="$(wib_from_epoch "${EXPIRE_AT}")"
ENABLED="$(jq -r --arg e "${USERNAME}" '.users[$e].enabled // false' "${XRAY_DB}")"

QUOTA_BYTES="$(jq -r --arg e "${USERNAME}" '.users[$e].quota_bytes // 0' "${XRAY_DB}")"
QUOTA_GB_NOW="$(awk -v b="${QUOTA_BYTES}" 'BEGIN{printf "%.2f", b/1024/1024/1024}')"

RESET_DAYS_NOW="$(get_reset_days)"
SUB_URL="$(get_sub_url "${USERNAME}")"

TLS_PORT="${SS_PORT}"
NTLS_PORT="${HTTP_PORT}"

# Link Clash (TXT) terbaru — file gabungan semua tag
CFG_PATH1="$(find_latest_cfg_clash || true)"
if [ -n "${CFG_PATH1:-}" ]; then
  BASENAME_TXT="$(basename "${CFG_PATH1}")"
  DL_URL_CLASH="https://${DOMAIN}/${BASENAME_TXT}"
else
  DL_URL_CLASH="(config belum ditemukan di ${CLIENT_DIR})"
fi

# ===== Output HTML_CODE =====
echo -e "HTML_CODE"
echo -e "-=================================-"
echo -e "<b>+++++ShadowSocks-WS Account Extended+++++</b>"
echo -e "1. Username: ${USERNAME}"
echo -e "2. Domain: <code>${DOMAIN}</code>"
printf "3. Quota saat ini: %.2f GB (reset tiap %s hari)\n" "${QUOTA_GB_NOW}" "${RESET_DAYS_NOW}"
echo -e "4. Tambah durasi: ${ADD_DAYS} hari"
echo -e "5. Expired baru: ${EXPIRE_WIB}"
echo -e "6. Status: $( [ "${ENABLED}" = "true" ] && echo Aktif || echo Nonaktif )"
echo -e "7. Diperbarui: $(wib_now)"
echo -e "8. Subscription: ${SUB_URL}"
echo -e "Download config CLASH: ${DL_URL_CLASH}"

# Semua JSON per-tag (v2rayNG)
echo -e "Download config V2RAYNG (JSON):"
IFS=','; for _tag in ${INBOUND_TAGS}; do
  _tag="$(echo "${_tag}" | xargs)"          # trim
  echo -e "- ${_tag}: $(json_link_for_tag "${_tag}")"
done; unset IFS

echo -e "<b>+++++ End of Account Details +++++</b>"
echo -e "-=================================-"
