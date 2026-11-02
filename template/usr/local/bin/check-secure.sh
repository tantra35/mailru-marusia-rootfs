#!/bin/ash
set -u

PASS=1
IFACE=usb0
INTERFACES=/etc/network/interfaces

hash=$(awk -F: '$1 == "root" { print $2; exit }' /etc/shadow 2>/dev/null)
case $hash in '$'*) ;; *) exit 0 ;; esac
setting=${hash%\$*}

matches() {
	for t in cryptpw mkpasswd; do
		command -v "$t" >/dev/null || continue
		for s in "$hash" "$setting"; do
			[ "$("$t" -S "$s" "$PASS" 2>/dev/null)" = "$hash" ] && return 0
			[ "$("$t" "$PASS" "$s" 2>/dev/null)" = "$hash" ] && return 0
		done
	done
	if command -v openssl >/dev/null; then
		case $hash in
		'$6$'*)	[ "$(openssl passwd -6 -salt "$(echo "$hash" | cut -d'$' -f3)" \
			     "$PASS" 2>/dev/null)" = "$hash" ] && return 0 ;;
		esac
	fi
	return 1
}

matches || exit 0

ringled all FF0000

addr=$(awk -v i="$IFACE" '
	$1 == "iface"        { u = ($2 == i) }
	u && $1 == "address" { print $2; exit }
' "$INTERFACES" 2>/dev/null)
addr=${addr%%/*}
addr=${addr//./ }

offline-speak en "Hello, I'm VK Capsula mini."
offline-speak ru "альпайн линукс $(cat /etc/alpine-release),
ядро $(uname -r).
подключи колонку по тайп си для консоли. логин рут, пароль единица.
эс эс аш также доступен по тайп си по адресу ${addr}.
и не забудь сменить пароль, чтобы убрать это сообщение при старте."

ringled off

