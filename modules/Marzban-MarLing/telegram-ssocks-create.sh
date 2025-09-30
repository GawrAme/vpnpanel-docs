#!/usr/bin/env bash
# Buat akun SS2022 lewat ss2022ctl untuk integrasi bot Telegram
#
# Opsi via ENV (punya default aman):
#   QUOTA_GB=1024          # kuota (GB)
#   RESET_DAYS=<EXPIRED>   # hari reset kuota (default sama dgn EXPIRED)
#   MAX_DEV=0              # 0 = unlimited
#   INBOUND_TAGS="SSWS,SSWS-ANTIADS,SSWS-ANTIPORN"
#   XRAY_BIN="/usr/local/bin/xray"
#   XRAY_CFG="/usr/local/etc/xray/config.json"
#   XRAY_DB="/usr/local/etc/xray/database.json"
#   XRAY_API="127.0.0.1:10085"
#   CLIENT_DIR="/var/www/html"   # lokasi file template client
#   PRIMARY_TAG="SSWS"           # inbound utama (mengambil server-key)

set -euo pipefail

USERNAME="${1:-}"; PASSWORD="${2:-}"; EXPIRED_DAYS="${3:-}"
[ -n "$USERNAME" ] && [ -n "$PASSWORD" ] && [ -n "$EXPIRED_DAYS" ] || {
  echo "Usage: $0 <USERNAME> <PASSWORD> <EXPIRED_DAYS>" >&2
  exit 1
}

# ---- Konfigurasi ----
QUOTA_GB="${QUOTA_GB:-1024}"
RESET_DAYS="30"
MAX_DEV="${MAX_DEV:-3}"

INBOUND_TAGS="${INBOUND_TAGS:-SSWS,SSWS-ANTIADS,SSWS-ANTIPORN}"
PRIMARY_TAG="${PRIMARY_TAG:-SSWS}"

XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_CFG="${XRAY_CFG:-/usr/local/etc/xray/config.json}"
XRAY_DB="${XRAY_DB:-/usr/local/etc/xray/database.json}"
XRAY_API="${XRAY_API:-127.0.0.1:10085}"
CLIENT_DIR="${CLIENT_DIR:-/var/www/html}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Need: $1"; exit 1; }; }
need jq
need openssl
[ -x "$XRAY_BIN" ] || { echo "Xray binary not found: $XRAY_BIN"; exit 1; }
[ -f "$XRAY_CFG" ] || { echo "Xray config not found: $XRAY_CFG"; exit 1; }
[ -f "$XRAY_DB" ]  || { echo "DB not found: $XRAY_DB"; exit 1; }

# ---- Helper ambil domain (sesuai ss2022ctl kamu) ----
get_domain(){
  if [ -f /root/domain ]; then awk 'NF{print; exit}' /root/domain
  else echo "example.com"; fi
}

# Ambil server key (PSK) dari PRIMARY_TAG
get_server_key(){
  jq -r --arg tag "$PRIMARY_TAG" '.inbounds[] | select(.tag==$tag) | .settings.password // empty' "$XRAY_CFG"
}

# Buat payload adu utk satu inbound
make_adu_payload_for_tag(){ # tag email pw_b64
  local tag="$1" email="$2" pw="$3"
  jq --arg tag "$tag" --arg email "$email" --arg pw "$pw" '
    { "inbounds": [ ( .inbounds[] | select(.tag==$tag)
      | .settings.clients = [ { "email": $email, "password": $pw } ] ) ] }' "$XRAY_CFG"
}

# Tambah/replace user ke semua inbound (password = $2)
api_adu_multi(){ # email pw_b64
  local email="$1" pw="$2" IFS=',' tag tmp
  for tag in $INBOUND_TAGS; do
    tag="$(echo "$tag" | xargs)"
    tmp="$(mktemp)"
    make_adu_payload_for_tag "$tag" "$email" "$pw" > "$tmp"
    "$XRAY_BIN" api adu --server="$XRAY_API" "$tmp" >/dev/null 2>&1 || true
    rm -f "$tmp"
  done
}

# Update field password_b64 di DB (persist)
db_set_password(){
  local email="$1" pw="$2"
  jq --arg e "$email" --arg p "$pw" '.users[$e].password_b64 = $p' "$XRAY_DB" > "${XRAY_DB}.tmp" && mv "${XRAY_DB}.tmp" "$XRAY_DB"
}

# Ambil subscription URL via ss2022ctl link kalau tersedia
get_sub_url(){
  if command -v ss2022ctl >/dev/null 2>&1; then
    ss2022ctl link "$1" 2>/dev/null || true
  fi
}

# Tanggal WIB helper
wib_now(){ TZ=Asia/Jakarta date +"%Y-%m-%d %H:%M:%S WIB"; }
wib_from_epoch(){ TZ=Asia/Jakarta date -d "@$1" +"%Y-%m-%d %H:%M:%S WIB"; }

# ---- 1) Generate user password (16 random bytes → base64) ----
USER_PW_B64="$(openssl rand -base64 16 | tr -d '\n')"

# ---- 2) Buat akun via ss2022ctl (biar DB, quota, expire tercatat rapi) ----
ss2022ctl add "$USERNAME" "$QUOTA_GB" "$EXPIRED_DAYS" "$RESET_DAYS" "$MAX_DEV" >/dev/null

# ---- 3) Replace password runtime & DB ke password buatan kita ----
api_adu_multi "$USERNAME" "$USER_PW_B64"
db_set_password "$USERNAME" "$USER_PW_B64"

# ---- 4) Generate file template client (v2rayNG + Clash) ----
if command -v ss2022ctl >/dev/null 2>&1; then
  ss2022ctl clientcfg "$USERNAME" >/dev/null 2>&1 || true
fi
# lokasi file mengikuti cmd_clientcfg kamu (server-psk diambil dari cfg)
SERVER_PSK="$(get_server_key)"
OUT_TXT="${CLIENT_DIR}/${USER_PW_B64}-${USERNAME}.txt"

# Pastikan file ada (kalau cmd_clientcfg belum dibuat, tulis minimal Clash entry)
if [ ! -f "$OUT_TXT" ]; then
  DOMAIN="$(get_domain)"
  PORT="${SS_PORT:-443}"
  CIPHER="${SS_METHOD:-2022-blake3-aes-128-gcm}"
  # Ambil path dari PRIMARY_TAG (fallback /ss-ws)
  WSPATH="$(jq -r --arg tag "$PRIMARY_TAG" '.inbounds[]|select(.tag==$tag)|.streamSettings.wsSettings.path // "/ss-ws"' "$XRAY_CFG")"

  mkdir -p "$CLIENT_DIR"
  cat > "$OUT_TXT" <<YAML
# Minimal Clash entry
- name: ${USERNAME}-${PRIMARY_TAG}
  type: ss
  server: ${DOMAIN}
  port: ${PORT}
  cipher: ${CIPHER}
  password: ${SERVER_PSK}:${USER_PW_B64}
  udp-over-tcp: true
  plugin: v2ray-plugin
  plugin-opts:
    mode: websocket
    host: ${DOMAIN}
    tls: true
    skip-cert-verify: true
    path: "${WSPATH}"
    mux: false
YAML
fi

# --- helper: ambil wsPath per-tag & gabungkan untuk tampilan ---
get_wspath_for_tag(){ # $1=tag
  jq -r --arg tag "$1" '
    .inbounds[]|select(.tag==$tag)
    | .streamSettings.wsSettings.path // "/ss-ws"
  ' "$XRAY_CFG"
}

collect_all_paths(){ # out dalam satu baris "a, b, c"
  local IFS=',' tag paths=() p
  for tag in $INBOUND_TAGS; do
    tag="$(echo "$tag" | xargs)"
    p="$(get_wspath_for_tag "$tag")"
    [ -n "$p" ] && paths+=("$p")
  done
  # unik + urut ringan
  printf "%s\n" "${paths[@]}" | awk '!seen[$0]++' | paste -sd', ' -
}
# ---- 5) Cetak hasil (untuk dikirim balik ke Telegram bot) ----
DOMAIN="$(get_domain)"
NOW_EPOCH="$(date +%s)"
EXPIRE_AT="$(jq -r --arg e "$USERNAME" '.users[$e].expire_at // 0' "$XRAY_DB")"
EXPIRE_WIB="$(wib_from_epoch "$EXPIRE_AT")"
SUB_URL="$(get_sub_url "$USERNAME")"

TLS_PORT="${SS_PORT:-443}"
NTLS_PORT="${HTTP_PORT:-80}"   
ALL_PATHS="$(collect_all_paths)"

DL_URL=""
BASENAME="$(basename "$OUT_TXT")"
if [ -f "$OUT_TXT" ]; then
  # asumsi /var/www/html disajikan di https://DOMAIN/
  DL_URL="https://${DOMAIN}/${BASENAME}"
fi

echo -e "HTML_CODE"
echo -e "Pembuatan akun BERHASIL"
echo -e "———————————————"
echo -e "ShadowSocks-WS Account Created"
echo -e "Username: ${USERNAME}"
echo -e "Domain: <code>${DOMAIN}</code>"
echo -e "Password : <code>${SERVER_PSK}:${USER_PW_B64}</code>"
echo -e "Durasi: ${EXPIRED_DAYS} hari"
echo -e "Limit Device: ${MAX_DEV}"
echo -e "TLS/nTLS: ${TLS_PORT}/${NTLS_PORT}"
echo -e "Path WS: ${ALL_PATHS}"
echo -e "Protocol: SS 2022 (${SS_METHOD:-2022-blake3-aes-128-gcm}) over WS"
echo -e "Dibuat: $(wib_now)"
echo -e "Expired: ${EXPIRE_WIB}"
printf "Quota: %.2f GB (reset tiap %s hari)\n" "$QUOTA_GB" "$RESET_DAYS"
echo -e "Subscription: ${SUB_URL}"
if [ -n "$DL_URL" ]; then
  echo "Download config: ${DL_URL}"
else
  echo "Download config: ${OUT_TXT}"
fi
