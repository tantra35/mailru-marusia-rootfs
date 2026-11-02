#!/usr/bin/env bash
# Догоняющий этап: пользователь, ключи, APKBUILD
set -euo pipefail
B=/home/ruslan/Загрузки/marusia/build-rootfs
C=$B/chroot

chroot "$C" adduser -D -s /bin/ash builder 2>/dev/null || echo "(builder уже есть)"
chroot "$C" addgroup builder abuild 2>/dev/null || echo "(в группе abuild уже есть)"

# ключи подписи (без пароля)
chroot "$C" su builder -c "abuild-keygen -a -n" 2>/dev/null | tail -1 || true
mkdir -p "$B/build/signing"
cp "$C"/home/builder/.abuild/*.rsa "$B/build/signing/"
cp "$C"/home/builder/.abuild/*.rsa.pub "$B/build/signing/"
cp "$B/build/signing/"*.rsa.pub "$C/etc/apk/keys/"
cp "$B/build/signing/"*.rsa.pub "$B/build/apk-keys/"

# APKBUILD
mkdir -p "$C/home/builder/package/community/pipewire"
cp "$B/build/apkbuild/pipewire/"* "$C/home/builder/package/community/pipewire/"
chroot "$C" chown -R builder:builder /home/builder
mkdir -p "$C/var/cache/distfiles"
chroot "$C" chown builder:builder /var/cache/distfiles

echo "chroot готов"
chroot "$C" su builder -c "abuild --version && ls ~/package/community/pipewire/"
