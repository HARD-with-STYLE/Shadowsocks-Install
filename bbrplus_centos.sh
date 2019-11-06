#!/usr/bin/env bash
# Original Author:  cx9208   Licensed: GPLv3
# Thanks:
# @cx9208  <https://github.com/cx9208>

kernel_version="4.14.129-bbrplus"
if [[ ! -f /etc/redhat-release ]]; then
	echo -e "Only support centos..."
	exit 0
fi

if [[ "$(uname -r)" == "${kernel_version}" ]]; then
	echo -e "Kernel has been installed..."
	exit 0
fi

echo -e "Uninstalling lotServer..."
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
if [[ -e /appex/bin/serverSpeeder.sh ]]; then
	wget --no-check-certificate -O appex.sh https://raw.githubusercontent.com/MoeClub/lotServer/master/Install.sh && chmod +x appex.sh && bash appex.sh uninstall
	rm -f appex.sh
fi
echo -e "Downloading Kernel..."
wget --no-check-certificate https://github.com/Yuk1n0/Shadowsocks-Install/raw/master/Centos7/x86_64/kernel-${kernel_version}.rpm
echo -e "Installing Kernel..."
yum install -y kernel-${kernel_version}.rpm

#Check
list="$(awk -F\' '$1=="menuentry " {print i++ " : " $2}' /etc/grub2.cfg)"
target="CentOS Linux (${kernel_version})"
result=$(echo $list | grep "${target}")
if [[ "$result" == "" ]]; then
	echo -e "Failed to install bbrplus..."
	exit 1
fi

echo -e "Switching to new bbrplus-kernel..."
grub2-set-default 'CentOS Linux (${kernel_version}) 7 (Core)'
echo -e "Enable bbr module..."
echo "net.core.default_qdisc=fq" >>/etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbrplus" >>/etc/sysctl.conf
rm -f kernel-${kernel_version}.rpm

read -p "bbrplus installation completed，reboot server now ? [Y/n] :" answer
[ -z "${answer}" ] && answer="y"
if [[ $answer == [Yy] ]]; then
	echo -e "Rebooting..."
	reboot
fi
