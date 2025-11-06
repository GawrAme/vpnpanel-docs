#!/usr/bin/env bash
set -euo pipefail

# ========= Telegram Config =========
source "/etc/gegevps/bin/telegram_config.conf"

html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
tg_send() {
  local RAW_TEXT="${1:-}"
  [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] || return 0
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$(printf '%s' "$RAW_TEXT")" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
}

# ========= Inputs =========
USERNAME="${1:-}"
PASSWORD="${2:-}"
EXPIRED="${3:-}"   # days to extend

if [[ -z "$USERNAME" || -z "$PASSWORD" || -z "$EXPIRED" ]]; then
  echo "Usage: $0 <username> <password> <expired_days>" >&2
  exit 1
fi
if ! [[ "$EXPIRED" =~ ^[0-9]+$ ]]; then
  echo "expired_days harus integer (hari)" >&2
  exit 1
fi

# ========= Env / Defaults =========
LVCTL="${LVCTL:-/usr/local/sbin/lvctl}"
DB="/etc/lingvpn/db.json"
DOMAIN="$(test -f /root/domain && sed -n '1p' /root/domain || echo localhost)"
WS_PATH="${LV_WS_PATH:-/sshws}"
TLS_PORT="${LV_TLS_PORT:-443}"
NTLS_PORT="${LV_NTLS_PORT:-80}"

now_h="$(date '+%Y-%m-%d %H:%M:%S')"

# ========= Helper: read user record from DB =========
read_json_field() {  # $1=json $2=key
  python3 - "$1" "$2" <<'PY'
import json,sys
j=json.loads(sys.argv[1]); k=sys.argv[2]
v=j
for part in k.split('.'):
    if isinstance(v,dict) and part in v:
        v=v[part]
    else:
        print(""); sys.exit(0)
print(v if v is not None else "")
PY
}

if [[ ! -s "$DB" ]]; then
  msg="DB tidak ditemukan: $DB"
  tg_send "$(printf '%s\n' \
    "Perpanjangan akun <b>GAGAL</b>!" \
    "-=================================-" \
    "Username : $(printf '%s' "$USERNAME" | html_escape)" \
    "Waktu    : $(printf '%s' "$now_h" | html_escape)" \
    "Detail   : $(printf '%s' "$msg" | html_escape)")"
  echo "$msg" >&2
  exit 1
fi

DB_JSON="$(cat "$DB")"
USER_JSON="$(python3 - "$DB" "$USERNAME" <<'PY'
import json,sys
db=json.load(open(sys.argv[1],'r'))
u=sys.argv[2]
print(json.dumps(db.get("users",{}).get(u, {})))
PY
)"

if [[ -z "$USER_JSON" || "$USER_JSON" == "{}" ]]; then
  tg_send "$(printf '%s\n' \
    "Perpanjangan akun <b>GAGAL</b>!" \
    "-=================================-" \
    "Username : $(printf '%s' "$USERNAME" | html_escape)" \
    "Waktu    : $(printf '%s' "$now_h" | html_escape)" \
    "Detail   : $(printf '%s' "user tidak ada di DB" | html_escape)")"
  echo "user tidak ada di DB" >&2
  exit 1
fi

expire_before="$(read_json_field "$USER_JSON" "expire_at")"
expire_before="${expire_before:-0}"

# ========= Extend via lvctl =========
if ! command -v "$LVCTL" >/dev/null 2>&1; then
  tg_send "$(printf '%s\n' \
    "Perpanjangan akun <b>GAGAL</b>!" \
    "-=================================-" \
    "Username : $(printf '%s' "$USERNAME" | html_escape)" \
    "Waktu    : $(printf '%s' "$now_h" | html_escape)" \
    "Detail   : $(printf '%s' "lvctl tidak ditemukan" | html_escape)")"
  echo "lvctl tidak ditemukan" >&2
  exit 1
fi

RENEW_OUT="$("$LVCTL" renew "$USERNAME" "$EXPIRED" 2>&1)" || {
  tg_send "$(printf '%s\n' \
    "Perpanjangan akun <b>GAGAL</b>!" \
    "-=================================-" \
    "Username : $(printf '%s' "$USERNAME" | html_escape)" \
    "Waktu    : $(printf '%s' "$now_h" | html_escape)" \
    "Detail   : $(printf '%s' "$RENEW_OUT" | html_escape)")"
  echo "$RENEW_OUT" >&2
  exit 1
}

# reload DB
DB_JSON2="$(cat "$DB")"
USER_JSON2="$(python3 - "$DB" "$USERNAME" <<'PY'
import json,sys
db=json.load(open(sys.argv[1],'r'))
u=sys.argv[2]
print(json.dumps(db.get("users",{}).get(u, {})))
PY
)"
expire_after="$(read_json_field "$USER_JSON2" "expire_at")"
expire_after="${expire_after:-0}"

# ========= Human-readable fields =========
exp_before_h="$(date -u -d "@${expire_before}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '-')"
exp_after_h="$(date -u -d "@${expire_after}"  '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '-')"

used_bytes="$(read_json_field "$USER_JSON2" "used_bytes")"
used_bytes="${used_bytes:-0}"
cum_bytes="$(read_json_field "$USER_JSON2" "cum_used_bytes")"
cum_bytes="${cum_bytes:-0}"
quota_bytes="$(read_json_field "$USER_JSON2" "quota_bytes")"
quota_bytes="${quota_bytes:-0}"

human_bytes() {
  python3 - "$1" <<'PY'
import sys
b=int(sys.argv[1]) if sys.argv[1] else 0
u=["B","KB","MB","GB","TB","PB"]
i=0
v=float(b)
while v>=1024 and i<len(u)-1:
    v/=1024; i+=1
print(f"{int(v)} {u[i]}" if i==0 else f"{v:.2f} {u[i]}")
PY
}
used_h="$(human_bytes "$used_bytes")"
cum_h="$(human_bytes "$cum_bytes")"
limit_h=$([ "$quota_bytes" = "0" -o -z "$quota_bytes" ] && echo "Unlimited" || human_bytes "$quota_bytes")

# ========= Build Status URL (lvsub) =========
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

# ========= DarkTunnel import URL =========
DARKTUNNEL_URL="$(DT_USER="$USERNAME" DT_PASS="$PASSWORD" DT_DOMAIN="$DOMAIN" DT_PATH="$WS_PATH" DT_TLS_PORT="$TLS_PORT" python3 - <<'PY'
import json,base64,os
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
    "sshConfig":{"host":dom,"port":tls_p,"username":user,"password":pw},
    "injectConfig":{"mode":"DIRECT_SNI","serverNameIndication":dom,"payload":payload}
  }
}
print("darktunnel://" + base64.b64encode(json.dumps(obj,separators=(',',':'),ensure_ascii=False).encode()).decode())
PY
)"

# ========= Telegram: OK =========
mapfile -t TG_OK <<EOF
Perpanjangan akun SSH-WS <b>BERHASIL</b>!
-=================================-
Username: $(printf '%s' "$USERNAME" | html_escape)
Diperpanjang pada: $(printf '%s' "$now_h" | html_escape)
Durasi: $(printf '%s' "$EXPIRED" | html_escape) hari
-=================================-
Expired (sebelum): $(printf '%s' "$exp_before_h" | html_escape)
Expired (sesudah): $(printf '%s' "$exp_after_h" | html_escape)
-=================================-
Limit (periode): $(printf '%s' "$limit_h" | html_escape)
Used (periode): $(printf '%s' "$used_h" | html_escape)
Total Used: $(printf '%s' "$cum_h" | html_escape)
Status Page:  $(printf '%s' "$STATUS_URL" | html_escape)
EOF
tg_send "$(printf '%s\n' "${TG_OK[@]}")"

# ========= STDOUT for panel =========
echo -e "HTML_CODE"
echo -e "<b>+++++ SSH-WS Account Extended +++++</b>"
echo -e "Username: <code>${USERNAME}</code>"
echo -e "Domain: <code>${DOMAIN}</code>"
echo -e "Durasi: <code>${EXPIRED}</code> hari"
echo -e "Expired (sebelum): <b>${exp_before_h}</b>"
echo -e "Expired (sesudah): <b>${exp_after_h}</b>"
echo -e "-=================================-"
echo -e "Limit (periode): <code>${limit_h}</code>"
echo -e "Used (periode): <code>${used_h}</code>"
echo -e "Total Used: <code>${cum_h}</code>"
echo -e "-=================================-"
echo -e "Status Page: <code>${STATUS_URL}</code>"
echo -e "DarkTunnel: <code>${DARKTUNNEL_URL}</code>"
echo -e "<b>+++++ End of Details +++++</b>"
