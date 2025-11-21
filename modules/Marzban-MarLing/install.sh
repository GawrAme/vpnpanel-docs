#!/bin/bash

source_code="GawrAme/vpnpanel-docs"
module_name="Marzban-MarLing"
bin_dir="/etc/gegevps/bin"

if [[ "$EUID" -ne 0 ]]; then
    echo "The script must be run as root." >&2
    exit 1
fi

API_USERNAME="${1}"
API_PASSWORD="${2}"
API_PORT="${3}"
TELEGRAM_BOT_TOKEN="${4}"
TELEGRAM_CHAT_ID="${5}"

if [[ -z "${API_USERNAME}" || -z "${API_PASSWORD}" || -z "${API_PORT}"|| -z "${TELEGRAM_BOT_TOKEN}"|| -z "${TELEGRAM_CHAT_ID}" ]]; then
    echo "Usage: $0 <api_username> <api_password> <api_port> <telegram_bot_token> <telegram_chat_id>"
    exit 1
fi

function link_gen(){
    dl_link="https://raw.githubusercontent.com/${source_code}/refs/heads/main/modules/${module_name}/telegram-${1}-${2}.sh"
    echo "${dl_link}"
}

function install_sh(){
    full_link="$(link_gen ${1} ${2})"
    file_name="$(echo "${full_link}" | rev | cut -d'/' -f 1 | rev)"
    wget -qO- "${full_link}" | sed 's/YOUR_API_USERNAME/'"${API_USERNAME}"'/g; s/YOUR_API_PASSWORD/'"${API_PASSWORD}"'/g; s/YOUR_API_PORT/'"${API_PORT}"'/g' > "${bin_dir}/${file_name}"
    chmod +x "${bin_dir}/${file_name}"
}

function tunnels_list(){
    echo "
        sshovpn
        vmess
        vless
        trojan
        ssocks
        vmessqb
        vlessqb
        trojanqb
    " | sed 's/^[ \t]*//g;/^$/d'
}

function actions_list(){
    echo "
        create
        extend
        delete
        trial
    " | sed 's/^[ \t]*//g;/^$/d'
}

tunnels_list | while read -r tunnel; do
    if [[ ! -d "${bin_dir}" ]]; then
        mkdir -p "${bin_dir}"
    fi
    actions_list | while read -r action; do
        install_sh "${tunnel}" "${action}"
    done
done
wget -q -O /usr/bin/addconfig-vmess.sh "https://raw.githubusercontent.com/GawrAme/vpnpanel-docs/refs/heads/main/modules/Marzban-MarLing/addconfig-vmess.sh" && chmod +x /usr/bin/addconfig-vmess.sh
wget -q -O /usr/bin/addconfig-vless.sh "https://raw.githubusercontent.com/GawrAme/vpnpanel-docs/refs/heads/main/modules/Marzban-MarLing/addconfig-vless.sh" && chmod +x /usr/bin/addconfig-vless.sh
wget -q -O /usr/bin/addconfig-trojan.sh "https://raw.githubusercontent.com/GawrAme/vpnpanel-docs/refs/heads/main/modules/Marzban-MarLing/addconfig-trojan.sh" && chmod +x /usr/bin/addconfig-trojan.sh
echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN" > "${bin_dir}/telegram_config.conf"
echo "TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID" >> "${bin_dir}/telegram_config.conf"
echo "Module ${module_name} installed successfully."
chmod 555 ${bin_dir}/*sh
