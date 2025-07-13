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

# Link VLess
vlesslink1="vless://${PASSWORD}@${DOMAIN}:443?security=tls&type=ws&host=${DOMAIN}&headerType=&path=%2Fvless&sni=&fp=&alpn=http%2F1.1#%28${USERNAME}%29%20%5BVLESS%20-%20WS%5D%20TLS"
vlesslink2="vless://${PASSWORD}@${DOMAIN}:80?security=none&type=ws&host=${DOMAIN}&headerType=&path=%2Fvless#%28${USERNAME}%29%20%5BVLESS%20-%20WS%5D%20nonTLS"
vlesslink3="vless://${PASSWORD}@${DOMAIN}:443?security=tls&type=grpc&host=${DOMAIN}&headerType=&serviceName=vless-service&sni=${DOMAIN}&fp=&alpn=h2#%28${USERNAME}%29%20%5BVLESS%20-%20GRPC%5D%20TLS"
vlesslink4="vless://${PASSWORD}@${DOMAIN}:443?security=tls&type=httpupgrade&host=${DOMAIN}&headerType=&path=%2Fvless-http&sni=&fp=&alpn=http%2F1.1#%28${USERNAME}%29%20%5BVLESS%20-%20HTTPUpgrade%5D%20TLS"
vlesslink5="vless://${PASSWORD}@${DOMAIN}:80?security=none&type=httpupgrade&host=${DOMAIN}&headerType=&path=%2Fvless-http#%28${USERNAME}%29%20%5BVLESS%20-%20HTTPUpgrade%5D%20nonTLS"

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

🔑 VLess
a.) path WS: /vless atau /enter-your-custom-path/vless
b.) path WS Antiads: /vless-antiads
c.) path WS Anti ADS&PORN: /vless-antiporn
d.) serviceName GRPC: vless-service
e.) path HTTP Upgrade: /vless-http
f.) path HTTP Upgrade AntiADS: /vless-hu-antiads
g.) path HTTP Upgrade AntiPorn: /vless-hu-antiporn

Config URL :

-==============================-

1.) VLess-WS TLS 
${vlesslink1}

2.) VLess-WS nonTLS 
${vlesslink2}

3.) VLess-GRPC TLS 
${vlesslink3}

4.) VLess-HU TLS 
${vlesslink4}

5.) VLess-HU nonTLS 
${vlesslink5}

-==============================-

Format Openclash : 

1.) VLess-WS TLS 
- name: VlessWS_${USERNAME}
  type: vless
  server: ${DOMAIN}
  port: 443
  uuid: ${PASSWORD}
  udp: true
  tls: true
  network: ws
  client-fingerprint: chrome
  servername: ${DOMAIN}
  alpn:
   - http/1.1
  skip-cert-verify: true
  ws-opts:
    path: "/vless" # selain path ini ada /vless-antiads atau /vless-antiporn 
    headers:
      Host: ${DOMAIN}

2.) VLess-WS nonTLS
- name: VlessWS_${USERNAME}
  type: vless
  server: ${DOMAIN}
  port: 80
  uuid: ${PASSWORD}
  udp: true
  tls: false
  network: ws
  client-fingerprint: chrome
  alpn:
   - http/1.1
  skip-cert-verify: true
  ws-opts:
    path: "/vless" # selain path ini ada /vless-antiads atau /vless-antiporn
    headers:
      Host: ${DOMAIN}

3.) VLess-GRPC TLS
- name: VlessGRPC_${USERNAME}
  server: ${DOMAIN}
  port: 443
  type: vless
  uuid: ${PASSWORD}
  network: grpc
  udp: true
  tls: true
  servername: example.com
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: vless-service

4.) VLess-HU TLS
- name: VLessHU_${USERNAME}
  type: vless
  server: ${DOMAIN}
  port: 443
  uuid: ${PASSWORD}
  udp: true
  tls: true
  network: ws
  client-fingerprint: chrome
  servername: ${DOMAIN}
  alpn:
  - http/1.1
  skip-cert-verify: true
  ws-opts:
   path: "/vless-http" # selain path ini ada /vless-hu-antiads atau /vless-hu-antiporn
   headers:
     Host: ${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false

5.) VLess-HU nonTLS
- name: VLessHU_${USERNAME}
  type: vless
  server: ${DOMAIN}
  port: 80
  uuid: ${PASSWORD}
  udp: true
  tls: false
  network: ws
  client-fingerprint: chrome
  alpn:
  - http/1.1
  skip-cert-verify: true
  ws-opts:
   path: "/vless-http" # selain path ini ada /vless-hu-antiads atau /vless-hu-antiporn
   headers:
     Host: ${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
-==============================-

Contoh Config inject XL Openclash : 
1.) XL VIDIO (Jika quiz.int.vidio.com tidak bisa, tinggal hapus int nya, menjadi quiz.vidio.com)
- name: VLessWS_${USERNAME}
  server: quiz.int.vidio.com
  port: 443
  type: vless
  uuid: ${PASSWORD}
  cipher: auto
  tls: true
  skip-cert-verify: true
  servername: quiz.int.vidio.com.${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /vless # selain path ini ada path /vless-antiads atau /vless-antiporn
    headers:
      Host: quiz.int.vidio.com.${DOMAIN}
  udp: true
  
- name: VLessHU_${USERNAME}
  type: vless
  server: quiz.int.vidio.com
  port: 443
  uuid: ${PASSWORD}
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
   path: "/vless-http" # selain path ini ada path /vless-hu-antiads atau /vless-hu-antiporn
   headers:
     Host: quiz.int.vidio.com.${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
- name: vlessGRPC_${USERNAME}
  type: vless
  server: quiz.int.vidio.com
  port: 443
  uuid: ${PASSWORD}
  cipher: auto
  udp: true
  network: grpc
  tls: true
  servername: quiz.int.vidio.com.${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: vless-service
    
2. XL XUTS / XCS / XUTP 
- name: vlessWS_${USERNAME}
  server: ava.game.naver.com
  port: 443
  type: vless
  uuid: ${PASSWORD}
  cipher: auto
  tls: true
  skip-cert-verify: true
  servername: ava.game.naver.com.${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /vless # selain path ini ada path /vless-antiads atau /vless-antiporn
    headers:
      Host: ava.game.naver.com.${DOMAIN}
  udp: true
  
- name: vlessHU_${USERNAME}
  type: vless
  server: ava.game.naver.com
  port: 443
  uuid: ${PASSWORD}
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
   path: "/vless-http" # selain path ini ada path /vless-hu-antiads atau /vless-hu-antiporn
   headers:
     Host: ava.game.naver.com.${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
- name: vlessGRPC_${USERNAME}
  type: vless
  server: ava.game.naver.com
  port: 443
  uuid: ${PASSWORD}
  cipher: auto
  udp: true
  network: grpc
  tls: true
  servername: ava.game.naver.com.${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: vless-service

3. XL Xtra Combo VIP Double Youtube (Jatim, Sebagian Jateng, Sulawesi, Nusa Tenggara, Papua)
- name: vlessWS_${USERNAME}
  server: 104.17.3.81
  port: 443
  type: vless
  uuid: ${PASSWORD}
  cipher: auto
  tls: true
  skip-cert-verify: true
  servername: ${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /vless # selain path ini ada path /vless-antiads atau /vless-antiporn
    headers:
      Host: ${DOMAIN}
  udp: true
  
- name: vlessHU_${USERNAME}
  type: vless
  server: 104.17.3.81
  port: 443
  uuid: ${PASSWORD}
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
   path: "/vless-http" # selain path ini ada path /vless-hu-antiads atau /vless-hu-antiporn
   headers:
     Host: ${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
- name: vlessGRPC_${USERNAME}
  type: vless
  server: 104.17.3.81
  port: 443
  uuid: ${PASSWORD}
  cipher: auto
  udp: true
  network: grpc
  tls: true
  servername: ${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: vless-service
    
4. XL Xtra Combo VIP Double Youtube (Jabodetabek, Kalimantan, Sumatra)
- name: vlessWS_${USERNAME}
  server: support.zoom.us
  port: 443
  type: vless
  uuid: ${PASSWORD}
  cipher: auto
  tls: true
  skip-cert-verify: true
  servername: support.zoom.us.${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /vless # selain path ini ada path /vless-antiads atau /vless-antiporn
    headers:
      Host: support.zoom.us.${DOMAIN}
  udp: true
  
- name: vlessHU_${USERNAME}
  type: vless
  server: support.zoom.us
  port: 443
  uuid: ${PASSWORD}
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
   path: "/vless-http" # selain path ini ada path /vless-hu-antiads atau /vless-hu-antiporn
   headers:
     Host: support.zoom.us.${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
- name: vlessGRPC_${USERNAME}
  type: vless
  server: support.zoom.us
  port: 443
  uuid: ${PASSWORD}
  cipher: auto
  udp: true
  network: grpc
  tls: true
  servername: support.zoom.us.${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: vless-service
      

SELALU PATUHI PERATURAN SERVER DAN TERIMA KASIH SUDAH MEMILIH LINGVPN 🙏

UPTIME SITE : https://uptime.lingvpn.id
BOT TELEGRAM : https://t.me/lingvpn_autopaymentbot
TELEGRAM CHANNEL : https://t.me/LingVPN
TELEGRAM GROUP : https://t.me/LingVPN_Group" > "/var/www/html/${PASSWORD}-${USERNAME}.txt"
