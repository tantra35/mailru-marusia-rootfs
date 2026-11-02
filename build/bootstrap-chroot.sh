#!/usr/bin/env bash
# Бутстрап aarch64-chroot для abuild (запускается root'ом, один раз)
set -euo pipefail
B=/home/ruslan/Загрузки/marusia/build-rootfs
C=$B/chroot

[ -d "$C/etc" ] && { echo "chroot уже существует"; exit 0; }
mkdir -p "$C"

# базовая система aarch64
"$B/build/sbin/apk.static" --root "$C" --initdb --arch aarch64 \
  --keys-dir "$B/build/apk-keys" --repositories-file "$B/build/repositories.txt" \
  --cache-dir "$B/build/apk-cache" --no-progress \
  add alpine-base abuild build-base git curl file

# псевдо-ФС и резолвер
mkdir -p "$C/proc" "$C/sys" "$C/dev" "$C/tmp"
mount --bind /proc "$C/proc" 2>/dev/null || true
mount --bind /sys  "$C/sys"  2>/dev/null || true
mount --bind /dev  "$C/dev"  2>/dev/null || true
cp -L /etc/resolv.conf "$C/etc/resolv.conf"

# пользователь сборки
adduser -D -h /home/builder -s /bin/ash builder >/dev/null 2>&1 || chroot "$C" adduser -D -s /bin/ash builder
chroot "$C" addgroup builder abuild 2>/dev/null || true
echo 'builder ALL=(ALL) NOPASSWD: ALL' > "$C/etc/sudoers.d/builder"
chmod 440 "$C/etc/sudoers.d/builder"

# ключи подписи (без пароля — ключ лежит локально)
chroot "$C" sh -c 'su builder -c "abuild-keygen -a -n" >/dev/null 2>&1 || true'
mkdir -p "$B/build/signing"
cp "$C"/home/builder/.abuild/*.rsa "$B/build/signing/" 2>/dev/null || true
cp "$C"/home/builder/.abuild/*.rsa.pub "$B/build/signing/" 2>/dev/null || true
# публичный ключ — в доверенные и в chroot, и на хосте
cp "$C"/home/builder/.abuild/*.rsa.pub "$C/etc/apk/keys/" 2>/dev/null || true
cp "$B/build/signing/"*.rsa.pub "$B/build/apk-keys/" 2>/dev/null || true

# место под исходники и APKBUILD
mkdir -p "$C/home/builder/package/community/pipewire"
cp "$B/build/apkbuild/pipewire/"* "$C/home/builder/package/community/pipewire/"
chroot "$C" chown -R builder:builder /home/builder
mkdir -p "$C/var/cache/distfiles" && chroot "$C" chown builder:builder /var/cache/distfiles

echo "chroot готов: $C"
