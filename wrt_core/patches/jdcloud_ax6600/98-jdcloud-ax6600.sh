#!/bin/sh

# 京东云 AX6600 雅典娜定制版首启设置。
# 配置由构建工作流写入 /etc/config/jdcloud-settings；执行后删除，避免在系统中
# 长期保留 root/PPPoE 明文设置。没有该文件时使用仓库默认值。

BOARD_NAME=$(cat /tmp/sysinfo/board_name 2>/dev/null)
case "$BOARD_NAME" in
	jdcloud,ax6600|jdcloud,re-cs-02) ;;
	*) exit 0 ;;
esac

SETTINGS_FILE=/etc/config/jdcloud-settings
if [ -f "$SETTINGS_FILE" ]; then
	. "$SETTINGS_FILE"
fi

net_mode=${net_mode:-dhcp}
lan_ip=${lan_ip:-192.168.2.1}
root_pw=${root_pw:-666666}
wifi_ssid=${wifi_ssid:-ASUS395}
wifi_word=${wifi_word:-yjb123456}

# LAN 子网与 WAN 模式。
uci set network.lan.proto='static'
uci set network.lan.ipaddr="$lan_ip"
uci set network.lan.netmask='255.255.255.0'
if [ "$net_mode" = 'pppoe' ] && [ -n "$pppoe_account" ] && [ -n "$pppoe_password" ]; then
	uci set network.wan.proto='pppoe'
	uci set network.wan.username="$pppoe_account"
	uci set network.wan.password="$pppoe_password"
	uci set network.wan.peerdns='1'
	uci set network.wan.auto='1'
	uci set network.wan6.proto='none'
else
	uci set network.wan.proto='dhcp'
	uci set network.wan6.proto='dhcpv6'
fi

# AX6600 三个无线 radio 的默认 AP。
for radio in 0 1 2; do
	section="wireless.default_radio${radio}"
	if uci -q get "$section.ssid" >/dev/null 2>&1; then
		uci set "$section.ssid=$wifi_ssid"
		uci set "$section.encryption=psk2+ccmp"
		uci set "$section.key=$wifi_word"
	fi
done

# 默认主题为 OpenWrt；保留上游认证与 2FA 机制。
uci -q set luci.main='core'
uci set luci.main.mediaurlbase='/luci-static/openwrt'

# LuCI 长会话默认值；若上游没有该 section，则创建一个 named section。
uci -q set luci.sauth='sauth'
uci set luci.sauth.cookie_days='365'
uci set luci.sauth.sessiontime='604800'

# 首次访问便利设置：完成调试后建议把 WAN 入站改回 REJECT。
WAN_ZONE=$(uci show firewall 2>/dev/null | sed -n "s/^firewall\.@zone\[\([0-9][0-9]*\)\]\.name='wan'$/\1/p" | head -n1)
[ -n "$WAN_ZONE" ] && uci set "firewall.@zone[$WAN_ZONE].input=ACCEPT"

# ttyd 与 dropbear 不限定接口，便于从 WAN/LAN 调试；完成调试后应收紧防火墙。
uci -q delete ttyd.@ttyd[0].interface
uci set dropbear.@dropbear[0].Interface=''

# 安卓 TV 时间同步域名映射。
if ! uci show dhcp 2>/dev/null | grep -q "name='time.android.com'"; then
	DHCP_DOMAIN=$(uci add dhcp domain)
	uci set "dhcp.$DHCP_DOMAIN.name=time.android.com"
	uci set "dhcp.$DHCP_DOMAIN.ip=203.107.6.88"
fi

# 首启启用常用 collectd 统计插件。
for plugin in cpu memory load interface df sensors; do
	if uci -q get "luci_statistics.collectd_$plugin" >/dev/null 2>&1; then
		uci set "luci_statistics.collectd_$plugin.enable=1"
	fi
done

printf '%s\n%s\n' "$root_pw" "$root_pw" | passwd root >/dev/null 2>&1 || true

# 让 LuCI 系统页和 SSH banner 显示设备规格。
if [ -f /etc/openwrt_release ]; then
	sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='京东云无线宝 AX6600 雅典娜 · 1G RAM · 128G EMMC · Quad-core ARM Cortex-A53 @ 1.8GHz'/" /etc/openwrt_release
fi

uci commit
rm -f "$SETTINGS_FILE"
exit 0
