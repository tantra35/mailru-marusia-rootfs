#!/bin/bash
# Добавление spotifyd (Spotify Connect) в дерево rootfs.
# Пакет: Alpine v3.24 community aarch64, собран с pulseaudio+alsa бэкендами
# (NEEDED: libpulse.so.0, libpulse-simple.so.0, libasound.so.2).
# apk add идёт с --no-scripts, поэтому пользователя создаём вручную —
# дословная реплика /etc/.pre-install пакета:
#   addgroup -S spotifyd
#   adduser -S -D -H -h /dev/null -s /sbin/nologin -G audio -g spotifyd spotifyd
set -euo pipefail
B=/home/ruslan/Загрузки/marusia/build-rootfs

echo "=== apk: spotifyd в дерево ==="
$B/build/sbin/apk.static --root "$B/rootfs" --arch aarch64 --allow-untrusted \
  --repositories-file "$B/build/repositories.txt" \
  --cache-dir "$B/build/apk-cache" --no-progress --no-scripts \
  add spotifyd

echo "=== пользователь/группа (реплика .pre-install пакета) ==="
grep -q '^spotifyd:' "$B/rootfs/etc/group"  || echo 'spotifyd:x:108:' >> "$B/rootfs/etc/group"
grep -q '^spotifyd:' "$B/rootfs/etc/passwd" || echo 'spotifyd:x:106:18:spotifyd:/dev/null:/sbin/nologin' >> "$B/rootfs/etc/passwd"
grep -q '^spotifyd:' "$B/rootfs/etc/shadow" || echo 'spotifyd:!:20618:0:99999:7:::' >> "$B/rootfs/etc/shadow"
# pulse-access — как mpd (unix-сокет PA, auth-unix по умолчанию).
grep -q '^pulse-access:.*spotifyd' "$B/rootfs/etc/group" || \
  sed -i 's/^pulse-access:.*/&,spotifyd/' "$B/rootfs/etc/group"
grep '^pulse-access' "$B/rootfs/etc/group"

echo "=== world ==="
grep -q '^spotifyd$' "$B/rootfs/etc/apk/world" || echo spotifyd >> "$B/rootfs/etc/apk/world"

echo "=== конфиг + init.d + рунлевел (из template/) ==="
install -m 644 "$B/template/etc/spotifyd.conf" "$B/rootfs/etc/spotifyd.conf"
install -m 755 "$B/template/etc/init.d/spotifyd" "$B/rootfs/etc/init.d/spotifyd"
ln -sf /etc/init.d/spotifyd "$B/rootfs/etc/runlevels/default/spotifyd"
ls -la "$B/rootfs/etc/runlevels/default/" | grep spotifyd

chown -R ruslan:ruslan "$B/rootfs/etc"
echo "=== ГОТОВО ==="
