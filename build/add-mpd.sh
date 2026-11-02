#!/bin/bash
# Добавление mpd+upmpdcli в дерево и пересборка образа
set -euo pipefail
B=/home/ruslan/Загрузки/marusia/build-rootfs

echo "=== apk: mpd + upmpdcli в дерево ==="
$B/build/sbin/apk.static --root "$B/rootfs" --arch aarch64 --allow-untrusted \
  --repositories-file "$B/build/repositories.txt" \
  --cache-dir "$B/build/apk-cache" --no-progress --no-scripts \
  add mpd upmpdcli 2>&1 | tail -2

echo "=== world ==="
grep -q '^mpd$' "$B/rootfs/etc/apk/world" || echo mpd >> "$B/rootfs/etc/apk/world"
grep -q '^upmpdcli$' "$B/rootfs/etc/apk/world" || echo upmpdcli >> "$B/rootfs/etc/apk/world"

echo "=== mpd.conf ==="
cat > "$B/rootfs/etc/mpd.conf" <<'EOF'
music_directory	"/media"
playlist_directory	"/var/lib/mpd/playlists"
db_file			"/var/lib/mpd/database"
log_file		"/var/lib/mpd/log"
pid_file		"/run/mpd/pid"
state_file		"/var/lib/mpd/state"
user			"mpd"
bind_to_address		"0.0.0.0"
port			"6600"

audio_output {
	type		"pulse"
	name		"Marusia PulseAudio"
}

database {
	plugin		"simple"
	path		"/var/lib/mpd/database"
}
EOF

echo "=== группы: mpd в pulse-access ==="
sed -i 's/^pulse-access:.*/pulse-access:x:107:root,mpd/' "$B/rootfs/etc/group"
grep '^pulse-access' "$B/rootfs/etc/group"

echo "=== runlevels ==="
ln -sf /etc/init.d/mpd "$B/rootfs/etc/runlevels/default/mpd"
ln -sf /etc/init.d/upmpdcli "$B/rootfs/etc/runlevels/default/upmpdcli" 2>/dev/null || \
  ln -sf /etc/init.d/upmpdmpd "$B/rootfs/etc/runlevels/default/upmpdcli" 2>/dev/null || true
ls "$B/rootfs/etc/init.d/" | grep -E 'mpd'
ls -la "$B/rootfs/etc/runlevels/default/" | grep -E 'mpd'

mkdir -p "$B/rootfs/media"
chown -R ruslan:rusman "$B/rootfs/etc" 2>/dev/null || chown -R ruslan:ruslan "$B/rootfs/etc"

echo "=== ПЕРЕСБОРКА ==="
bash "$B/build/rebuild.sh" 2>&1 | tail -6
