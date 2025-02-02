#! /bin/zsh
# Usage: check_location.sh --wifi <ssid1> <ssid2> ... --ethernet <ip1> <ip2> ...

params=("$@")

ssids=()
for ((i=1; i<=$#params; i++)); do
	if [[ "${params[$i]}" = "--wifi" ]]; then
		for ((j=i+1; j<=$#params; j++)); do
			if [[ "${params[$j]}" = "--ethernet" ]]; then
				break
			fi
			ssids+=("(${params[$j]})")
		done
	fi
done
ssid_pattern=$(IFS=\|; echo "${ssids[*]}")

ips=()
for ((i=1; i<=$#params; i++)); do
	if [[ "${params[$i]}" = "--ethernet" ]]; then
		for ((j=i+1; j<=$#params; j++)); do
			if [[ "${params[$j]}" = "--wifi" ]]; then
				break
			fi
			ips+=("${params[$j]}")
		done
	fi
done

if [ -x "$(which gtimeout 2>/dev/null)" ]; then
  interface=$(gtimeout 1s route get default | grep interface | awk '{print $2}')
else
  interface=$(route get default | grep interface | awk '{print $2}')
fi
if [[ $? -ne 0 ]]; then
	return -1
fi

networkservice=$(networksetup -listallhardwareports | awk "/${interface}/ {print prev} {prev=\$0;}" | awk -F: '{print $2}' | awk '{$1=$1};1')

if [[ "Wi-Fi" = "$networkservice" ]]; then
  [[ -z "$ssids" ]] && return -1
	ipconfig getsummary ${interface} | awk -F ' SSID : '  '/ SSID : / {print $2}' | grep -q -E "^(${ssid_pattern})$"
elif [[ "$networkservice" =~ "^USB (.*) LAN$" ]]; then
  [[ -z "$ips" ]] && return 1
	ip=$(ifconfig "$interface" | grep "inet[^6]" | awk '{print $2}')
	for i in "${ips[@]}"; do
		[[ "$ip" =~ "$i" ]] && return 0
	done
	return 1
else
	return -1
fi