#!/bin/bash
USERNAME="$1"
PASSWORD="$2"
EXPIRED="$3"
DOMAIN=$(cat /root/domain)

limit_gb="1024"
current_date=$(date "+%Y-%m-%d %H:%M:%S")

if [[ -z "$USERNAME" || -z "$PASSWORD" || -z "$EXPIRED" ]]; then
    echo "Usage: $0 <username> <password> <expired_days>"
    exit 1
fi

# Link VMess
ws1=`cat<<EOF
      {
      "v": "2",
      "ps": "(${USERNAME}) [VMess - WS] TLS",
      "add": "${DOMAIN}",
      "port": "443",
      "id": "${PASSWORD}",
      "aid": "0",
      "net": "ws",
      "path": "/vmess",
      "type": "none",
      "host": "",
      "tls": "tls"
}
EOF`
ws2=`cat<<EOF
      {
      "v": "2",
      "ps": "(${USERNAME}) [VMess - WS] nonTLS",
      "add": "${DOMAIN}",
      "port": "80",
      "id": "${PASSWORD}",
      "aid": "0",
      "net": "ws",
      "path": "/vmess",
      "type": "none",
      "host": "",
      "tls": "none"
}
EOF`
grpc=`cat<<EOF
 {
      "v": "2",
      "ps": "(${USERNAME}) [VMess - GRPC] TLS",
      "add": "${DOMAIN}",
      "port": "443",
      "id": "${PASSWORD}",
      "aid": "0",
      "net": "grpc",
      "path": "vmess-service",
      "type": "gun",
      "host": "",
      "tls": "tls"
}
EOF`
hutls=`cat<<EOF
 {
      "v": "2",
      "ps": "(${USERNAME}) [VMess - HTTP Upgrade] TLS",
      "add": "${DOMAIN}",
      "port": "443",
      "id": "${PASSWORD}",
      "aid": "0",
      "net": "httpugrade",
      "path": "/vmess-http",
      "type": "none",
      "host": "",
      "tls": "tls"
}
EOF`
huntls=`cat<<EOF
 {
      "v": "2",
      "ps": "(${USERNAME}) [VMess - HTTP Upgrade] nTLS",
      "add": "${DOMAIN}",
      "port": "80",
      "id": "${PASSWORD}",
      "aid": "0",
      "net": "httpugrade",
      "path": "/vmess-http",
      "type": "none",
      "host": "",
      "tls": "none"
}
EOF`
vmesslink1="vmess://$(echo $tcp1 | base64 -w 0)"
vmesslink2="vmess://$(echo $tcp2 | base64 -w 0)"
vmesslink3="vmess://$(echo $ws1 | base64 -w 0)"
vmesslink4="vmess://$(echo $ws2 | base64 -w 0)"
vmesslink5="vmess://$(echo $grpc | base64 -w 0)"
vmesslink6="vmess://$(echo $hutls | base64 -w 0)"
vmesslink7="vmess://$(echo $huntls | base64 -w 0)"

# Contoh Format Openclash
echo "==--LINGVPN PRESENTS--==
TERIMA KASIH TELAH MEMILIH LAYANAN VPN LINGVPN!
LINK URL/CONFIG UNTUK USERNAME ${USERNAME^^} DENGAN KUOTA ${limit_gb}GB dan MASA AKTIF ${EXPIRED}
MOHON MELAKUKAN PERPANJANGAN VPN MAKSMIMAL 3 HARI SEBELUM TANGGAL EXPIRED SETIAP BULAN NYA!

DETAIL Keterangan ALPN (HARUS DI SETT!):
1.) WS/HU: http/1.1
2.) GRPC: h2

DETAIL Port Server (Pilih salah satu, Sesuaikan dengan bug masing masing):
1.) TLS : 443, 8443, 8880
2.) HTTP/nonTLS : 80, 2082, 2083, 3128, 8080

DETAIL AKUN lain lain, WebSocket, dan serviceName GRPC:

🔑 VMess
a.) path WS: /vmess atau /enter-your-custom-path/vmess
b.) path WS Antiads: /vmess-antiads
c.) path WS Anti ADS&PORN: /vmess-antiporn
d.) serviceName GRPC: vmess-service
e.) path HTTP Upgrade: /vmess-http
f.) path HTTP Upgrade AntiADS: /vmess-hu-antiads 
g.) path HTTP Upgrade AntiPorn: /vmess-hu-antiporn 

Config URL :

-==============================-

1.) VMess-WS TLS
${vmesslink3}

2.) VMess-WS nonTLS
${vmesslink4}

3.) VMess-GRPC TLS 
${vmesslink3}

4.) VMess-HU TLS
${vmesslink6}

5.) VMess-HU nonTLS
${vmesslink7}

-==============================-

Format Openclash : 

1.) VMess-WS TLS
- name: VMessWS_${USERNAME}
  server: ${DOMAIN}
  port: 443
  type: vmess
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  tls: true
  skip-cert-verify: true
  servername: ${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /vmess # selain path ini ada path /vmess-antiads atau /vmess-antiporn
    headers:
      Host: ${DOMAIN}
  udp: true

2.) VMess-WS nonTLS
- name: VMessWS_${USERNAME}
  server: ${DOMAIN}
  port: 80
  type: vmess
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  tls: false
  skip-cert-verify: true
  servername: ${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /vmess # selain path ini ada path /vmess-antiads atau /vmess-antiporn
    headers:
      Host: ${DOMAIN}
  udp: true

3.) VMess-GRPC TLS 
- name: VMessGRPC_${USERNAME}
  type: vmess
  server: ${DOMAIN}
  port: 443
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  udp: true
  network: grpc
  tls: true
  servername: ${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: vmess-service

4.) VMess-HU TLS
- name: VMessHU_${USERNAME}
  type: vmess
  server: ${DOMAIN}
  port: 443
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  client-fingerprint: chrome
  skip-cert-verify: true
  servername: ${DOMAIN}
  alpn:
  - http/1.1
  network: ws
  ws-opts:
   path: "/vmess-http" # selain path ini ada path /vmess-hu-antiads atau /vmess-hu-antiporn
   headers:
     Host: ${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false

5.) VMess-HU nonTLS
- name: VMessHU_${USERNAME}
  type: vmess
  server: ${DOMAIN}
  port: 80
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  udp: true
  tls: false
  client-fingerprint: chrome
  skip-cert-verify: true
  alpn:
  - http/1.1
  network: ws
  ws-opts:
   path: "/vmess-http" # selain path ini ada path /vmess-hu-antiads atau /vmess-hu-antiporn
   headers:
     Host: ${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
-==============================-

Contoh Config inject XL Openclash : 
1.) XL VIDIO (Jika quiz.int.vidio.com tidak bisa, tinggal hapus int nya, menjadi quiz.vidio.com)
- name: VMessWS_${USERNAME}
  server: quiz.int.vidio.com
  port: 443
  type: vmess
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  tls: true
  skip-cert-verify: true
  servername: quiz.int.vidio.com.${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /vmess # selain path ini ada path /vmess-antiads atau /vmess-antiporn
    headers:
      Host: quiz.int.vidio.com.${DOMAIN}
  udp: true
  
- name: VMessHU_${USERNAME}
  type: vmess
  server: quiz.int.vidio.com
  port: 443
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  client-fingerprint: chrome
  skip-cert-verify: true
  servername: quiz.int.vidio.com.${DOMAIN}
  alpn:
  - http/1.1
  network: ws
  ws-opts:
   path: "/vmess-http" # selain path ini ada path /vmess-hu-antiads atau /vmess-hu-antiporn
   headers:
     Host: quiz.int.vidio.com.${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
- name: VMessGRPC_${USERNAME}
  type: vmess
  server: quiz.int.vidio.com
  port: 443
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  udp: true
  network: grpc
  tls: true
  servername: quiz.int.vidio.com.${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: vmess-service
    
2. XL XUTS / XCS / XUTP 
- name: VMessWS_${USERNAME}
  server: ava.game.naver.com
  port: 443
  type: vmess
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  tls: true
  skip-cert-verify: true
  servername: ava.game.naver.com.${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /vmess # selain path ini ada path /vmess-antiads atau /vmess-antiporn
    headers:
      Host: ava.game.naver.com.${DOMAIN}
  udp: true
  
- name: VMessHU_${USERNAME}
  type: vmess
  server: ava.game.naver.com
  port: 443
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  client-fingerprint: chrome
  skip-cert-verify: true
  servername: ava.game.naver.com.${DOMAIN}
  alpn:
  - http/1.1
  network: ws
  ws-opts:
   path: "/vmess-http" # selain path ini ada path /vmess-hu-antiads atau /vmess-hu-antiporn
   headers:
     Host: ava.game.naver.com.${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
- name: VMessGRPC_${USERNAME}
  type: vmess
  server: ava.game.naver.com
  port: 443
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  udp: true
  network: grpc
  tls: true
  servername: ava.game.naver.com.${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: vmess-service

3. XL Xtra Combo VIP Double Youtube (Jatim, Sebagian Jateng, Sulawesi, Nusa Tenggara, Papua)
- name: VMessWS_${USERNAME}
  server: 104.17.3.81
  port: 443
  type: vmess
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  tls: true
  skip-cert-verify: true
  servername: ${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /vmess # selain path ini ada path /vmess-antiads atau /vmess-antiporn
    headers:
      Host: ${DOMAIN}
  udp: true
  
- name: VMessHU_${USERNAME}
  type: vmess
  server: 104.17.3.81
  port: 443
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  client-fingerprint: chrome
  skip-cert-verify: true
  servername: ${DOMAIN}
  alpn:
  - http/1.1
  network: ws
  ws-opts:
   path: "/vmess-http" # selain path ini ada path /vmess-hu-antiads atau /vmess-hu-antiporn
   headers:
     Host: ${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
- name: VMessGRPC_${USERNAME}
  type: vmess
  server: 104.17.3.81
  port: 443
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  udp: true
  network: grpc
  tls: true
  servername: ${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: vmess-service
    
4. XL Xtra Combo VIP Double Youtube (Jabodetabek, Kalimantan, Sumatra)
- name: VMessWS_${USERNAME}
  server: support.zoom.us
  port: 443
  type: vmess
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  tls: true
  skip-cert-verify: true
  servername: support.zoom.us.${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /vmess # selain path ini ada path /vmess-antiads atau /vmess-antiporn
    headers:
      Host: support.zoom.us.${DOMAIN}
  udp: true
  
- name: VMessHU_${USERNAME}
  type: vmess
  server: support.zoom.us
  port: 443
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  client-fingerprint: chrome
  skip-cert-verify: true
  servername: support.zoom.us.${DOMAIN}
  alpn:
  - http/1.1
  network: ws
  ws-opts:
   path: "/vmess-http" # selain path ini ada path /vmess-hu-antiads atau /vmess-hu-antiporn
   headers:
     Host: support.zoom.us.${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
- name: VMessGRPC_${USERNAME}
  type: vmess
  server: support.zoom.us
  port: 443
  uuid: ${PASSWORD}
  alterId: 0
  cipher: auto
  udp: true
  network: grpc
  tls: true
  servername: support.zoom.us.${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: vmess-service
      

SELALU PATUHI PERATURAN SERVER DAN TERIMA KASIH SUDAH MEMILIH LINGVPN 🙏

UPTIME SITE : https://uptime.lingvpn.id
BOT TELEGRAM : https://t.me/lingvpn_autopaymentbot
TELEGRAM CHANNEL : https://t.me/LingVPN
TELEGRAM GROUP : https://t.me/LingVPN_Group" > "/var/www/html/${PASSWORD}-${USERNAME}.txt"
