#!/usr/bin/env bash

USERNAME="$1"
PASSWORD="$2"
EXPIRED="$3"

tunnel_name="Shadowsocks"
tunnel_type="SHADOWSOCKS"
limit_gb="1024"
limit_bytes=$((limit_gb * 1024 * 1024 * 1024))
expired_timestamp=$(date -d "+${EXPIRED} days" +%s)
current_date=$(date "+%Y-%m-%d %H:%M:%S")

DOMAIN=$(cat /root/domain)
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

req_json='{
  "data_limit": '"${limit_bytes}"',
  "data_limit_reset_strategy": "month",
  "expire": '"${expired_timestamp}"',
  "inbounds": {
    "shadowsocks": [
      "'"${tunnel_type}"'_OUTLINE"
    ]
  },
  "next_plan": {
    "add_remaining_traffic": false,
    "data_limit": 0,
    "expire": 0,
    "fire_on_either": true
  },
  "note": "CREATED AT '"${current_date}"'",
  "proxies": {
    "shadowsocks": {
      "password": "'"${PASSWORD}"'",
      "method": "aes-128-gcm"
    }
  },
  "status": "active",
  "username": "'"${USERNAME}"'"
}'

response_file="/tmp/$(uuid).json"
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
    exit 1
fi

expire=$(echo "${res_json}" | jq -r '.expire')
link=$(echo "${res_json}" | jq -r '.links[0]')

echo -e "<b>+++++ ${tunnel_name} Account Created +++++</b>"
echo -e "Username: <code>${USERNAME}</code>"
echo -e "Password: <code>${PASSWORD}</code>"
echo -e "Expired: <code>$(date -d "@${expire}" '+%Y-%m-%d %H:%M:%S')</code>"
echo -e "Data Limit: <code>${limit_gb}</code> GB"
echo -e "Link : <code>${link}</code>"
echo -e "<b>+++++ End of Account Details +++++</b>"

echo -e "=======-XRAY/${tunnel_name}-OUTLINE======="
echo -e ""
echo -e "Remarks: ${USERNAME}"
echo -e "Domain: ${DOMAIN}"
echo -e "Quota: ${limit_gb}GB"
echo -e "Reset Quota Strategy: Bulanan"
echo -e "================================="
echo -e "Port Outline: 1080"
echo -e "================================="
echo -e "password: ${PASSWORD}"
echo -e "Method: aes-128-gcm"
echo -e "network: none"
echo -e "================================="
echo -e "alpn: h2, http/1.1"
echo -e "tls: none"
echo -e "allowInsecure: true"
echo -e "================================="
echo -e "Link Subscription : https://${DOMAIN}${SUBS}"
echo -e "================================="
echo -e "Masa Aktif: $(date -d "@${expire}" '+%Y-%m-%d %H:%M:%S')"
echo -e "<b>+++++ End of Account Details +++++</b>"
