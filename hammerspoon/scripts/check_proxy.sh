#! /bin/zsh

interface=$(route get default | grep interface | awk '{print $2}')
if [[ $? -ne 0 ]]; then
	return 1
fi

networkservice=$(networksetup -listallhardwareports | awk "/${interface}/ {print prev} {prev=\$0;}" | awk -F: '{print $2}' | awk '{$1=$1};1')

autoproxyurl=$(networksetup -getautoproxyurl ${networkservice})
[[ $autoproxyurl =~ "Yes" ]] && exit 0
webproxy=$(networksetup -getwebproxy ${networkservice})
[[ $webproxy =~ "Yes" ]] && exit 0
securewebproxy=$(networksetup -getsecurewebproxy ${networkservice})
[[ $securewebproxy =~ "Yes" ]] && exit 0
exit 1
