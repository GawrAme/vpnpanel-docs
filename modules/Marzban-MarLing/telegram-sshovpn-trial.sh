#!/usr/bin/env bash
set -euo pipefail

# ====== Config Telegram ======
source "/etc/gegevps/bin/telegram_config.conf"

# ====== Input ======
USERNAME="${1}"
PASSWORD="${2}"
EXPIRED="${3}"
TRANSPORT="${4}"
EXPIRED_TIMESTAMP_BOT="${5}"

if [[ -z "$USERNAME" || -z "$PASSWORD" || -z "$EXPIRED" ]]; then
  echo "Usage: $0 <username> <password> <expired_days>" >&2
  exit 1
fi

# ====== LingVPN / koneksi defaults (bisa override via ENV) ======
LVCTL="${LVCTL:-/usr/local/sbin/lvctl}"
DOMAIN="$(test -f /root/domain && sed -n '1p' /root/domain || echo localhost)"
WS_PATH="${LV_WS_PATH:-/sshws}"
TLS_PORT="${LV_TLS_PORT:-443}"
NTLS_PORT="${LV_NTLS_PORT:-80}"

# Optional default untuk pembuatan akun
QUOTA_GB="${LV_DEFAULT_QUOTA_GB:-2}"
MAX_DEVICES="${LV_DEFAULT_MAX_DEVICES:-3}"
RESET_STRATEGY="${LV_DEFAULT_RESET:-none}"

# ====== Util ======
html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

tg_send() {
  local RAW_TEXT="$1"
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$(printf '%s' "$RAW_TEXT")" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
}

bytes_h() {
  # humanize bytes (GB/MB)
  local b="${1:-0}"
  awk -v b="$b" 'BEGIN{
    split("B KB MB GB TB PB",u);
    i=1; while (b>=1024 && i<6){b/=1024; i++}
    if (i==1) printf("%d %s", b,u[i]); else printf("%.2f %s", b,u[i])
  }'
}

# ====== Buat akun via lvctl ======
if ! command -v "$LVCTL" >/dev/null 2>&1; then
  echo "Error: lvctl tidak ditemukan di $LVCTL" >&2
  exit 1
fi

ADD_OUT="$("$LVCTL" add "$USERNAME" "$PASSWORD" "$EXPIRED" "$QUOTA_GB" "$MAX_DEVICES" "$RESET_STRATEGY" 2>&1)" || {
  # kirim GAGAL
  NOW="$(date '+%Y-%m-%d %H:%M:%S')"
  mapfile -t FAIL_MSG <<EOF
Pembuatan akun <b>GAGAL</b>!
-=================================-
Username: $(printf '%s' "$USERNAME" | html_escape)
Domain: $(printf '%s' "$DOMAIN"   | html_escape)
Durasi: $(printf '%s' "$EXPIRED"  | html_escape) hari
Waktu: $(printf '%s' "$NOW"      | html_escape)
Detail: $(printf '%s' "$ADD_OUT"  | html_escape)
EOF
  tg_send "$(printf '%s\n' "${FAIL_MSG[@]}")"
  echo "$ADD_OUT" >&2
  exit 1
}

# Zona waktu WIB
JKT_TZ="Asia/Jakarta"

# Ambil expire epoch dari DB
DB=/etc/lingvpn/db.json
EXPIRE_EPOCH="0"
if command -v jq >/dev/null 2>&1 && [[ -s "$DB" ]]; then
  EXPIRE_EPOCH="$(jq -r --arg u "$USERNAME" '.users[$u].expire_at // 0' "$DB" 2>/dev/null || echo 0)"
fi

# Format ke WIB
if [[ -n "$EXPIRE_EPOCH" && "$EXPIRE_EPOCH" != "0" ]]; then
  EXPIRE_HUMAN="$(TZ="$JKT_TZ" date -d "@$EXPIRE_EPOCH" '+%Y-%m-%d %H:%M:%S WIB' 2>/dev/null || echo '-')"
else
  EXPIRE_HUMAN="-"
fi

# Waktu sekarang juga pakai WIB
NOW="$(TZ="$JKT_TZ" date '+%Y-%m-%d %H:%M:%S WIB')"

# === Durasi (human readable) dari EXPIRED (hari; boleh desimal) ===
DUR_LABEL="$(python3 - <<'PY' "$EXPIRED"
import sys, math
try:
    d = float(sys.argv[1])   # hari (boleh desimal)
except:
    d = 0.0
secs = int(round(max(0.0, d) * 86400))
if secs >= 86400:
    days = secs // 86400
    print(f"{days} hari")
elif secs >= 3600:
    hours = secs // 3600
    print(f"{hours} jam")
else:
    mins = max(1, secs // 60)
    print(f"{mins} menit")
PY
)"

# ====== Payload injector ======
PAYLOAD=$(cat <<TPL
GET ${WS_PATH}?u=${USERNAME}&p=${PASSWORD} HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Upgrade: WebSocket[crlf]Connection: Keep-Alive[crlf]User-Agent: [ua][crlf][crlf]
TPL
)

# ====== Buat Status URL (lvsub) pakai HMAC /etc/lingvpn/sub.secret ======
STATUS_URL="-"
if [[ -s /etc/lingvpn/sub.secret ]]; then
  TOKEN="$(python3 - "$USERNAME" <<'PY'
import sys, hmac, hashlib, pathlib
u=sys.argv[1]
key=pathlib.Path("/etc/lingvpn/sub.secret").read_bytes().strip()
print(hmac.new(key, u.encode(), hashlib.sha256).hexdigest())
PY
)"
  STATUS_URL="https://${DOMAIN}/lvsub/?u=${USERNAME}&t=${TOKEN}"
fi

# ====== Buat DarkTunnel import URL ======
DARKTUNNEL_URL="$(python3 - <<'PY'
import json,base64,sys,os
user  = os.environ.get("DT_USER")
pw    = os.environ.get("DT_PASS")
dom   = os.environ.get("DT_DOMAIN")
wsp   = os.environ.get("DT_PATH")
tls_p = int(os.environ.get("DT_TLS_PORT","443"))
payload = f"GET {wsp}?u={user}&p={pw} HTTP/1.1[crlf]Host: {dom}[crlf]Upgrade: WebSocket[crlf]Connection: Keep-Alive[crlf]User-Agent: [ua][crlf][crlf]"
obj = {
  "type":"SSH",
  "name":"LingVPN",
  "sshTunnelConfig":{
    "sshConfig":{
      "host": dom,
      "port": tls_p,
      "username": user,
      "password": pw
    },
    "injectConfig":{
      "mode":"DIRECT_SNI",
      "serverNameIndication": dom,
      "payload": payload
    }
  }
}
js = json.dumps(obj,separators=(',',':'),ensure_ascii=False).encode()
print("darktunnel://" + base64.b64encode(js).decode())
PY
)"

export DT_USER="$USERNAME" DT_PASS="$PASSWORD" DT_DOMAIN="$DOMAIN" DT_PATH="$WS_PATH" DT_TLS_PORT="$TLS_PORT"
DARKTUNNEL_URL="$(DT_USER="$USERNAME" DT_PASS="$PASSWORD" DT_DOMAIN="$DOMAIN" DT_PATH="$WS_PATH" DT_TLS_PORT="$TLS_PORT" python3 - <<'PY'
import json,base64,sys,os
user  = os.environ["DT_USER"]
pw    = os.environ["DT_PASS"]
dom   = os.environ["DT_DOMAIN"]
wsp   = os.environ["DT_PATH"]
tls_p = int(os.environ["DT_TLS_PORT"])
payload = f"GET {wsp}?u={user}&p={pw} HTTP/1.1[crlf]Host: {dom}[crlf]Upgrade: WebSocket[crlf]Connection: Keep-Alive[crlf]User-Agent: [ua][crlf][crlf]"
obj = {
  "type":"SSH",
  "name":"LingVPN",
  "sshTunnelConfig":{
    "sshConfig":{
      "host": dom,
      "port": tls_p,
      "username": user,
      "password": pw
    },
    "injectConfig":{
      "mode":"DIRECT_SNI",
      "serverNameIndication": dom,
      "payload": payload
    }
  }
}
js = json.dumps(obj,separators=(',',':'),ensure_ascii=False).encode()
print("darktunnel://" + base64.b64encode(js).decode())
PY
)"

# ====== Hitung limit human (dari QUOTA_GB) ======
if [[ "${QUOTA_GB}" == "0" ]]; then
  LIMIT_H="Unlimited"
else
  # tampilkan "x.xx GB"
  LIMIT_H="$(awk -v g="${QUOTA_GB}" 'BEGIN{printf("%.2f GB", g+0)}')"
fi

NOW="$(date '+%Y-%m-%d %H:%M:%S')"

# ====== Telegram: BERHASIL ======
mapfile -t OK_MSG <<EOF
Pembuatan akun Trial <b>BERHASIL</b>!
-=================================-
<b>+++++ SSH-WS Trial Account Created +++++</b>
Domain: $(printf '%s' "$DOMAIN"    | html_escape)
Username: $(printf '%s' "$USERNAME"  | html_escape)
Password: $(printf '%s' "$PASSWORD"  | html_escape)
Port: $(printf '%s' "$TLS_PORT"  | html_escape) [TLS], $(printf '%s' "$NTLS_PORT" | html_escape) [nTLS]
Durasi: $(printf '%s' "$DUR_LABEL"   | html_escape)
Limit: $(printf '%s' "$LIMIT_H"   | html_escape)
Status: $(printf '%s' "$STATUS_URL"| html_escape)
DarkTunnel: <code>$(printf '%s' "$DARKTUNNEL_URL" | html_escape)</code>
-=================================-
Payload (injector):
<code>$(printf '%s' "$PAYLOAD" | html_escape)</code>
-=================================-
Akun dibuat pada:  $(printf '%s' "$NOW"          | html_escape)
Expired: $(printf '%s' "$EXPIRE_HUMAN" | html_escape)
EOF
tg_send "$(printf '%s\n' "${OK_MSG[@]}")"

# ====== Output ke STDOUT (buat panel) ======
echo -e "HTML_CODE"
echo -e "<b>+++++ SSH-WS Trial Account Created +++++</b>"
echo -e "Domain: <code>${DOMAIN}</code>"
echo -e "Username: <code>${USERNAME}</code>"
echo -e "Password: <code>${PASSWORD}</code>"
echo -e "Port: ${TLS_PORT} [TLS], ${NTLS_PORT} [nTLS]"
echo -e "Path: ${WS_PATH}?u=${USERNAME}&p=${PASSWORD}"
echo -e "Durasi: ${DUR_LABEL}"
echo -e "Limit: ${LIMIT_H}"
echo -e "Status: ${STATUS_URL}"
echo -e "-=================================-"
echo -e "DarkTunnel: <code>${DARKTUNNEL_URL}</code>"
echo -e ""
echo -e "Payload [INGIN MENGGUNAKAN PAYLOAD SENDIRI? HARAP JANGAN UBAH BAGIAN PATH ${WS_PATH}?u=${USERNAME}&p=${PASSWORD}"
echo -e "<code>${PAYLOAD}</code>"
echo -e "================================="
echo -e "Masa Aktif: <b>${EXPIRE_HUMAN}</b>"
echo -e "<b>+++++ End of Account Details +++++</b>"
