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

# Link Trojan
trojanlink1="trojan://${PASSWORD}@${DOMAIN}:443?security=tls&type=ws&host=${DOMAIN}&headerType=&path=%2Ftrojan&sni=${DOMAIN}&fp=&alpn=http%2F1.1#%28${USERNAME}%29%20%5BTrojan%20-%20WS%5D%20TLS"
trojanlink2="trojan://${PASSWORD}@${DOMAIN}:80?security=none&type=ws&host=${DOMAIN}&headerType=&path=%2Ftrojan#%28${USERNAME}%29%20%5BTrojan%20-%20WS%5D%20nonTLS"
trojanlink3="trojan://${PASSWORD}@${DOMAIN}:443?security=tls&type=grpc&host=&headerType=&serviceName=trojan-service&sni=${DOMAIN}&fp=&alpn=h2#%28${USERNAME}%29%20%5BTrojan%20-%20GRPC%5D%20TLS"
trojanlink4="trojan://${PASSWORD}@${DOMAIN}:443?security=tls&type=httpupgrade&host=${DOMAIN}&headerType=&path=%2Ftrojan-http&sni=${DOMAIN}&fp=&alpn=http%2F1.1#%28${USERNAME}%29%20%5BTrojan%20-%20HTTPUpgrade%5D%20TLS"
trojanlink5="trojan://${PASSWORD}@${DOMAIN}:80?security=none&type=httpupgrade&host=${DOMAIN}&headerType=&path=%2Ftrojan-http#%28${USERNAME}%29%20%5BTrojan%20-%20HTTPUpgrade%5D%20nonTLS"

# Contoh Format Openclash
echo "==--LINGVPN PRESENTS--==
TERIMA KASIH TELAH MEMILIH LAYANAN VPN LINGVPN!
LINK URL/CONFIG UNTUK USER ${USERNAME^^} DENGAN KUOTA ${quota_text} dan MASA AKTIF ${EXPIRED} HARI
MOHON MELAKUKAN PERPANJANGAN VPN MAKSMIMAL 3 HARI SEBELUM TANGGAL EXPIRED SETIAP BULAN NYA!

DETAIL Keterangan ALPN (HARUS DI SETT!):
1.) WS: http/1.1
2.) GRPC: h2
3.) HTTP Upgrade: http/1.1

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

1.) Trojan-WS TLS 
${trojanlink1}

2.) Trojan-WS nonTLS 
${trojanlink2}

3.) Trojan-GRPC TLS 
${trojanlink3}

4.) Trojan-HUpgrade TLS
${trojanlink4}

5.) Trojan-HUpgrade nonTLS
${trojanlink5}

-==============================-

Format Openclash : 

1.) Trojan-WS TLS
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

2.) Trojan-GRPC TLS
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

3.) Trojan-HU TLS
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
     Host: ${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false 

4.) Trojan-TCP TLS
- name: TrojanTCP_${USERNAME}
  type: trojan
  server: IPADDRESS
  port: 443
  password: ${PASSWORD}
  udp: true
  sni: ${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  
-==============================-

Contoh Config inject XL Openclash : 
1.) XL VIDIO (Jika quiz.int.vidio.com tidak bisa, tinggal hapus int nya, menjadi quiz.vidio.com)
- name: TrojanWS_${USERNAME}
  server: quiz.int.vidio.com
  port: 443
  type: trojan
  password: ${PASSWORD}
  skip-cert-verify: true
  sni: quiz.int.vidio.com.${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /trojan # selain path ini ada path /trojan-antiads atau /trojan-antiporn
    headers:
      Host: quiz.int.vidio.com.${DOMAIN}
  udp: true
  
- name: TrojanHU_${USERNAME}
  type: trojan
  server: quiz.int.vidio.com
  port: 443
  password: ${PASSWORD}
  udp: true
  client-fingerprint: chrome
  skip-cert-verify: true
  sni: quiz.int.vidio.com.${DOMAIN}
  alpn:
  - http/1.1
  network: ws
  ws-opts:
   path: "/trojan-http" # selain path ini ada path /trojan-hu-antiads atau /trojan-hu-antiporn
   headers:
     Host: quiz.int.vidio.com.${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
- name: TrojanGRPC_${USERNAME}
  type: trojan
  server: quiz.int.vidio.com
  port: 443
  password: ${PASSWORD}
  udp: true
  network: grpc
  sni: quiz.int.vidio.com.${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: trojan-service
    
2. XL XUTS / XCS / XUTP 
- name: TrojanWS_${USERNAME}
  server: ava.game.naver.com
  port: 443
  type: trojan
  password: ${PASSWORD}
  skip-cert-verify: true
  sni: ava.game.naver.com.${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /trojan # selain path ini ada path /trojan-antiads atau /trojan-antiporn
    headers:
      Host: ava.game.naver.com.${DOMAIN}
  udp: true
  
- name: TrojanHU_${USERNAME}
  type: trojan
  server: ava.game.naver.com
  port: 443
  password: ${PASSWORD}
  udp: true
  client-fingerprint: chrome
  skip-cert-verify: true
  sni: ava.game.naver.com.${DOMAIN}
  alpn:
  - http/1.1
  network: ws
  ws-opts:
   path: "/trojan-http" # selain path ini ada path /trojan-hu-antiads atau /trojan-hu-antiporn
   headers:
     Host: ava.game.naver.com.${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
- name: TrojanGRPC_${USERNAME}
  type: trojan
  server: ava.game.naver.com
  port: 443
  password: ${PASSWORD}
  udp: true
  network: grpc
  sni: ava.game.naver.com.${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: trojan-service

3. XL Xtra Combo VIP Double Youtube (Jatim, Sebagian Jateng, Sulawesi, Nusa Tenggara, Papua)
- name: TrojanWS_${USERNAME}
  server: 104.17.3.81
  port: 443
  type: trojan
  password: ${PASSWORD}
  skip-cert-verify: true
  sni: ${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /trojan # selain path ini ada path /trojan-antiads atau /trojan-antiporn
    headers:
      Host: ${DOMAIN}
  udp: true
  
- name: TrojanHU_${USERNAME}
  type: trojan
  server: 104.17.3.81
  port: 443
  password: ${PASSWORD}
  udp: true
  client-fingerprint: chrome
  skip-cert-verify: true
  sni: ${DOMAIN}
  alpn:
  - http/1.1
  network: ws
  ws-opts:
   path: "/trojan-http" # selain path ini ada path /trojan-hu-antiads atau /trojan-hu-antiporn
   headers:
     Host: ${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
- name: TrojanGRPC_${USERNAME}
  type: trojan
  server: 104.17.3.81
  port: 443
  password: ${PASSWORD}
  udp: true
  network: grpc
  tls: true
  sni: ${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: trojan-service
    
4. XL Xtra Combo VIP Double Youtube (Jabodetabek, Kalimantan, Sumatra)
- name: TrojanWS_${USERNAME}
  server: support.zoom.us
  port: 443
  type: trojan
  password: ${PASSWORD}
  skip-cert-verify: true
  sni: support.zoom.us.${DOMAIN}
  alpn:
   - http/1.1
  network: ws
  ws-opts:
    path: /trojan # selain path ini ada path /trojan-antiads atau /trojan-antiporn
    headers:
      Host: support.zoom.us.${DOMAIN}
  udp: true
  
- name: TrojanHU_${USERNAME}
  type: trojan
  server: support.zoom.us
  port: 443
  password: ${PASSWORD}
  udp: true
  client-fingerprint: chrome
  skip-cert-verify: true
  sni: support.zoom.us.${DOMAIN}
  alpn:
  - http/1.1
  network: ws
  ws-opts:
   path: "/trojan-http" # selain path ini ada path /trojan-hu-antiads atau /trojan-hu-antiporn
   headers:
     Host: support.zoom.us.${DOMAIN}
   v2ray-http-upgrade: true
   v2ray-http-upgrade-fast-open: false
   
- name: TrojanGRPC_${USERNAME}
  type: trojan
  server: support.zoom.us
  port: 443
  password: ${PASSWORD}
  udp: true
  network: grpc
  tls: true
  servername: support.zoom.us.${DOMAIN}
  alpn:
   - h2
  skip-cert-verify: true
  grpc-opts:
    grpc-service-name: trojan-service
      
SELALU PATUHI PERATURAN SERVER DAN TERIMA KASIH SUDAH MEMILIH LINGVPN 🙏

UPTIME SITE : https://uptime.lingvpn.id
BOT TELEGRAM : https://t.me/lingvpn_autopaymentbot
TELEGRAM CHANNEL : https://t.me/LingVPN
TELEGRAM GROUP : https://t.me/LingVPN_Group" > "/var/www/html/${PASSWORD}-${USERNAME}.txt"
