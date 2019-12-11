#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#
# Auto prepare v2ray environment
#
# Copyright (C) 2019-2020 Yuk1n0
#
# System Required:  CentOS 7
#
# Reference URL:
# https://github.com/v2ray
# https://github.com/v2ray/v2ray-core

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
kernel_version="4.14.158"

[[ $EUID -ne 0 ]] && echo -e "[${red}Warning${plain}] This script must be run as root!" && exit 0

disable_selinux() {
    echo -e "[${yellow}Step${plain}] This step will make SELinux disabled (if SELinux existed)..."
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
    echo
}

check_sys() {
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''

    if [[ -f /etc/redhat-release ]]; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "debian|raspbian" /etc/issue; then
        release="debian"
        systemPackage="apt"
    elif grep -Eqi "ubuntu" /etc/issue; then
        release="ubuntu"
        systemPackage="apt"
    elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "debian|raspbian" /proc/version; then
        release="debian"
        systemPackage="apt"
    elif grep -Eqi "ubuntu" /proc/version; then
        release="ubuntu"
        systemPackage="apt"
    elif grep -Eqi "centos|red hat|redhat" /proc/version; then
        release="centos"
        systemPackage="yum"
    fi

    if [[ "${checkType}" == "sysRelease" ]]; then
        if [ "${value}" == "${release}" ]; then
            return 0
        else
            return 1
        fi
    elif [[ "${checkType}" == "packageManager" ]]; then
        if [ "${value}" == "${systemPackage}" ]; then
            return 0
        else
            return 1
        fi
    fi
}

getversion() {
    if [[ -s /etc/redhat-release ]]; then
        grep -oE "[0-9.]+" /etc/redhat-release
    else
        grep -oE "[0-9.]+" /etc/issue
    fi
}

centosversion() {
    if check_sys sysRelease centos; then
        local code=$1
        local version="$(getversion)"
        local main_ver=${version%%.*}
        if [ "$main_ver" == "$code" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

get_char() {
    SAVEDSTTY=$(stty -g)
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2>/dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

error_detect_depends() {
    local command=$1
    local depend=$(echo "${command}" | awk '{print $4}')
    echo -e "[${green}Info${plain}] Starting to install package ${depend}"
    ${command} >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "[${red}Error${plain}] Failed to install ${red}${depend}${plain}"
        exit 1
    fi
}

config_firewall() {
    echo -e "[${yellow}Step${plain}] This step will config your firewall..."
    systemctl status firewalld >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        default_zone=$(firewall-cmd --get-default-zone)
        firewall-cmd --permanent --zone=${default_zone} --add-service=http
        firewall-cmd --permanent --zone=${default_zone} --add-port=443/tcp
        firewall-cmd --permanent --zone=${default_zone} --add-port=443/udp
        firewall-cmd --reload
    else
        echo -e "[${yellow}Warning${plain}] firewalld looks like not running or not installed, please enable port 80/443 manually if necessary."
    fi
    echo
}

install_epel() {
    echo -e "[${yellow}Step${plain}] This step will enable EPEL repository (centos) and update your system again..."
    echo -e "[${green}Info${plain}] Checking the EPEL repository..."
    if [ ! -f /etc/yum.repos.d/epel.repo ]; then
        yum install -y epel-release >/dev/null 2>&1
    fi
    [ ! -f /etc/yum.repos.d/epel.repo ] && echo -e "[${red}Error${plain}] Install EPEL repository failed, please check it." && exit 1
    [ ! "$(command -v yum-config-manager)" ] && yum install -y yum-utils >/dev/null 2>&1
    [ x"$(yum-config-manager epel | grep -w enabled | awk '{print $3}')" != x"True" ] && yum-config-manager --enable epel >/dev/null 2>&1
    yum -y update
    echo -e "[${green}Info${plain}] Checking the EPEL repository complete..."
    echo
}

install_useful_package() {
    echo -e "[${yellow}Step${plain}] This step will install some packages that installation needed..."
    yum_depends=(
        ufw certbot bind-utils traceroute bash-completion
    )
    for depend in ${yum_depends[@]}; do
        error_detect_depends "yum -y install ${depend}"
    done
    echo
}

disable_unuseful_services() {
    echo -e "[${yellow}Step${plain}] This step will disable some unuseful autostart services..."
    systemctl stop kdump
    systemctl disable kdump
    systemctl stop NetworkManager-wait-online
    systemctl disable NetworkManager-wait-online
    systemctl stop postfix
    systemctl disable postfix
    echo
}

prepare_domain() {
    echo -e "[${yellow}Step${plain}] This step will get a cert for your OWN domain..."
    echo -e "[${yellow}Warning${plain}] To use v2ray-websocket-tls, make sure you have at least ONE domain ,or you can buy one at https://www.godaddy.com"
    read -p "Please enter your own domain: " domain
    str=$(echo $domain | gawk '/^([a-zA-Z0-9_\-\.]+)\.([a-zA-Z]{2,5})$/{print $0}')
    while [ ! -n "${str}" ]; do
        echo -e "[${red}Error${plain}] Invalid domain, Please try again! "
        read -p "Please enter your own domain: " domain
        str=$(echo $domain | gawk '/^([a-zA-Z0-9_\-\.]+)\.([a-zA-Z]{2,5})$/{print $0}')
    done
    echo -e "Your domain = ${domain}"
    get_cert
    echo
}

get_cert() {
    if [ -f /etc/letsencrypt/live/$domain/fullchain.pem ]; then
        echo -e "[${green}Step${plain}] Cert already got, skip..."
    else
        certbot certonly --cert-name $domain -d $domain -d www.$domain --standalone --agree-tos --register-unsafely-without-email
        systemctl enable certbot-renew.timer
        systemctl start certbot-renew.timer
        if [ ! -f /etc/letsencrypt/live/$domain/fullchain.pem ]; then
            echo -e "[${red}Error${plain}] Failed to get a cert! "
            exit 1
        fi
    fi
}

install_bbrplus() {
    echo -e "[${yellow}Step${plain}] This step will install bbrplus kernel to your host..."

    echo -e "[${green}Info${plain}] Updating your system ,please wait a few minutes..."
    yum -y update
    echo -e "[${green}Info${plain}] Updating system complete..."

    echo -e "[${green}Info${plain}] Checking lotServer..."
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    if [[ -e /appex/bin/lotServer.sh ]]; then
        echo -e "[${green}Info${plain}] Uninstalling lotServer..."
        wget --no-check-certificate -O appex.sh https://raw.githubusercontent.com/MoeClub/lotServer/master/Install.sh && chmod +x appex.sh && bash appex.sh uninstall
        rm -f appex.sh
        echo -e "[${green}Info${plain}] Uninstalling lotServer complete..."
    fi

    echo -e "[${green}Info${plain}] Downloading bbrplus Kernel..."
    wget --no-check-certificate https://github.com/Yuk1n0/Shadowsocks-Install/raw/master/Centos7/x86_64/kernel-${kernel_version}.rpm
    wget --no-check-certificate https://github.com/Yuk1n0/Shadowsocks-Install/raw/master/Centos7/x86_64/kernel-headers-${kernel_version}.rpm
    echo -e "[${green}Info${plain}] Installing bbrplus Kernel..."
    yum install -y kernel-headers-${kernel_version}.rpm
    yum install -y kernel-${kernel_version}.rpm
    echo -e "[${green}Info${plain}] Installing bbrplus kernel complete..."

    #Check
    list="$(awk -F\' '$1=="menuentry " {print i++ " : " $2}' /etc/grub2.cfg)"
    target="CentOS Linux (${kernel_version})"
    result=$(echo $list | grep "${target}")
    if [[ "$result" == "" ]]; then
        echo -e "[${red}Error${plain}] Failed to install bbrplus..."
        exit 1
    fi
    echo -e "[${green}Info${plain}] Checking lotServer complete..."

    echo -e "[${green}Info${plain}] Switching to new bbrplus-kernel..."
    grub2-set-default 'CentOS Linux (${kernel_version}) 7 (Core)'
    echo -e "[${green}Info${plain}] Enable bbr module..."
    echo "net.core.default_qdisc=fq" >>/etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbrplus" >>/etc/sysctl.conf
    rm -f kernel-${kernel_version}.rpm
    rm -f kernel-headers-${kernel_version}.rpm
}

install_check() {
    if check_sys packageManager yum; then
        if centosversion 5 || centosversion 6; then
            return 1
        fi
        return 0
    else
        return 1
    fi
}

install_main() {
    if ! install_check; then
        echo -e "[${red}Error${plain}] Your OS is not supported to run it! Please change to CentOS 7 and try again"
        exit 1
    fi
    echo -e "[${green}Info${plain}] Press any key to start...or Press Ctrl+C to cancel"
    char=$(get_char)
    echo
    if [[ "$(uname -r)" == "${kernel_version}" ]]; then
        echo "bbrplus kernel has been installed..."
    else
        install_bbrplus
    fi
    install_epel
    disable_selinux
    install_useful_package
    disable_unuseful_services
    config_firewall
    prepare_domain
    echo "alias netports='netstat -anp | grep -E \"Recv-Q|tcp|udp|raw\"'" >>/root/.bashrc

    while true; do
        read -p "prepare installation completed，reboot server now ? [Y/n] :" answer
        [ -z "${answer}" ] && answer="y"
        if [[ $answer == [Yy] ]]; then
            echo -e "[${green}Info${plain}] Rebooting..."
            break
        else
            echo -e "[${red}Error${plain}] Please enter [Y/n] !"
            echo
        fi
    done
    reboot
}

install_main
