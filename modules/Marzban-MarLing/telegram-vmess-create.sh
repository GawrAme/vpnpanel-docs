#!/usr/bin/env bash

USERNAME="$1"
PASSWORD="$2"
EXPIRED="$3"

tunnel_name="VMESS"
tunnel_type="VMESS"
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
    "vmess": [
      "'"${tunnel_type}"'_WS",
      "'"${tunnel_type}"'_WS_ANTIADS",
      "'"${tunnel_type}"'_WS_ANTIPORN",
      "'"${tunnel_type}"'_HTTPUPGRADE",
      "'"${tunnel_type}"'_HU_ANTIADS",
      "'"${tunnel_type}"'_HU_ANTIPORN",
      "'"${tunnel_type}"'_GRPC"
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
    "vmess": {
      "id": "'"${PASSWORD}"'"
    }
  },
  "status": "active",
  "username": "'"${USERNAME}"'"
}'

response_file="/tmp/${USERNAME}_vmess.json"
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
SUBS=$(echo "${res_json}" | jq -r '.subscription_url')

addconfig-vmess.sh ${USERNAME} ${PASSWORD} ${EXPIRED}

echo -e "HTML_CODE"
echo -e "<b>+++++ ${tunnel_name} Account Created +++++</b>"
echo -e "Username: <code>${USERNAME}</code>"
echo -e "UUID: <code>${PASSWORD}</code>"
echo -e "Data Limit: <code>${limit_gb}</code> GB"
echo -e "Cek Kuota : https://${DOMAIN}${SUBS}"
echo -e "Detail akun : https://${DOMAIN}/${PASSWORD}-${USERNAME}.txt"
echo -e "================================="
echo -e "Masa Aktif: $(date -d "@${expire}" '+%Y-%m-%d %H:%M:%S')"
echo -e "<b>+++++ End of Account Details +++++</b>"
