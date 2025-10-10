#!/usr/bin/env bash
# Buat akun SS2022 lewat ss2022ctl untuk integrasi bot Telegram
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
# ===== Cek user sudah ada di DB? Kalau ada → batal =====
# Set ALLOW_OVERWRITE=1 untuk mengizinkan overwrite (default: 0 = batal)
ALLOW_OVERWRITE="${ALLOW_OVERWRITE:-0}"

if jq -e --arg e "$USERNAME" '.users[$e]' "$XRAY_DB" >/dev/null 2>&1; then
  if [ "$ALLOW_OVERWRITE" != "1" ]; then
    echo -e "HTML_CODE"
    echo -e "<b>Pembuatan akun DIBATALKAN</b>"
    echo -e "———————————————"
    echo -e "Username: <code>${USERNAME}</code>"
    echo -e "Alasan: sudah ada di database (duplikat)"
    echo -e "Tip: set <code>ALLOW_OVERWRITE=1</code> jika ingin menimpa user lama."
    exit 3
  else
    echo "Peringatan: user ${USERNAME} sudah ada. ALLOW_OVERWRITE=1 → lanjut menimpa." >&2
  fi
fi

# ---- Helper ambil domain  ----
get_domain(){
  if [ -f /root/domain ]; then awk 'NF{print; exit}' /root/domain
  else echo "example.com"; fi
}

# Ambil kunci (user key) yang sedang aktif di runtime untuk 1 tag
get_runtime_key_for_tag() { # <tag> <email>
  local tag="$1" email="$2"
  "$XRAY_BIN" api inbounduser --server="$XRAY_API" -tag="$tag" \
    | jq -r --arg e "$email" '
        .users[]? | select(.email==$e)
        | .account.key // empty
      ' 2>/dev/null
}

# Ambil kunci runtime dari daftar tag; prioritas PRIMARY_TAG lalu yang lain
get_runtime_key_any() { # <email>
  local email="$1" key=""
  # coba PRIMARY_TAG
  key="$(get_runtime_key_for_tag "$PRIMARY_TAG" "$email")"
  [ -n "$key" ] && { echo "$key"; return; }
  # coba tag lain
  local IFS=',' t
  for t in $INBOUND_TAGS; do
    t="$(echo "$t" | xargs)"
    [ "$t" = "$PRIMARY_TAG" ] && continue
    key="$(get_runtime_key_for_tag "$t" "$email")"
    [ -n "$key" ] && { echo "$key"; return; }
  done
  echo ""
}

# Sinkronisasi: pastikan password runtime == target; kalau tidak, adopt runtime
sync_runtime_password() { # <email> <target_pw_b64>
  local email="$1" want="$2" have=""
  # cek yang aktif sekarang
  have="$(get_runtime_key_any "$email")"

  # kalau belum ada user di runtime (kosong), coba adu ulang lalu re-check
  if [ -z "$have" ]; then
    api_adu_multi "$email" "$want"
    sleep 0.2
    have="$(get_runtime_key_any "$email")"
  fi

  # jika beda, coba sekali push ulang
  if [ -n "$have" ] && [ "$have" != "$want" ]; then
    api_adu_multi "$email" "$want"
    sleep 0.2
    have2="$(get_runtime_key_any "$email")"
    if [ -n "$have2" ] && [ "$have2" != "$want" ]; then
      # adopsi runtime agar output tidak bohong
      db_set_password "$email" "$have2"
      echo "$have2"
      return
    fi
  fi

  # kalau sama (atau berhasil dipaksa sama), kembalikan target
  echo "$want"
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

# write_v2rayng_json <username> <domain> <server_psk> <user_pw_b64> <tag> <outfile>
write_v2rayng_json(){
  local USERNAME="$1" DOMAIN="$2" SERVER_PSK="$3" USER_PW="$4" TAG="$5" OUT="$6"
  local CIPHER="${SS_METHOD:-2022-blake3-aes-128-gcm}"
  local PORT="${SS_PORT:-443}"
  local WSPATH; WSPATH="$(get_wspath_for_tag "$TAG")"
  mkdir -p "$(dirname "$OUT")"

  cat > "$OUT" <<JSON
{
  "log": { "loglevel": "warning" },
  "dns": {
    "servers": ["1.1.1.1", "8.8.8.8"]
  },
  "inbounds": [
    {
      "tag": "socks",
      "listen": "127.0.0.1",
      "port": 10808,
      "protocol": "socks",
      "settings": { "auth": "noauth", "udp": true, "userLevel": 8 },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls"] }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "shadowsocks",
      "settings": {
        "servers": [
          {
            "address": "${DOMAIN}",
            "port": ${PORT},
            "method": "${CIPHER}",
            "password": "${SERVER_PSK}:${USER_PW}",
            "level": 8,
            "uot": true,
            "ota": false
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${DOMAIN}",
          "allowInsecure": true,
          "alpn": ["http/1.1"],
          "fingerprint": "chrome"
        },
        "wsSettings": {
          "path": "${WSPATH}",
          "headers": { "Host": "${DOMAIN}" }
        }
      },
      "mux": { "enabled": false, "concurrency": -1 }
    },
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block",  "protocol": "blackhole", "settings": { "response": { "type": "http" } } }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "inboundTag": ["socks"], "outboundTag": "proxy" },
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "direct" },
      { "type": "field", "domain": ["geosite:private"], "outboundTag": "direct" }
    ]
  },
  "remarks": "${USERNAME}-${TAG}"
}
JSON
}

# Tanggal WIB helper
wib_now(){ TZ=Asia/Jakarta date +"%Y-%m-%d %H:%M:%S WIB"; }
wib_from_epoch(){ TZ=Asia/Jakarta date -d "@$1" +"%Y-%m-%d %H:%M:%S WIB"; }

# ---- 1) Generate user password (16 random bytes → base64) ----
USER_PW_B64="$(openssl rand -base64 16 | tr -d '\n')"

# ---- 2) Buat akun via ss2022ctl ----
ss2022ctl add "$USERNAME" "$QUOTA_GB" "$EXPIRED_DAYS" "$RESET_DAYS" "$MAX_DEV" >/dev/null

# ---- 3) Replace password runtime & DB ke password buatan kita ----
api_adu_multi "$USERNAME" "$USER_PW_B64"
db_set_password "$USERNAME" "$USER_PW_B64"

# >>> Tambahkan baris ini: pastikan password yang dipakai output = yang benar-benar aktif
USER_PW_B64="$(sync_runtime_password "$USERNAME" "$USER_PW_B64")"

# ---- 5) Generate UUID ----
UUID_TXT="$(cat /proc/sys/kernel/random/uuid)"

# lokasi file mengikuti cmd_clientcfg kamu (server-psk diambil dari cfg)
SERVER_PSK="$(get_server_key)"
OUT_TXT="${CLIENT_DIR}/${UUID_TXT}-${USERNAME}.txt"

# Pastikan file ada (kalau cmd_clientcfg belum dibuat, tulis minimal Clash entry + ss:// v2rayNG)
if [ ! -f "$OUT_TXT" ]; then
  DOMAIN="$(get_domain)"
  PORT="${SS_PORT:-443}"
  CIPHER="${SS_METHOD:-2022-blake3-aes-128-gcm}"

  # Ambil path dari PRIMARY_TAG (fallback /ss-ws)
  WSPATH_PRIMARY="$(jq -r --arg tag "$PRIMARY_TAG" '.inbounds[]|select(.tag==$tag)|.streamSettings.wsSettings.path // "/ss-ws"' "$XRAY_CFG")"

  # Kalau kamu punya inbound lain (ANTIADS/ANTIPORN) dan mau ikut ditulis:
  WSPATH_ADS="$(jq -r '.inbounds[]|select(.tag=="SSWS-ANTIADS")|.streamSettings.wsSettings.path // empty' "$XRAY_CFG")"
  WSPATH_PORN="$(jq -r '.inbounds[]|select(.tag=="SSWS-ANTIPORN")|.streamSettings.wsSettings.path // empty' "$XRAY_CFG")"

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
    path: "${WSPATH_PRIMARY}"
    mux: false

YAML
fi

# ws path per-tag
get_wspath_for_tag(){ # $1=tag
  jq -r --arg tag "$1" '
    .inbounds[]|select(.tag==$tag)
    | .streamSettings.wsSettings.path // "/ss-ws"
  ' "$XRAY_CFG"
}

# ====== Generate JSON per inbound (v2rayNG) & kumpulkan link unduhan ======
JSON_LINKS=""
UUID_JSON_BASE="$(cat /proc/sys/kernel/random/uuid)"
IFS=','; for TAG in $INBOUND_TAGS; do
  TAG="$(echo "$TAG" | xargs)"
  OUT_JSON="${CLIENT_DIR}/${UUID_JSON_BASE}-${USERNAME}-${TAG}.json"
  write_v2rayng_json "$USERNAME" "$(get_domain)" "$SERVER_PSK" "$USER_PW_B64" "$TAG" "$OUT_JSON"
  BASENAME_JSON="$(basename "$OUT_JSON")"
  JSON_LINKS="${JSON_LINKS}\n- [${TAG}] https://$(get_domain)/${BASENAME_JSON}"
done; unset IFS

# kumpulkan semua path
collect_all_paths_atau(){
  local IFS=',' tag
  {
    for tag in $INBOUND_TAGS; do
      tag="$(echo "$tag" | xargs)"
      get_wspath_for_tag "$tag"
    done
  } | awk 'NF' \
    | awk '!seen[$0]++' \
    | awk '{
        a[++n]=$0
      }
      END{
        if(n==0){ print "" ; exit }
        for(i=1;i<=n;i++){
          printf("<code>%s</code>", a[i])
          if(i<n) printf(" atau ")
        }
        printf("\n")
      }'
}

# ---- 5) Cetak hasil (untuk dikirim balik ke Telegram bot) ----
DOMAIN="$(get_domain)"
NOW_EPOCH="$(date +%s)"
EXPIRE_AT="$(jq -r --arg e "$USERNAME" '.users[$e].expire_at // 0' "$XRAY_DB")"
EXPIRE_WIB="$(wib_from_epoch "$EXPIRE_AT")"
SUB_URL="$(get_sub_url "$USERNAME")"

TLS_PORT="${SS_PORT:-443}"
NTLS_PORT="${HTTP_PORT:-80}"
ALL_PATHS="$(collect_all_paths_atau)"

DL_URL=""
BASENAME="$(basename "$OUT_TXT")"
if [ -f "$OUT_TXT" ]; then
  # asumsi /var/www/html disajikan di https://DOMAIN/
  DL_URL="https://${DOMAIN}/${BASENAME}"
fi

echo -e "HTML_CODE"
echo -e "-=================================-"
echo -e "<b>+++++ShadowSocks-2022 WS Account Created+++++</b>"
echo -e "Username: ${USERNAME}"
echo -e "Domain: <code>${DOMAIN}</code>"
echo -e "Password: <code>${SERVER_PSK}:${USER_PW_B64}</code>"
echo -e "Durasi: 1 Jam"
echo -e "Limit Device: ${MAX_DEV}"
echo -e "TLS/nTLS: ${TLS_PORT}/${NTLS_PORT}"
echo -e "Path WS: ${ALL_PATHS}"
echo -e "Protocol: SS 2022 (${SS_METHOD:-2022-blake3-aes-128-gcm})"
echo -e "Dibuat: $(wib_now)"
printf "Quota: %.2f GB (reset tiap %s hari)\n" "$QUOTA_GB" "$RESET_DAYS"
echo -e "-=================================-"
echo -e "Subscription: ${SUB_URL}"
echo -e "Expired: ${EXPIRE_WIB}"
echo -e "<b>+++++ End of Account Details +++++</b>"
echo -e "-=================================-"
