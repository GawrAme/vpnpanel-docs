#!/usr/bin/env bash

USERNAME="$1"
PASSWORD="$2"
EXPIRED="$3"

current_date=$(date "+%Y-%m-%d %H:%M:%S")
tunnel_name="Trojan"
tunnel_type="TROJAN"
limit_gb="1024"
limit_bytes=$((limit_gb * 1024 * 1024 * 1024))
expired_timestamp=$(date -d "+${EXPIRED} days" +%s)

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
    "trojan": [
      "'"${tunnel_type}"'_TCP",
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
    "trojan": {
      "password": "'"${PASSWORD}"'"
    }
  },
  "status": "active",
  "username": "'"${USERNAME}"'"
}'

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
    exit 1
fi

# Link Trojan
trojanlink1="trojan://${PASSWORD}@${DOMAIN}:443?security=tls&type=tcp&host=&headerType=&path=&sni=${DOMAIN}&fp=&alpn=h2#%28${USERNAME}%29%20%5BTrojan%20-%20TCP%5D%20TLS"
trojanlink2="trojan://${PASSWORD}@${DOMAIN}:443?security=tls&type=ws&host=${DOMAIN}&headerType=&path=%2Ftrojan&sni=${DOMAIN}&fp=&alpn=http%2F1.1#%28${USERNAME}%29%20%5BTrojan%20-%20WS%5D%20TLS"
trojanlink3="trojan://${PASSWORD}@${DOMAIN}:80?security=none&type=ws&host=${DOMAIN}&headerType=&path=%2Ftrojan#%28${USERNAME}%29%20%5BTrojan%20-%20WS%5D%20nonTLS"
trojanlink4="trojan://${PASSWORD}@${DOMAIN}:443?security=tls&type=grpc&host=&headerType=&serviceName=trojan-service&sni=${DOMAIN}&fp=&alpn=h2#%28${USERNAME}%29%20%5BTrojan%20-%20GRPC%5D%20TLS"
trojanlink5="trojan://${PASSWORD}@${DOMAIN}:443?security=tls&type=httpupgrade&host=${DOMAIN}&headerType=&path=%2Ftrojan-http&sni=${DOMAIN}&fp=&alpn=http%2F1.1#%28${USERNAME}%29%20%5BTrojan%20-%20HTTPUpgrade%5D%20TLS"
trojanlink6="trojan://${PASSWORD}@${DOMAIN}:80?security=none&type=httpupgrade&host=${DOMAIN}&headerType=&path=%2Ftrojan-http#%28${USERNAME}%29%20%5BTrojan%20-%20HTTPUpgrade%5D%20nonTLS"

# Contoh Format Openclash
echo "==--LINGVPN PRESENTS--==
TERIMA KASIH TELAH MEMILIH LAYANAN VPN LINGVPN!
LINK URL/CONFIG UNTUK USER ${USERNAME^^} DENGAN KUOTA ${limit_gb} dan MASA AKTIF ${EXPIRED} Hari
MOHON MELAKUKAN PERPANJANGAN VPN MAKSMIMAL 3 HARI SEBELUM TANGGAL EXPIRED SETIAP BULAN NYA!

DETAIL Keterangan ALPN (HARUS DI SETT!):
1.) TCP: h2
2.) WS: http/1.1
3.) GRPC: h2
4.) HTTP Upgrade: http/1.1

DETAIL Port Server (Pilih salah satu, Sesuaikan dengan bug masing masing):
1.) TLS : 443, 8443, 8880
2.) HTTP/nonTLS : 80, 2082, 2083, 3128, 8080

DETAIL AKUN lain lain, WebSocket, HTTP Upgrade, FLOW dan serviceName GRPC:

🔑 Trojan 
a.) path WS: /trojan atau /enter-your-custom-path/trojan
b.) path WS Antiads: /trojan-antiads
c.) path WS Anti ADS&PORN: /trojan-antiporn
d.) serviceName GRPC: trojan-service
e.) path HTTP Upgrade: /trojan-http
f.) path HU AntiADS: /trojan-hu-antiads
g.) path HU AntiPorn: /trojan-hu-antiporn

Config URL :

-==============================-

1.) Trojan-TCP TLS 
${trojanlink1}

2.) Trojan-WS TLS 
${trojanlink2}

3.) Trojan-WS nonTLS 
${trojanlink3}

4.) Trojan-GRPC TLS 
${trojanlink4}

5.) Trojan-HUpgrade TLS
${trojanlink5}

6.) Trojan-HUpgrade nonTLS
${trojanlink6}

-==============================-

Format Openclash : 

1.) Trojan-TCP TLS 
- name: TrojanTCP_${USERNAME}
  type: trojan
  server: ${DOMAIN}
  port: 443
  password: ${PASSWORD}
  udp: true
  sni: ${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true

2.) Trojan-WS TLS
- name: TrojanWS_${USERNAME}
  type: trojan
  server: ${DOMAIN}
  port: 443
  password: ${PASSWORD}
  udp: true
  sni: ${DOMAIN}
  alpn:
  - http/1.1
  skip-cert-verify: true
  network: ws
  ws-opts:
    path: "/trojan" # selain path ini ada /trojan-antiads atau /trojan-antiporn 

3.) Trojan-GRPC TLS
- name: TrojanGRPC_${USERNAME}
  type: trojan
  server: ${DOMAIN}
  port: 443
  password: ${PASSWORD}
  udp: true
  sni: ${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  network: grpc
  grpc-opts:
    grpc-service-name: trojan-service

4.) Trojan-HU TLS
- name: TrojanHU_${USERNAME}
  type: trojan
  server: ${DOMAIN}
  port: 443
  password: ${PASSWORD}
  client-fingerprint: chrome
  udp: true
  sni: ${DOMAIN}
  alpn:
  - http/1.1
  skip-cert-verify: true
  network: ws
  ws-opts:
   path: "/trojan-http" # selain path ini ada /trojan-hu-antiads atau /trojan-hu-antiporn 
   headers:
     Host: ${PASSWORD}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false 

SELALU PATUHI PERATURAN SERVER DAN TERIMA KASIH SUDAH MEMILIH LINGVPN 🙏

CONTACT ADMIN TELEGRAM : https://t.me/EkoLing
TELEGRAM CHANNEL : https://t.me/LingVPN
TELEGRAM GROUP : https://t.me/LingVPN_Group" > "/var/www/html/${PASSWORD}-${USERNAME}.txt"

expire=$(echo "${res_json}" | jq -r '.expire')
SUBS=$(echo "${res_json}" | jq -r '.subscription_url')

echo -e "HTML_CODE"
echo -e "<b>+++++=======-XRAY/${tunnel_name}=======+++++</b>"
echo -e ""
echo -e "Remarks: <code>${USERNAME}</code>"
echo -e "Domain: <code>${DOMAIN}</code>"
echo -e "Quota: <code>${limit_gb}</code> GB"
echo -e "Reset Quota Strategy: Bulanan"
echo -e "================================="
echo -e "🔑 Port TLS: 443, 8443, 8880"
echo -e "🔑 Port nonTLS: 80, 2082, 2083, 3128, 8080"
echo -e "================================="
echo -e "password: <code>${PASSWORD}</code>"
echo -e "================================="
echo -e "network: tcp/ws/grpc/httpupgrade"
echo -e "================================="
echo -e "path: "
echo -e "a.) WS: /trojan atau /enter-your-custom-path/trojan"
echo -e "b.) WS Antiads: /trojan-antiads"
echo -e "c.) WS Anti Ads & porn: /trojan-antiporn"
echo -e "d.) GRPC: trojan-service"
echo -e "e.) HTTP Upgrade: /trojan-http"
echo -e "f.) HTTP Upgrade AntiADS: /trojan-hu-antiads"
echo -e "g.) HTTP Upgrade AntiPorn: /trojan-hu-antiporn"
echo -e "================================="
echo -e "alpn: "
echo -e "a.) WS & HU: http/1.1"
echo -e "b.) GRPC: h2"
echo -e "c.) TCP: h2"
echo -e "================================="
echo -e "tls:"
echo -e "a.) WS & HU: true (tls), false (nontls)"
echo -e "b.) GRPC: true"
echo -e "allowInsecure: true"
echo -e "================================="
echo -e "Link config: <code>https://${DOMAIN}/${PASSWORD}-${USERNAME}.txt</code>"
echo -e "================================="
echo -e "Link Subscription : <code>https://${DOMAIN}${SUBS}</code>"
echo -e "================================="
echo -e "Masa Aktif: <code>$(date -d "@${expire}" '+%Y-%m-%d %H:%M:%S')</code>"
echo -e "<b>+++++ End of Account Details +++++</b>"
rm -r /tmp/${USERNAME}_trojan.json
