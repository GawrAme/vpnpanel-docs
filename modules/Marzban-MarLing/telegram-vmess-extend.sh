#!/usr/bin/env bash

############################################
# [ADD] Telegram Notifier
############################################
# Configuration Telegram
source "/etc/gegevps/bin/telegram_config.conf"

# Escape HTML sederhana untuk parse_mode=HTML
html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Kirim pesan ke Telegram dengan aman (URL-encode)
tg_send() {
  local RAW_TEXT="$1"
  if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=$(printf '%s' "$RAW_TEXT")" \
      --data-urlencode "parse_mode=HTML" \
      --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1
  fi
}
############################################
# [END ADD]
############################################

USERNAME="$1"
PASSWORD="$2"
EXPIRED="$3"

DOMAIN=$(cat /root/domain)
tunnel_name="VMESS"
limit_gb="1024"
limit_bytes=$((limit_gb * 1024 * 1024 * 1024))
expired_seconds=$((EXPIRED * 24 * 60 * 60))

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

response_file="/tmp/${USERNAME}_vmess.json"

# GET USER
http_response=$(curl -sSkL -w "%{http_code}" -o "${response_file}" -X 'GET' \
  "http://${api_host}:${api_port}/api/user/${USERNAME}" \
  -H 'accept: application/json' \
  -H "Authorization: Bearer ${api_token}")
get_user=$(cat "${response_file}")
rm -rf "${response_file}"

if [[ "$http_response" != "200" ]]; then
    echo "API Response: $(echo "${get_user}" | jq -r '.detail')"

    ############################################
    # [ADD] Notif Telegram: GAGAL (GET user)
    ############################################
    err_detail="$(echo "${get_user}" | jq -r '.detail // .message // .error // "Unknown error"')"
    mapfile -t TG_FAIL_GET <<EOF
Perpanjangan akun <b>GAGAL</b> (GET user)!
Username : $(printf '%s' "$USERNAME" | html_escape)
Protocol : $(printf '%s' "$tunnel_name" | html_escape)
Waktu    : $(printf '%s' "$current_date" | html_escape)
HTTP Code: $(printf '%s' "$http_response" | html_escape)
Detail   : $(printf '%s' "$err_detail" | html_escape)
EOF
    tg_send "$(printf '%s\n' "${TG_FAIL_GET[@]}")"
    ############################################

    exit 1
fi

expire_before=$(echo "${get_user}" | jq -r '.expire')
expire_after=$((expire_before + expired_seconds))

# MODIFY_USER
req_json='{
  "expire": '"${expire_after}"'
}'

http_response=$(curl -sSkL -w "%{http_code}" -o "${response_file}" -X 'PUT' \
  "http://${api_host}:${api_port}/api/user/${USERNAME}" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${api_token}" \
  -d "${req_json}")
mod_user=$(cat "${response_file}")
rm -rf "${response_file}"

if [[ "$http_response" != "200" ]]; then
    echo "API Response: $(echo "${mod_user}" | jq -r '.detail')"

    ############################################
    # [ADD] Notif Telegram: GAGAL (PUT modify)
    ############################################
    err_detail="$(echo "${mod_user}" | jq -r '.detail // .message // .error // "Unknown error"')"
    exp_before_h="$(date -d "@${expire_before}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    mapfile -t TG_FAIL_PUT <<EOF
Perpanjangan akun <b>GAGAL</b> (MODIFY user)!
-=================================-
Username : $(printf '%s' "$USERNAME" | html_escape)
Protocol : $(printf '%s' "$tunnel_name" | html_escape)
Waktu    : $(printf '%s' "$current_date" | html_escape)
Durasi   : $(printf '%s' "$EXPIRED" | html_escape) hari
Sebelum  : $(printf '%s' "$exp_before_h" | html_escape)
HTTP Code: $(printf '%s' "$http_response" | html_escape)
Detail   : $(printf '%s' "$err_detail" | html_escape)
EOF
    tg_send "$(printf '%s\n' "${TG_FAIL_PUT[@]}")"
    ############################################

    exit 1
fi

expire=$(echo "${mod_user}" | jq -r '.expire')
used_traffic=$(echo "${mod_user}" | jq -r '.used_traffic')
used_traffic_gb=$(awk "BEGIN {printf \"%.2f\", ${used_traffic}/1024/1024/1024}")
SUBS=$(echo "${mod_user}" | jq -r '.subscription_url')

############################################
# [ADD] Notif Telegram: BERHASIL
############################################
exp_before_h="$(date -d "@${expire_before}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
exp_after_h="$(date -d "@${expire}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
subscription_full="https://${DOMAIN}${SUBS}"

mapfile -t TG_OK <<EOF
Perpanjangan akun <b>BERHASIL</b>!
-=================================-
Username : $(printf '%s' "$USERNAME" | html_escape)
Protocol : $(printf '%s' "$tunnel_name" | html_escape)
Diperpanjang pada : $(printf '%s' "$current_date" | html_escape)
Durasi : $(printf '%s' "$EXPIRED" | html_escape) hari
Expired (sebelum) : $(printf '%s' "$exp_before_h" | html_escape)
Expired (sesudah) : $(printf '%s' "$exp_after_h" | html_escape)
Used Traffic : $(printf '%s' "$used_traffic_gb" | html_escape) GB
Subscription : $(printf '%s' "$subscription_full" | html_escape)
EOF
tg_send "$(printf '%s\n' "${TG_OK[@]}")"
############################################
echo -e "HTML_CODE"
echo -e "<b>+++++ ${tunnel_name} Account Extended +++++</b>"
echo -e "Username: <code>${USERNAME}</code>"
echo -e "Password: <code>${PASSWORD}</code>"
echo -e "Expired: <code>$(date -d "@${expire}" '+%Y-%m-%d %H:%M:%S')</code>"
echo -e "Data Limit: <code>${limit_gb}</code> GB"
echo -e "Used Traffic: <code>${used_traffic_gb}</code> GB"
echo -e "Link Subscription : https://${DOMAIN}${SUBS}"
echo -e "<b>+++++ End of Account Details +++++</b>"
