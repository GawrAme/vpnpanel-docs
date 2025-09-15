#!/usr/bin/env bash

# Configuration Telegram
source "/etc/gegevps/bin/telegram_config.conf"

# Escape HTML sederhana untuk aman di parse_mode=HTML
html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Kirim pesan ke Telegram (auto urlencode teks)
tg_send() {
  local RAW_TEXT="$1"
  # gunakan --data-urlencode agar newline & karakter khusus aman
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$(printf '%s' "$RAW_TEXT")" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1
}
### [ADD] === end Telegram Notifier ===

USERNAME="$1"
PASSWORD="$2"
EXPIRED="$3"

tunnel_name="Trojan"
tunnel_type="TROJAN"
limit_gb="1024"
limit_bytes=$((limit_gb * 1024 * 1024 * 1024))
expired_timestamp=$(date -d "+${EXPIRED} days" +%s)
current_date=$(date "+%Y-%m-%d %H:%M:%S")
UUID=$(cat /proc/sys/kernel/random/uuid)

DOMAIN=$(cat /root/domain)
IP_FILE="/tmp/myip.txt"

# Kalau file sudah ada dan tidak kosong, pakai isinya
if [[ -s "$IP_FILE" ]]; then
    IP_ADDR=$(cat "$IP_FILE")
else
    # Ambil IPv4 dari ifconfig.me
    IP_ADDR=$(curl -s4 ifconfig.me)
    echo "$IP_ADDR" > "$IP_FILE"
fi

api_host="127.0.0.1"
api_port="YOUR_API_PORT"
api_username="YOUR_API_USERNAME"
api_password="YOUR_API_PASSWORD"
api_token="$(curl -sSkL -X 'POST' \
  "http://${api_host}:${api_port}/api/admin/token" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "grant_type=password&username=${api_username}&password=${api_password}&scope=&client_id=&client_secret=" | jq -r .access_token)"

if [[ -z "$USERNAME" || -z "$PASSWORD" || -z "$EXPIRED" ]]; then
    echo "Usage: $0 <username> <password> <expired_days>"
    exit 1
fi

# Inbounds array (pakai array Bash, bukan string)
inbounds_list=(
  "${tunnel_type}_WS"
  "${tunnel_type}_WS_ANTIADS"
  "${tunnel_type}_WS_ANTIPORN"
  "${tunnel_type}_HTTPUPGRADE"
  "${tunnel_type}_HU_ANTIADS"
  "${tunnel_type}_HU_ANTIPORN"
  "${tunnel_type}_GRPC"
)

# Jika expired 90 hari, tambahkan TCP
if (( EXPIRED >= 90 )); then
  inbounds_list+=("${tunnel_type}_TCP")
fi

# Format array jadi JSON list pakai jq
inbounds_json=$(printf '%s\n' "${inbounds_list[@]}" | jq -R . | jq -s .)

# Buat JSON request ke API
req_json='{
  "data_limit": '"${limit_bytes}"',
  "data_limit_reset_strategy": "month",
  "expire": '"${expired_timestamp}"',
  "inbounds": {
    "trojan": '"${inbounds_json}"'
  },
  "next_plan": {
    "add_remaining_traffic": false,
    "data_limit": 0,
    "expire": 0,
    "fire_on_either": true
  },
  "note": "CREATED AT '"${current_date}"'",
  "proxies": {
    "trojan": {
      "password": "'"${PASSWORD}"'"
    }
  },
  "status": "active",
  "username": "'"${USERNAME}"'"
}'

# Kirim request ke API
response_file="/tmp/${USERNAME}_trojan.json"
http_response=$(curl -sSkL -w "%{http_code}" -o "${response_file}" -X 'POST' \
  "http://${api_host}:${api_port}/api/user" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${api_token}" \
  -d "${req_json}")
res_json=$(cat "${response_file}")
rm -rf "${response_file}"

if [[ "$http_response" != "200" ]]; then
    echo "API Response: $(echo "${res_json}" | jq -r '.detail')"

    ### [ADD] === Telegram: kirim notifikasi GAGAL ===
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
      error_detail="$(echo "${res_json}" | jq -r '.detail // .message // .error // "Unknown error"')"
      # susun pesan & escape HTML
      mapfile -t MSG_LINES <<EOF
Pembuatan akun <b>GAGAL</b>!
Username : $(printf '%s' "$USERNAME" | html_escape)
Protocol : $(printf '%s' "$tunnel_name" | html_escape)
Durasi : $(printf '%s' "$EXPIRED" | html_escape)
Waktu    : $(printf '%s' "$current_date" | html_escape)
HTTP Code: $(printf '%s' "$http_response" | html_escape)
Detail   : $(printf '%s' "$error_detail" | html_escape)
EOF
      tg_send "$(printf '%s\n' "${MSG_LINES[@]}")"
    fi
    ### [ADD] === end notifikasi GAGAL ===

    exit 1
fi

# Ambil hasil dari response
expire=$(echo "${res_json}" | jq -r '.expire')
SUBS=$(echo "${res_json}" | jq -r '.subscription_url')

### [ADD] === Telegram: kirim notifikasi BERHASIL ===
if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
  expire_human="$(date -d "@${expire}" '+%Y-%m-%d %H:%M:%S')"
  subscription_full="https://${DOMAIN}${SUBS}"

  mapfile -t OK_LINES <<EOF
Pembuatan akun <b>berhasil</b>!
<b>+++++ $(printf '%s' "$tunnel_name" | html_escape) Account Created +++++</b>
Username : $(printf '%s' "$USERNAME" | html_escape)
Password : $(printf '%s' "$PASSWORD" | html_escape)
Durasi : $(printf '%s' "$EXPIRED" | html_escape)
Protocol : $(printf '%s' "$tunnel_name" | html_escape)
Akun dibuat pada : $(printf '%s' "$current_date" | html_escape)
Subscription : $(printf '%s' "$subscription_full" | html_escape)
Expired : $(printf '%s' "$expire_human" | html_escape)
EOF
  tg_send "$(printf '%s\n' "${OK_LINES[@]}")"
fi
### [ADD] === end notifikasi BERHASIL ===

# Tambahkan ke konfigurasi lokal
addconfig-trojan.sh "${USERNAME}" "${PASSWORD}" "${EXPIRED}"

# Output ke user
echo -e "HTML_CODE"
echo -e "<b>+++++ ${tunnel_name} Account Created +++++</b>"
echo -e "Username: <code>${USERNAME}</code>"
echo -e "Password: <code>${PASSWORD}</code>"
echo -e "Domain: <code>${DOMAIN}</code>"
if (( EXPIRED >= 90 )); then
    echo -e "IP Address: <code>${IP_ADDR}</code>"
fi
echo -e "Data Limit: <code>${limit_gb}</code> GB"
echo -e "Cek Kuota : https://${DOMAIN}${SUBS}"
echo -e "Detail akun : https://${DOMAIN}/${PASSWORD}-${USERNAME}.txt"
echo -e "================================="
echo -e "Masa Aktif: $(date -d "@${expire}" '+%Y-%m-%d %H:%M:%S')"
echo -e "<b>+++++ End of Account Details +++++</b>"
