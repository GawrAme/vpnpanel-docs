#!/usr/bin/env bash
# Perpanjang akun SS2022 untuk integrasi bot Telegram (HTML_CODE output)
# Usage: telegram-ssocks-extend.sh <USERNAME> <ADD_DAYS> [NEW_QUOTA_GB]
#
# ENV override (opsional):
#   INBOUND_TAGS="SSWS,SSWS-ANTIADS,SSWS-ANTIPORN"
#   PRIMARY_TAG="SSWS"
#   XRAY_BIN="/usr/local/bin/xray"
#   XRAY_CFG="/usr/local/etc/xray/config.json"
#   XRAY_DB="/usr/local/etc/xray/database.json"
#   XRAY_API="127.0.0.1:10085"
#   CLIENT_DIR="/var/www/html"
#   SS_METHOD="2022-blake3-aes-128-gcm"
#   SS_PORT="443"
#   HTTP_PORT="80"

set -euo pipefail

USERNAME="${1:-}"; ADD_DAYS="${2:-}"; NEW_QUOTA_GB="${3:-}"
[ -n "$USERNAME" ] && [[ "$ADD_DAYS" =~ ^[0-9]+$ ]] || {
  echo "Usage: $0 <USERNAME> <ADD_DAYS> [NEW_QUOTA_GB]" >&2
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

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Need: $1"; exit 1; }; }
need jq
need ss2022ctl
[ -x "$XRAY_BIN" ] || { echo "Xray binary not found: $XRAY_BIN"; exit 1; }
[ -f "$XRAY_CFG" ] || { echo "Xray config not found: $XRAY_CFG"; exit 1; }
[ -f "$XRAY_DB" ]  || { echo "DB not found: $XRAY_DB"; exit 1; }

# ===== Helper umum =====
get_domain(){
  if [ -f /root/domain ]; then awk 'NF{print; exit}' /root/domain
  else echo "example.com"; fi
}

# reset interval (hari) dari DB -> detik -> hari
get_reset_days(){
  jq -r --arg e "$USERNAME" '.users[$e].reset_every_seconds // 0' "$XRAY_DB" \
  | awk '{ d = ($1<=0)?0:int(($1+86399)/86400); print d }'
}

# WebSocket path per tag (fallback /ss-ws)
get_wspath_for_tag(){ # $1=tag
  jq -r --arg tag "$1" '
    .inbounds[]|select(.tag==$tag)
    | .streamSettings.wsSettings.path // "/ss-ws"
  ' "$XRAY_CFG"
}

# gabung path jadi "a atau b atau c"
collect_all_paths_atau(){
  local IFS=',' tag
  for tag in $INBOUND_TAGS; do
    tag="$(echo "$tag" | xargs)"
    get_wspath_for_tag "$tag"
  done \
  | awk 'NF{print}' \
  | awk '!seen[$0]++' \
  | awk '{a[++n]=$0} END{ if(n==0){print ""} else if(n==1){print a[1]} else { for(i=1;i<=n;i++){ if(i==1) s=a[i]; else s=s " atau " a[i] } print s } }'
}

# Subscription URL via ss2022ctl
get_sub_url(){
  ss2022ctl link "$1" 2>/dev/null || true
}

# Format WIB
wib_from_epoch(){ TZ=Asia/Jakarta date -d "@$1" +"%Y-%m-%d %H:%M:%S WIB"; }
wib_now(){ TZ=Asia/Jakarta date +"%Y-%m-%d %H:%M:%S WIB"; }

# Temukan file config TXT terbaru untuk USERNAME
find_latest_cfg(){
  ls -1t "${CLIENT_DIR}"/*-"$USERNAME".txt 2>/dev/null | head -n1 || true
}

# ===== Validasi user ada =====
if ! jq -e --arg e "$USERNAME" '.users[$e]' "$XRAY_DB" >/dev/null; then
  echo "User tidak ada di DB: $USERNAME" >&2
  exit 2
fi

# ===== Perpanjang lewat ss2022ctl =====
if [ -n "$NEW_QUOTA_GB" ]; then
  ss2022ctl renew "$USERNAME" "$ADD_DAYS" "$NEW_QUOTA_GB" >/dev/null
else
  ss2022ctl renew "$USERNAME" "$ADD_DAYS" >/dev/null
fi

# ===== Ambil data terkini dari DB =====
DOMAIN="$(get_domain)"
EXPIRE_AT="$(jq -r --arg e "$USERNAME" '.users[$e].expire_at // 0' "$XRAY_DB")"
EXPIRE_WIB="$(wib_from_epoch "$EXPIRE_AT")"
ENABLED="$(jq -r --arg e "$USERNAME" '.users[$e].enabled // false' "$XRAY_DB")"

QUOTA_BYTES="$(jq -r --arg e "$USERNAME" '.users[$e].quota_bytes // 0' "$XRAY_DB")"
QUOTA_GB_NOW="$(awk -v b="$QUOTA_BYTES" 'BEGIN{printf "%.2f", b/1024/1024/1024}')"

RESET_DAYS_NOW="$(get_reset_days)"
PATHS_TXT="$(collect_all_paths_atau)"
SUB_URL="$(get_sub_url "$USERNAME")"

TLS_PORT="${SS_PORT}"
NTLS_PORT="${HTTP_PORT}"

CFG_PATH="$(find_latest_cfg)"
if [ -n "$CFG_PATH" ]; then
  BASENAME="$(basename "$CFG_PATH")"
  DL_URL="https://${DOMAIN}/${BASENAME}"
else
  DL_URL="(config belum ditemukan di ${CLIENT_DIR})"
fi

# ===== Output ke bot (HTML_CODE) =====
echo "HTML_CODE"
echo "Perpanjangan akun BERHASIL"
echo "———————————————"
echo "ShadowSocks-WS Account Extended"
echo "Username: ${USERNAME}"
echo "Domain: <code>${DOMAIN}</code>"
if [ -n "$NEW_QUOTA_GB" ]; then
  printf "Quota baru: %.2f GB\n" "$NEW_QUOTA_GB"
fi
printf "Quota saat ini: %.2f GB (reset tiap %s hari)\n" "$QUOTA_GB_NOW" "$RESET_DAYS_NOW"
echo "Tambah durasi: ${ADD_DAYS} hari"
echo "Expired baru: ${EXPIRE_WIB}"
echo "Status: $( [ "$ENABLED" = "true" ] && echo Aktif || echo Nonaktif )"
echo "TLS/nTLS: ${TLS_PORT}/${NTLS_PORT}"
echo "Path WS: ${PATHS_TXT}"
echo "Protocol: SS 2022 (${SS_METHOD}) over WS"
echo "Diperbarui: $(wib_now)"
echo "Subscription: ${SUB_URL}"
echo "Download config: ${DL_URL}"
