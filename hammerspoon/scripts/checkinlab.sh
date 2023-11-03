#! /bin/zsh

interface=$(route get default | grep interface | awk '{print $2}')
if [[ $? -ne 0 ]]; then
	return 1
fi

networkservice=$(networksetup -listallhardwareports | awk "/${interface}/ {print prev} {prev=\$0;}" | awk -F: '{print $2}' | awk '{$1=$1};1')

if [[ "Wi-Fi" = "$networkservice" ]]; then
	/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep -o 'SSID: .*$' | cut -c 7- | grep -q "<possible-ssid-pattern"
elif [[ "$networkservice" =~ "^USB (.*) LAN$" ]]; then
	ip=$(ifconfig "$interface" | grep "inet[^6]" | awk '{print $2}')
	[[ "$ip" =~ "<possible-ip-pattern>" ]] && return 0 || return 1
else
	return 1
fi