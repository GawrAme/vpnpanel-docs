#!/usr/bin/env bash
# Hapus (purge) akun Shadowsocks 2022 + bersihkan file client
# Output ke bot dalam format HTML_CODE

set -euo pipefail

# === Argumen ===
USERNAME="${1:-}"
PASSWORD="${2:-}"
EXPIRED="${3:-}"              # tidak terpakai untuk delete, tetap diterima biar kompatibel
TRANSPORT="${4:-}"            # tidak terpakai
EXPIRED_TIMESTAMP_BOT="${5:-}"

if [[ -z "$USERNAME" || -z "$PASSWORD" || -z "$EXPIRED" ]]; then
  echo "Usage: $0 <username> <password> <expired_days> [transport] [expired_timestamp_bot]"
  exit 1
fi

# ===== Konfigurasi (bisa di-override via ENV) =====
XRAY_DB="${XRAY_DB:-/usr/local/etc/xray/database.json}"
CLIENT_DIR="${CLIENT_DIR:-/var/www/html}"
PRIMARY_TAG="${PRIMARY_TAG:-SSWS}"  # hanya untuk tampilan domain/psk jika perlu nanti

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Need: $1"; exit 1; }; }
need jq
need ss2022ctl

[ -f "$XRAY_DB" ] || { echo "DB not found: $XRAY_DB"; exit 1; }

get_domain(){
  if [ -f /root/domain ]; then awk 'NF{print; exit}' /root/domain
  else echo "example.com"; fi
}
wib_now(){ TZ=Asia/Jakarta date +"%Y-%m-%d %H:%M:%S WIB"; }

DOMAIN="$(get_domain)"

# ===== Cek ada di DB? =====
USER_IN_DB=0
if jq -e --arg e "$USERNAME" '.users[$e]' "$XRAY_DB" >/dev/null 2>&1; then
  USER_IN_DB=1
fi

# ===== Purge (runtime & DB) =====
PURGE_MSG=""
PURGE_OK=1
if ss2022ctl purge "$USERNAME" >/dev/null 2>&1; then
  PURGE_MSG="Berhasil purge (runtime & DB)."
else
  PURGE_OK=0
  PURGE_MSG="Peringatan: purge gagal atau user tidak ada di runtime/DB."
fi

# ===== Bersihkan file client di /var/www/html =====
FILES_REMOVED=0
REMOVED_LIST=""

if [ -d "$CLIENT_DIR" ]; then
  # pola file yang pernah kita buat:
  #   <uuid>-USERNAME.txt
  #   <uuid>-USERNAME.json
  #   <uuid>-USERNAME-<TAG>.json
  # (kalau ada variasi lain, tambahkan pola di bawah)
  mapfile -t CANDIDATES < <(
    find "$CLIENT_DIR" -maxdepth 1 -type f \
      \( -name "*-${USERNAME}.txt" -o -name "*-${USERNAME}.json" -o -name "*-${USERNAME}-*.json" \) \
      -printf "%p\n" 2>/dev/null || true
  )

  if [ "${#CANDIDATES[@]}" -gt 0 ]; then
    FILES_REMOVED="${#CANDIDATES[@]}"
    # simpan list pendek (maks 5) untuk info
    for i in "${!CANDIDATES[@]}"; do
      [ "$i" -ge 5 ] && break
      REMOVED_LIST+=$(printf -- "• %s\n" "$(basename "${CANDIDATES[$i]}")")
    done
    # hapus file
    rm -f "${CANDIDATES[@]}" || true
  fi
fi

# ===== Tampilkan hasil (HTML_CODE) =====
echo -e "HTML_CODE"
echo -e "-=================================-"
echo -e "<b>+++++ ShadowSocks-WS Account Deleted +++++</b>"
echo -e "Username: <code>${USERNAME}</code>"
echo -e "Domain  : <code>${DOMAIN}</code>"
if [ "$USER_IN_DB" -eq 1 ]; then
  echo -e "Status  : ${PURGE_MSG}"
else
  echo -e "Status  : User tidak ditemukan di DB. ${PURGE_MSG}"
fi

if [ "$FILES_REMOVED" -gt 0 ]; then
  echo -e "Files dihapus: ${FILES_REMOVED}"
  echo -e "<i>Contoh file:</i>"
  # bungkus list file dalam monospaced biar rapi
  echo -e "<code>"
  printf "%s" "$REMOVED_LIST"
  echo -e "</code>"
else
  echo -e "Files dihapus: 0 (tidak ada file terasosiasi di ${CLIENT_DIR})"
fi

echo -e "Waktu   : $(wib_now)"
echo -e "<b>+++++ End of Report +++++</b>"
echo -e "-=================================-"
