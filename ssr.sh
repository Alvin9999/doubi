#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#=================================================
# System Required: CentOS 6+/Debian 6+/Ubuntu 14.04+
# Description: Install the ShadowsocksR server
# Version: 2.0.38
# Author: Toyo
# Blog: https://doub.io/ss-jc42/
# 修改了原脚本，支持高版本系统
#=================================================
sh_ver="2.0.38"
filepath=$(cd "$(dirname "$0")"; pwd)
file=$(echo -e "${filepath}"|awk -F "$0" '{print $1}')
ssr_folder="/usr/local/shadowsocksr"
ssr_ss_file="${ssr_folder}/shadowsocks"
config_file="${ssr_folder}/config.json"
config_folder="/etc/shadowsocksr"
config_user_file="${config_folder}/user-config.json"
ssr_log_file="${ssr_ss_file}/ssserver.log"
Libsodiumr_file="/usr/local/lib/libsodium.so"
Libsodiumr_ver_backup="1.0.13"
Server_Speeder_file="/serverspeeder/bin/serverSpeeder.sh"
LotServer_file="/appex/bin/serverSpeeder.sh"
BBR_file="${file}/bbr.sh"
jq_file="${ssr_folder}/jq"
Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"
Separator_1="——————————————————————————————"

check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 当前账号非ROOT(或没有ROOT权限)，无法继续操作，请使用${Green_background_prefix} sudo su ${Font_color_suffix}来获取临时ROOT权限（执行后会提示输入当前账号的密码）。" && exit 1
}

check_sys(){
	if [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif cat /etc/issue | grep -q -E -i "debian"; then
		release="debian"
	elif cat /etc/issue | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
	elif cat /proc/version | grep -q -E -i "debian"; then
		release="debian"
	elif cat /proc/version | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
	fi
	bit=`uname -m`
}

check_pid(){
	PID=`ps -ef |grep -v grep | grep server.py |awk '{print $2}'`
}

SSR_installation_status(){
	[[ ! -e ${config_user_file} ]] && echo -e "${Error} 没有发现 ShadowsocksR 配置文件，请检查 !" && exit 1
	[[ ! -e ${ssr_folder} ]] && echo -e "${Error} 没有发现 ShadowsocksR 文件夹，请检查 !" && exit 1
}

Server_Speeder_installation_status(){
	[[ ! -e ${Server_Speeder_file} ]] && echo -e "${Error} 没有安装 锐速(Server Speeder)，请检查 !" && exit 1
}

LotServer_installation_status(){
	[[ ! -e ${LotServer_file} ]] && echo -e "${Error} 没有安装 LotServer，请检查 !" && exit 1
}

BBR_installation_status(){
	if [[ ! -e ${BBR_file} ]]; then
		echo -e "${Error} 没有发现 BBR脚本，开始下载..."
		cd "${file}"
		if ! wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/bbr.sh; then
			echo -e "${Error} BBR 脚本下载失败 !" && exit 1
		else
			echo -e "${Info} BBR 脚本下载完成 !"
			chmod +x bbr.sh
		fi
	fi
}

# 设置 防火墙规则
Add_iptables(){
	iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport ${ssr_port} -j ACCEPT
	iptables -I INPUT -m state --state NEW -m udp -p udp --dport ${ssr_port} -j ACCEPT
	ip6tables -I INPUT -m state --state NEW -m tcp -p tcp --dport ${ssr_port} -j ACCEPT
	ip6tables -I INPUT -m state --state NEW -m udp -p udp --dport ${ssr_port} -j ACCEPT
}

Del_iptables(){
	iptables -D INPUT -m state --state NEW -m tcp -p tcp --dport ${port} -j ACCEPT
	iptables -D INPUT -m state --state NEW -m udp -p udp --dport ${port} -j ACCEPT
	ip6tables -D INPUT -m state --state NEW -m tcp -p tcp --dport ${port} -j ACCEPT
	ip6tables -D INPUT -m state --state NEW -m udp -p udp --dport ${port} -j ACCEPT
}

Save_iptables(){
	if [[ ${release} == "centos" ]]; then
		service iptables save
		service ip6tables save
	else
		iptables-save > /etc/iptables.up.rules
		ip6tables-save > /etc/ip6tables.up.rules
	fi
}

Set_iptables(){
	if [[ ${release} == "centos" ]]; then
		service iptables save
		service ip6tables save
		chkconfig --level 2345 iptables on
		chkconfig --level 2345 ip6tables on
	else
		iptables-save > /etc/iptables.up.rules
		ip6tables-save > /etc/ip6tables.up.rules
		echo -e '#!/bin/bash\n/sbin/iptables-restore < /etc/iptables.up.rules\n/sbin/ip6tables-restore < /etc/ip6tables.up.rules' > /etc/network/if-pre-up.d/iptables
		chmod +x /etc/network/if-pre-up.d/iptables
	fi
}

# 读取 配置信息
Get_IP(){
	ip=$(wget -qO- -t1 -T2 ipinfo.io/ip)
	if [[ -z "${ip}" ]]; then
		ip=$(wget -qO- -t1 -T2 api.ip.sb/ip)
		if [[ -z "${ip}" ]]; then
			ip=$(wget -qO- -t1 -T2 members.3322.org/dyndns/getip)
			if [[ -z "${ip}" ]]; then
				ip="VPS_IP"
			fi
		fi
	fi
}

Get_User(){
	[[ ! -e ${jq_file} ]] && echo -e "${Error} JQ解析器 不存在，请检查 !" && exit 1
	port=`${jq_file} '.server_port' ${config_user_file}`
	password=`${jq_file} '.password' ${config_user_file} | sed 's/^.//;s/.$//'`
	method=`${jq_file} '.method' ${config_user_file} | sed 's/^.//;s/.$//'`
	protocol=`${jq_file} '.protocol' ${config_user_file} | sed 's/^.//;s/.$//'`
	obfs=`${jq_file} '.obfs' ${config_user_file} | sed 's/^.//;s/.$//'`
	protocol_param=`${jq_file} '.protocol_param' ${config_user_file} | sed 's/^.//;s/.$//'`
	speed_limit_per_con=`${jq_file} '.speed_limit_per_con' ${config_user_file}`
	speed_limit_per_user=`${jq_file} '.speed_limit_per_user' ${config_user_file}`
	connect_verbose_info=`${jq_file} '.connect_verbose_info' ${config_user_file}`
}

urlsafe_base64(){
	date=$(echo -n "$1"|base64|sed ':a;N;s/\n/ /g;ta'|sed 's/ //g;s/=//g;s/+/-/g;s/\//_/g')
	echo -e "${date}"
}

ss_link_qr(){
	SSbase64=$(urlsafe_base64 "${method}:${password}@${ip}:${port}")
	SSurl="ss://${SSbase64}"
	SSQRcode="http://doub.pw/qr/qr.php?text=${SSurl}"
	ss_link=" SS 链接 : ${Green_font_prefix}${SSurl}${Font_color_suffix} \n SS 二维码 : ${Green_font_prefix}${SSQRcode}${Font_color_suffix}"
}

ssr_link_qr(){
	SSRprotocol=$(echo ${protocol} | sed 's/_compatible//g')
	SSRobfs=$(echo ${obfs} | sed 's/_compatible//g')
	SSRPWDbase64=$(urlsafe_base64 "${password}")
	SSRbase64=$(urlsafe_base64 "${ip}:${port}:${SSRprotocol}:${method}:${SSRobfs}:${SSRPWDbase64}")
	SSRurl="ssr://${SSRbase64}"
	SSRQRcode="http://doub.pw/qr/qr.php?text=${SSRurl}"
	ssr_link=" SSR 链接 : ${Red_font_prefix}${SSRurl}${Font_color_suffix} \n SSR 二维码 : ${Red_font_prefix}${SSRQRcode}${Font_color_suffix} \n "
}

ss_ssr_determine(){
	protocol_suffix=`echo ${protocol} | awk -F "_" '{print $NF}'`
	obfs_suffix=`echo ${obfs} | awk -F "_" '{print $NF}'`
	if [[ ${protocol} = "origin" ]]; then
		if [[ ${obfs} = "plain" ]]; then
			ss_link_qr
			ssr_link=""
		else
			if [[ ${obfs_suffix} != "compatible" ]]; then
				ss_link=""
			else
				ss_link_qr
			fi
		fi
	else
		if [[ ${protocol_suffix} != "compatible" ]]; then
			ss_link=""
		else
			if [[ ${obfs_suffix} != "compatible" ]]; then
				if [[ ${obfs_suffix} = "plain" ]]; then
					ss_link_qr
				else
					ss_link=""
				fi
			else
				ss_link_qr
			fi
		fi
	fi
	ssr_link_qr
}

# 显示 配置信息
View_User(){
	SSR_installation_status
	Get_IP
	Get_User
	now_mode=$(cat "${config_user_file}"|grep '"port_password"')
	[[ -z ${protocol_param} ]] && protocol_param="0(无限)"
	if [[ -z "${now_mode}" ]]; then
		ss_ssr_determine
		clear
		echo "==================================================="
		echo
		echo -e " ShadowsocksR账号 配置信息："
		echo
		echo -e " I P\t : ${Green_font_prefix}${ip}${Font_color_suffix}"
		echo -e " 端口\t : ${Green_font_prefix}${port}${Font_color_suffix}"
		echo -e " 密码\t : ${Green_font_prefix}${password}${Font_color_suffix}"
		echo -e " 加密\t : ${Green_font_prefix}${method}${Font_color_suffix}"
		echo -e " 协议\t : ${Red_font_prefix}${protocol}${Font_color_suffix}"
		echo -e " 混淆\t : ${Red_font_prefix}${obfs}${Font_color_suffix}"
		echo -e " 设备数限制 : ${Green_font_prefix}${protocol_param}${Font_color_suffix}"
		echo -e " 单线程限速 : ${Green_font_prefix}${speed_limit_per_con} KB/S${Font_color_suffix}"
		echo -e " 端口总限速 : ${Green_font_prefix}${speed_limit_per_user} KB/S${Font_color_suffix}"
		echo -e "${ss_link}"
		echo -e "${ssr_link}"
		echo -e " ${Green_font_prefix} 提示: ${Font_color_suffix} 在浏览器中，打开二维码链接，就可以看到二维码图片。 协议和混淆后面的[ _compatible ]，指的是 兼容原版协议/混淆。"
		echo
		echo "==================================================="
	else
		user_total=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | wc -l`
		[[ ${user_total} = "0" ]] && echo -e "${Error} 没有发现 多端口用户，请检查 !" && exit 1
		clear
		echo "==================================================="
		echo
		echo -e " ShadowsocksR账号 配置信息："
		echo
		echo -e " I P\t : ${Green_font_prefix}${ip}${Font_color_suffix}"
		echo -e " 加密\t : ${Green_font_prefix}${method}${Font_color_suffix}"
		echo -e " 协议\t : ${Red_font_prefix}${protocol}${Font_color_suffix}"
		echo -e " 混淆\t : ${Red_font_prefix}${obfs}${Font_color_suffix}"
		echo -e " 设备数限制 : ${Green_font_prefix}${protocol_param}${Font_color_suffix}"
		echo -e " 单线程限速 : ${Green_font_prefix}${speed_limit_per_con} KB/S${Font_color_suffix}"
		echo -e " 端口总限速 : ${Green_font_prefix}${speed_limit_per_user} KB/S${Font_color_suffix}"
		echo && echo
		for((integer = ${user_total}; integer >= 1; integer--))
		do
			port=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | awk -F ":" '{print $1}' | sed -n "${integer}p" | sed -r 's/.*\"(.+)\".*/\1/'`
			password=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | awk -F ":" '{print $2}' | sed -n "${integer}p" | sed -r 's/.*\"(.+)\".*/\1/'`
			ss_ssr_determine
			echo -e ${Separator_1}
			echo -e " 端口\t : ${Green_font_prefix}${port}${Font_color_suffix}"
			echo -e " 密码\t : ${Green_font_prefix}${password}${Font_color_suffix}"
			echo -e "${ss_link}"
			echo -e "${ssr_link}"
		done
		echo -e " ${Green_font_prefix} 提示: ${Font_color_suffix} 在浏览器中，打开二维码链接，就可以看到二维码图片。 协议和混淆后面的[ _compatible ]，指的是 兼容原版协议/混淆。"
		echo
		echo "==================================================="
	fi
}

# 设置 配置信息
Set_config_port(){
	while true
	do
		echo -e "请输入要设置的ShadowsocksR账号 端口"
		read -e -p "(默认: 2333):" ssr_port
		[[ -z "$ssr_port" ]] && ssr_port="2333"
		echo $((${ssr_port}+0)) &>/dev/null
		if [[ $? == 0 ]]; then
			if [[ ${ssr_port} -ge 1 ]] && [[ ${ssr_port} -le 65535 ]]; then
				echo
				echo ${Separator_1}
				echo -e " 端口 : ${Green_font_prefix}${ssr_port}${Font_color_suffix}"
				echo ${Separator_1}
				echo
				break
			else
				echo -e "${Error} 请输入正确的数字(1-65535)"
			fi
		else
			echo -e "${Error} 请输入正确的数字(1-65535)"
		fi
	done
}

Set_config_password(){
	echo "请输入要设置的ShadowsocksR账号 密码"
	read -e -p "(默认: doub.io):" ssr_password
	[[ -z "${ssr_password}" ]] && ssr_password="doub.io"
	echo
	echo ${Separator_1}
	echo -e " 密码 : ${Green_font_prefix}${ssr_password}${Font_color_suffix}"
	echo ${Separator_1}
	echo
}

Set_config_method(){
	echo -e "请选择要设置的ShadowsocksR账号 加密方式 ${Green_font_prefix} 1.${Font_color_suffix} none ${Tip} 如果使用 auth_chain_a 协议，请加密方式选择 none，混淆随意(建议 plain)
 ${Green_font_prefix} 2.${Font_color_suffix} rc4
 ${Green_font_prefix} 3.${Font_color_suffix} rc4-md5
 ${Green_font_prefix} 4.${Font_color_suffix} rc4-md5-6
 ${Green_font_prefix} 5.${Font_color_suffix} aes-128-ctr
 ${Green_font_prefix} 6.${Font_color_suffix} aes-192-ctr
 ${Green_font_prefix} 7.${Font_color_suffix} aes-256-ctr
 ${Green_font_prefix} 8.${Font_color_suffix} aes-128-cfb
 ${Green_font_prefix} 9.${Font_color_suffix} aes-192-cfb
 ${Green_font_prefix}10.${Font_color_suffix} aes-256-cfb
 ${Green_font_prefix}11.${Font_color_suffix} aes-128-cfb8
 ${Green_font_prefix}12.${Font_color_suffix} aes-192-cfb8
 ${Green_font_prefix}13.${Font_color_suffix} aes-256-cfb8
 ${Green_font_prefix}14.${Font_color_suffix} salsa20
 ${Green_font_prefix}15.${Font_color_suffix} chacha20
 ${Green_font_prefix}16.${Font_color_suffix} chacha20-ietf
 ${Tip} salsa20/chacha20-*系列加密方式，需要额外安装依赖 libsodium ，否则会无法启动ShadowsocksR !"
	echo
	read -e -p "(默认: 5. aes-128-ctr):" ssr_method
	[[ -z "${ssr_method}" ]] && ssr_method="5"
	if [[ ${ssr_method} == "1" ]]; then
		ssr_method="none"
	elif [[ ${ssr_method} == "2" ]]; then
		ssr_method="rc4"
	elif [[ ${ssr_method} == "3" ]]; then
		ssr_method="rc4-md5"
	elif [[ ${ssr_method} == "4" ]]; then
		ssr_method="rc4-md5-6"
	elif [[ ${ssr_method} == "5" ]]; then
		ssr_method="aes-128-ctr"
	elif [[ ${ssr_method} == "6" ]]; then
		ssr_method="aes-192-ctr"
	elif [[ ${ssr_method} == "7" ]]; then
		ssr_method="aes-256-ctr"
	elif [[ ${ssr_method} == "8" ]]; then
		ssr_method="aes-128-cfb"
	elif [[ ${ssr_method} == "9" ]]; then
		ssr_method="aes-192-cfb"
	elif [[ ${ssr_method} == "10" ]]; then
		ssr_method="aes-256-cfb"
	elif [[ ${ssr_method} == "11" ]]; then
		ssr_method="aes-128-cfb8"
	elif [[ ${ssr_method} == "12" ]]; then
		ssr_method="aes-192-cfb8"
	elif [[ ${ssr_method} == "13" ]]; then
		ssr_method="aes-256-cfb8"
	elif [[ ${ssr_method} == "14" ]]; then
		ssr_method="salsa20"
	elif [[ ${ssr_method} == "15" ]]; then
		ssr_method="chacha20"
	elif [[ ${ssr_method} == "16" ]]; then
		ssr_method="chacha20-ietf"
	else
		ssr_method="aes-128-ctr"
	fi
	echo
	echo ${Separator_1}
	echo -e " 加密 : ${Green_font_prefix}${ssr_method}${Font_color_suffix}"
	echo ${Separator_1}
	echo
}

Set_config_protocol(){
	echo -e "请选择要设置的ShadowsocksR账号 协议插件 ${Green_font_prefix}1.${Font_color_suffix} origin
 ${Green_font_prefix}2.${Font_color_suffix} auth_sha1_v4
 ${Green_font_prefix}3.${Font_color_suffix} auth_aes128_md5
 ${Green_font_prefix}4.${Font_color_suffix} auth_aes128_sha1
 ${Green_font_prefix}5.${Font_color_suffix} auth_chain_a
 ${Green_font_prefix}6.${Font_color_suffix} auth_chain_b
 ${Tip} 如果使用 auth_chain_a 协议，请加密方式选择 none，混淆随意(建议 plain)"
	echo
	read -e -p "(默认: 2. auth_sha1_v4):" ssr_protocol
	[[ -z "${ssr_protocol}" ]] && ssr_protocol="2"
	if [[ ${ssr_protocol} == "1" ]]; then
		ssr_protocol="origin"
	elif [[ ${ssr_protocol} == "2" ]]; then
		ssr_protocol="auth_sha1_v4"
	elif [[ ${ssr_protocol} == "3" ]]; then
		ssr_protocol="auth_aes128_md5"
	elif [[ ${ssr_protocol} == "4" ]]; then
		ssr_protocol="auth_aes128_sha1"
	elif [[ ${ssr_protocol} == "5" ]]; then
		ssr_protocol="auth_chain_a"
	elif [[ ${ssr_protocol} == "6" ]]; then
		ssr_protocol="auth_chain_b"
	else
		ssr_protocol="auth_sha1_v4"
	fi
	echo
	echo ${Separator_1}
	echo -e " 协议 : ${Green_font_prefix}${ssr_protocol}${Font_color_suffix}"
	echo ${Separator_1}
	echo
	if [[ ${ssr_protocol} != "origin" ]]; then
		if [[ ${ssr_protocol} == "auth_sha1_v4" ]]; then
			read -e -p "是否设置 协议插件兼容原版(_compatible)？[Y/n]" ssr_protocol_yn
			[[ -z "${ssr_protocol_yn}" ]] && ssr_protocol_yn="y"
			[[ $ssr_protocol_yn == [Yy] ]] && ssr_protocol=${ssr_protocol}"_compatible"
		fi
	fi
}

Set_config_obfs(){
	echo -e "请选择要设置的ShadowsocksR账号 混淆插件 ${Green_font_prefix}1.${Font_color_suffix} plain
 ${Green_font_prefix}2.${Font_color_suffix} http_simple
 ${Green_font_prefix}3.${Font_color_suffix} http_post
 ${Green_font_prefix}4.${Font_color_suffix} random_head
 ${Green_font_prefix}5.${Font_color_suffix} tls1.2_ticket_auth
 ${Tip} 如果使用 ShadowsocksR 加速游戏，请选择 混淆兼容原版或 plain 混淆，然后客户端选择 plain，否则会增加延迟 !
 另外, 如果你选择了 tls1.2_ticket_auth，那么客户端可以选择 tls1.2_ticket_fastauth，这样即能伪装又不会增加延迟 !
 如果你是在日本、美国等热门地区搭建，那么选择 plain 混淆可能被墙几率更低 !"
	echo
	read -e -p "(默认: 1. plain):" ssr_obfs
	[[ -z "${ssr_obfs}" ]] && ssr_obfs="1"
	if [[ ${ssr_obfs} == "1" ]]; then
		ssr_obfs="plain"
	elif [[ ${ssr_obfs} == "2" ]]; then
		ssr_obfs="http_simple"
	elif [[ ${ssr_obfs} == "3" ]]; then
		ssr_obfs="http_post"
	elif [[ ${ssr_obfs} == "4" ]]; then
		ssr_obfs="random_head"
	elif [[ ${ssr_obfs} == "5" ]]; then
		ssr_obfs="tls1.2_ticket_auth"
	else
		ssr_obfs="plain"
	fi
	echo
	echo ${Separator_1}
	echo -e " 混淆 : ${Green_font_prefix}${ssr_obfs}${Font_color_suffix}"
	echo ${Separator_1}
	echo
	if [[ ${ssr_obfs} != "plain" ]]; then
		read -e -p "是否设置 混淆插件兼容原版(_compatible)？[Y/n]" ssr_obfs_yn
		[[ -z "${ssr_obfs_yn}" ]] && ssr_obfs_yn="y"
		[[ $ssr_obfs_yn == [Yy] ]] && ssr_obfs=${ssr_obfs}"_compatible"
	fi
}

Set_config_protocol_param(){
	while true
	do
		echo -e "请输入要设置的ShadowsocksR账号 欲限制的设备数 (${Green_font_prefix} auth_* 系列协议 不兼容原版才有效 ${Font_color_suffix})"
		echo -e "${Tip} 设备数限制：每个端口同一时间能链接的客户端数量(多端口模式，每个端口都是独立计算)，建议最少 2个。"
		read -e -p "(默认: 无限):" ssr_protocol_param
		[[ -z "$ssr_protocol_param" ]] && ssr_protocol_param="" && echo && break
		echo $((${ssr_protocol_param}+0)) &>/dev/null
		if [[ $? == 0 ]]; then
			if [[ ${ssr_protocol_param} -ge 1 ]] && [[ ${ssr_protocol_param} -le 9999 ]]; then
				echo
				echo ${Separator_1}
				echo -e " 设备数限制 : ${Green_font_prefix}${ssr_protocol_param}${Font_color_suffix}"
				echo ${Separator_1}
				echo
				break
			else
				echo -e "${Error} 请输入正确的数字(1-9999)"
			fi
		else
			echo -e "${Error} 请输入正确的数字(1-9999)"
		fi
	done
}

Set_config_speed_limit_per_con(){
	while true
	do
		echo -e "请输入要设置的每个端口 单线程 限速上限(单位：KB/S)"
		echo -e "${Tip} 单线程限速：每个端口 单线程的限速上限，多线程即无效。"
		read -e -p "(默认: 无限):" ssr_speed_limit_per_con
		[[ -z "$ssr_speed_limit_per_con" ]] && ssr_speed_limit_per_con=0 && echo && break
		echo $((${ssr_speed_limit_per_con}+0)) &>/dev/null
		if [[ $? == 0 ]]; then
			if [[ ${ssr_speed_limit_per_con} -ge 1 ]] && [[ ${ssr_speed_limit_per_con} -le 131072 ]]; then
				echo
				echo ${Separator_1}
				echo -e " 单线程限速 : ${Green_font_prefix}${ssr_speed_limit_per_con} KB/S${Font_color_suffix}"
				echo ${Separator_1}
				echo
				break
			else
				echo -e "${Error} 请输入正确的数字(1-131072)"
			fi
		else
			echo -e "${Error} 请输入正确的数字(1-131072)"
		fi
	done
}

Set_config_speed_limit_per_user(){
	while true
	do
		echo
		echo -e "请输入要设置的每个端口 总速度 限速上限(单位：KB/S)"
		echo -e "${Tip} 端口总限速：每个端口 总速度 限速上限，单个端口整体限速。"
		read -e -p "(默认: 无限):" ssr_speed_limit_per_user
		[[ -z "$ssr_speed_limit_per_user" ]] && ssr_speed_limit_per_user=0 && echo && break
		echo $((${ssr_speed_limit_per_user}+0)) &>/dev/null
		if [[ $? == 0 ]]; then
			if [[ ${ssr_speed_limit_per_user} -ge 1 ]] && [[ ${ssr_speed_limit_per_user} -le 131072 ]]; then
				echo
				echo ${Separator_1}
				echo -e " 端口总限速 : ${Green_font_prefix}${ssr_speed_limit_per_user} KB/S${Font_color_suffix}"
				echo ${Separator_1}
				echo
				break
			else
				echo -e "${Error} 请输入正确的数字(1-131072)"
			fi
		else
			echo -e "${Error} 请输入正确的数字(1-131072)"
		fi
	done
}

Set_config_all(){
	Set_config_port
	Set_config_password
	Set_config_method
	Set_config_protocol
	Set_config_obfs
	Set_config_protocol_param
	Set_config_speed_limit_per_con
	Set_config_speed_limit_per_user
}

# 修改 配置信息
Modify_config_port(){
	sed -i 's/"server_port": '"$(echo ${port})"'/"server_port": '"$(echo ${ssr_port})"'/g' ${config_user_file}
}

Modify_config_password(){
	sed -i 's/"password": "'"$(echo ${password})"'"/"password": "'"$(echo ${ssr_password})"'"/g' ${config_user_file}
}

Modify_config_method(){
	sed -i 's/"method": "'"$(echo ${method})"'"/"method": "'"$(echo ${ssr_method})"'"/g' ${config_user_file}
}

Modify_config_protocol(){
	sed -i 's/"protocol": "'"$(echo ${protocol})"'"/"protocol": "'"$(echo ${ssr_protocol})"'"/g' ${config_user_file}
}

Modify_config_obfs(){
	sed -i 's/"obfs": "'"$(echo ${obfs})"'"/"obfs": "'"$(echo ${ssr_obfs})"'"/g' ${config_user_file}
}

Modify_config_protocol_param(){
	sed -i 's/"protocol_param": "'"$(echo ${protocol_param})"'"/"protocol_param": "'"$(echo ${ssr_protocol_param})"'"/g' ${config_user_file}
}

Modify_config_speed_limit_per_con(){
	sed -i 's/"speed_limit_per_con": '"$(echo ${speed_limit_per_con})"'/"speed_limit_per_con": '"$(echo ${ssr_speed_limit_per_con})"'/g' ${config_user_file}
}

Modify_config_speed_limit_per_user(){
	sed -i 's/"speed_limit_per_user": '"$(echo ${speed_limit_per_user})"'/"speed_limit_per_user": '"$(echo ${ssr_speed_limit_per_user})"'/g' ${config_user_file}
}

Modify_config_connect_verbose_info(){
	sed -i 's/"connect_verbose_info": '"$(echo ${connect_verbose_info})"'/"connect_verbose_info": '"$(echo ${ssr_connect_verbose_info})"'/g' ${config_user_file}
}

Modify_config_all(){
	Modify_config_port
	Modify_config_password
	Modify_config_method
	Modify_config_protocol
	Modify_config_obfs
	Modify_config_protocol_param
	Modify_config_speed_limit_per_con
	Modify_config_speed_limit_per_user
}

Modify_config_port_many(){
	sed -i 's/"'"$(echo ${port})"'":/"'"$(echo ${ssr_port})"'":/g' ${config_user_file}
}

Modify_config_password_many(){
	sed -i 's/"'"$(echo ${password})"'"/"'"$(echo ${ssr_password})"'"/g' ${config_user_file}
}

# 写入 配置信息
Write_configuration(){
	cat > ${config_user_file}<<-EOF
{
	"server": "0.0.0.0",
	"server_ipv6": "::",
	"server_port": ${ssr_port},
	"local_address": "127.0.0.1",
	"local_port": 1080,
	"password": "${ssr_password}",
	"method": "${ssr_method}",
	"protocol": "${ssr_protocol}",
	"protocol_param": "${ssr_protocol_param}",
	"obfs": "${ssr_obfs}",
	"obfs_param": "",
	"speed_limit_per_con": ${ssr_speed_limit_per_con},
	"speed_limit_per_user": ${ssr_speed_limit_per_user},
	"additional_ports" : {},
	"timeout": 120,
	"udp_timeout": 60,
	"dns_ipv6": false,
	"connect_verbose_info": 0,
	"redirect": "",
	"fast_open": false
}
EOF
}

Write_configuration_many(){
	cat > ${config_user_file}<<-EOF
{
	"server": "0.0.0.0",
	"server_ipv6": "::",
	"local_address": "127.0.0.1",
	"local_port": 1080,
	"port_password":{
		"${ssr_port}":"${ssr_password}"
	},
	"method": "${ssr_method}",
	"protocol": "${ssr_protocol}",
	"protocol_param": "${ssr_protocol_param}",
	"obfs": "${ssr_obfs}",
	"obfs_param": "",
	"speed_limit_per_con": ${ssr_speed_limit_per_con},
	"speed_limit_per_user": ${ssr_speed_limit_per_user},
	"additional_ports" : {},
	"timeout": 120,
	"udp_timeout": 60,
	"dns_ipv6": false,
	"connect_verbose_info": 0,
	"redirect": "",
	"fast_open": false
}
EOF
}

Check_python(){
	python_ver=`python -h`
	if [[ -z ${python_ver} ]]; then
		echo -e "${Info} 没有安装Python，开始安装..."
		if [[ ${release} == "centos" ]]; then
			yum install -y python
		else
			apt-get install -y python
		fi
	fi
}

Centos_yum(){
	yum update
	cat /etc/redhat-release |grep 7\..*|grep -i centos>/dev/null
	if [[ $? = 0 ]]; then
		yum install -y vim unzip net-tools
	else
		yum install -y vim unzip
	fi
}

Debian_apt(){
	apt-get update
	cat /etc/issue |grep 9\..*>/dev/null
	if [[ $? = 0 ]]; then
		apt-get install -y vim unzip net-tools
	else
		apt-get install -y vim unzip
	fi
}

# 下载 ShadowsocksR
Download_SSR(){
	cd "/usr/local/"
	wget -N --no-check-certificate "https://github.com/ToyoDAdoubiBackup/shadowsocksr/archive/manyuser.zip"
	#git config --global http.sslVerify false
	#env GIT_SSL_NO_VERIFY=true git clone -b manyuser https://github.com/ToyoDAdoubiBackup/shadowsocksr.git
	#[[ ! -e ${ssr_folder} ]] && echo -e "${Error} ShadowsocksR服务端 下载失败 !" && exit 1
	[[ ! -e "manyuser.zip" ]] && echo -e "${Error} ShadowsocksR服务端 压缩包 下载失败 !" && rm -rf manyuser.zip && exit 1
	unzip "manyuser.zip"
	[[ ! -e "/usr/local/shadowsocksr-manyuser/" ]] && echo -e "${Error} ShadowsocksR服务端 解压失败 !" && rm -rf manyuser.zip && exit 1
	mv "/usr/local/shadowsocksr-manyuser/" "/usr/local/shadowsocksr/"
	[[ ! -e "/usr/local/shadowsocksr/" ]] && echo -e "${Error} ShadowsocksR服务端 重命名失败 !" && rm -rf manyuser.zip && rm -rf "/usr/local/shadowsocksr-manyuser/" && exit 1
	rm -rf manyuser.zip
	[[ -e ${config_folder} ]] && rm -rf ${config_folder}
	mkdir ${config_folder}
	[[ ! -e ${config_folder} ]] && echo -e "${Error} ShadowsocksR配置文件的文件夹 建立失败 !" && exit 1
	echo -e "${Info} ShadowsocksR服务端 下载完成 !"
}

Service_SSR(){
	if [[ ${release} = "centos" ]]; then
		if ! wget --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/service/ssr_centos -O /etc/init.d/ssr; then
			echo -e "${Error} ShadowsocksR服务 管理脚本下载失败 !" && exit 1
		fi
		chmod +x /etc/init.d/ssr
		chkconfig --add ssr
		chkconfig ssr on
	else
		if ! wget --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/service/ssr_debian -O /etc/init.d/ssr; then
			echo -e "${Error} ShadowsocksR服务 管理脚本下载失败 !" && exit 1
		fi
		chmod +x /etc/init.d/ssr
		update-rc.d -f ssr defaults
	fi
	echo -e "${Info} ShadowsocksR服务 管理脚本下载完成 !"
}

# 安装 JQ解析器
JQ_install(){
	if [[ ! -e ${jq_file} ]]; then
		cd "${ssr_folder}"
		if [[ ${bit} = "x86_64" ]]; then
			mv "jq-linux64" "jq"
			#wget --no-check-certificate "https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64" -O ${jq_file}
		else
			mv "jq-linux32" "jq"
			#wget --no-check-certificate "https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux32" -O ${jq_file}
		fi
		[[ ! -e ${jq_file} ]] && echo -e "${Error} JQ解析器 重命名失败，请检查 !" && exit 1
		chmod +x ${jq_file}
		echo -e "${Info} JQ解析器 安装完成，继续..."
	else
		echo -e "${Info} JQ解析器 已安装，继续..."
	fi
}

# 安装 依赖
Installation_dependency(){
	if [[ ${release} == "centos" ]]; then
		Centos_yum
	else
		Debian_apt
	fi
	[[ ! -e "/usr/bin/unzip" ]] && echo -e "${Error} 依赖 unzip(解压压缩包) 安装失败，多半是软件包源的问题，请检查 !" && exit 1
	Check_python
	#echo "nameserver 8.8.8.8" > /etc/resolv.conf
	#echo "nameserver 8.8.4.4" >> /etc/resolv.conf
	\cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
}

Install_SSR(){
	check_root
	[[ -e ${config_user_file} ]] && echo -e "${Error} ShadowsocksR 配置文件已存在，请检查( 如安装失败或者存在旧版本，请先卸载 ) !" && exit 1
	[[ -e ${ssr_folder} ]] && echo -e "${Error} ShadowsocksR 文件夹已存在，请检查( 如安装失败或者存在旧版本，请先卸载 ) !" && exit 1
	echo -e "${Info} 开始设置 ShadowsocksR账号配置..."
	Set_config_all
	echo -e "${Info} 开始安装/配置 ShadowsocksR依赖..."
	Installation_dependency
	echo -e "${Info} 开始下载/安装 ShadowsocksR文件..."
	Download_SSR
	echo -e "${Info} 开始下载/安装 ShadowsocksR服务脚本(init)..."
	Service_SSR
	echo -e "${Info} 开始下载/安装 JSNO解析器 JQ..."
	JQ_install
	echo -e "${Info} 开始写入 ShadowsocksR配置文件..."
	Write_configuration
	echo -e "${Info} 开始设置 iptables防火墙..."
	Set_iptables
	echo -e "${Info} 开始添加 iptables防火墙规则..."
	Add_iptables
	echo -e "${Info} 开始保存 iptables防火墙规则..."
	Save_iptables
	echo -e "${Info} 所有步骤 安装完毕，开始启动 ShadowsocksR服务端..."
	Start_SSR
}

Update_SSR(){
	SSR_installation_status
	echo -e "因破娃暂停更新ShadowsocksR服务端，所以此功能临时禁用。"
	#cd ${ssr_folder}
	#git pull
	#Restart_SSR
}

Uninstall_SSR(){
    if [[ ! -e ${config_user_file} ]] && [[ ! -e ${ssr_folder} ]]; then
        echo -e "${Error} ShadowsocksR 未安装！" && exit 1
    fi
    echo -e "${Info} 正在卸载 ShadowsocksR..."
    # 假设卸载操作为删除相关文件和目录
    rm -rf ${config_folder}
    rm -rf ${ssr_folder}
    rm -f /etc/init.d/ssr
    echo -e "${Info} ShadowsocksR 已卸载！"
}
