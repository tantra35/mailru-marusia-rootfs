#!/bin/bash
# Синхронизация пользователей/конфигов mpd+upmpdcli из живой системы в дерево
set -euo pipefail
B=/home/ruslan/Загрузки/marusia/build-rootfs

# passwd
grep -q '^mpd:' "$B/rootfs/etc/passwd" || echo 'mpd:x:103:18:Music Player Daemon:/var/lib/mpd:/sbin/nologin' >> "$B/rootfs/etc/passwd"
grep -q '^upmpdcli:' "$B/rootfs/etc/passwd" || echo 'upmpdcli:x:105:105:upmpdcli daemon:/var/lib/upmpdcli:/sbin/nologin' >> "$B/rootfs/etc/passwd"
# shadow
grep -q '^mpd:' "$B/rootfs/etc/shadow" || echo 'mpd:!:20618:0:99999:7:::' >> "$B/rootfs/etc/shadow"
grep -q '^upmpdcli:' "$B/rootfs/etc/shadow" || echo 'upmpdcli:!:20618:0:99999:7:::' >> "$B/rootfs/etc/shadow"
# group (без дублей)
grep -q '^mpd:' "$B/rootfs/etc/group" || echo 'mpd:x:104:' >> "$B/rootfs/etc/group"
grep -q '^upmpdcli:' "$B/rootfs/etc/group" || echo 'upmpdcli:x:105:upmpdcli' >> "$B/rootfs/etc/group"

# каталоги
mkdir -p "$B/rootfs/var/lib/mpd/playlists" "$B/rootfs/var/lib/mpd/music" \
         "$B/rootfs/var/lib/upmpdcli" "$B/rootfs/media" "$B/rootfs/run/mpd"

# mpd.conf (актуальная версия без дубля database)
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
EOF
cp "$B/rootfs/etc/mpd.conf" "$B/template/etc/mpd.conf"

# пользователи/группы в шаблоне (для будущих сборок с нуля)
for f in "$B/template/etc/passwd" "$B/template/etc/shadow" "$B/template/etc/group"; do
  touch "$f"
done
grep -q '^mpd:' "$B/template/etc/passwd" || echo 'mpd:x:103:18:Music Player Daemon:/var/lib/mpd:/sbin/nologin' >> "$B/template/etc/passwd"
grep -q '^upmpdcli:' "$B/template/etc/passwd" || echo 'upmpdcli:x:105:105:upmpdcli daemon:/var/lib/upmpdcli:/sbin/nologin' >> "$B/template/etc/passwd"
grep -q '^mpd:' "$B/template/etc/shadow" || echo 'mpd:!:20618:0:99999:7:::' >> "$B/template/etc/shadow"
grep -q '^upmpdcli:' "$B/template/etc/shadow" || echo 'upmpdcli:!:20618:0:99999:7:::' >> "$B/template/etc/shadow"
grep -q '^mpd:' "$B/template/etc/group" || echo 'mpd:x:104:' >> "$B/template/etc/group"
grep -q '^upmpdcli:' "$B/template/etc/group" || echo 'upmpdcli:x:105:upmpdcli' >> "$B/template/etc/group"

chown -R ruslan:ruslan "$B/rootfs/etc" "$B/template" 2>/dev/null || true
echo "=== контроль ==="
grep -cE '^(mpd|upmpdcli)' "$B/rootfs/etc/passwd" "$B/rootfs/etc/shadow" "$B/rootfs/etc/group"
ls "$B/rootfs/etc/mpd.conf" && head -3 "$B/rootfs/etc/mpd.conf"
