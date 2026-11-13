#!/bin/bash
# Пересборка образа: дерево → mkfs(-x zstd, БЕЗ патчей) → ubinize → обход плохих PEB.
# Список плохих PEB: путь в $BAD_PEB_FILE (по умолчанию $B/build/bad-pebs-shtab.txt —
# штабовая колонка). Файл снимается scan-bad-pebs'ом с конкретной платы:
# по одному PEB на строку, # - комментарий. Нет файла/пустой - образ без дыр.
# Контент каждого плохого PEB переносится в хвост образа (полный своп PEB целиком,
# CRC не пересчитываются), на его месте остаётся свободная пустышка (EC без VID).
# flasher.sh по тому же файлу (та же BAD_PEB_FILE) строит сегментную запись с разрывами.
set -euo pipefail
B=/home/ruslan/Загрузки/marusia/build-rootfs
BADPEBS="${BAD_PEB_FILE:-$B/build/bad-pebs-shtab.txt}"

rm -rf "$B/chroot/tmp/tree"
cp -a "$B/rootfs" "$B/chroot/tmp/tree"

echo "=== mkfs.ubifs -x zstd ==="
chroot "$B/chroot" mkfs.ubifs -r /tmp/tree -m 2048 -e 126976 -c 1600 -x zstd -o /tmp/rootfs.ubifs 2>&1 | tail -1

cat > "$B/chroot/tmp/ubinize.ini" <<INI
[rootfs]
mode=ubi
image=/tmp/rootfs.ubifs
vol_id=0
vol_type=dynamic
vol_name=rootfs
vol_flags=autoresize
vol_alignment=1
INI

echo "=== ubinize ==="
chroot "$B/chroot" ubinize -o /tmp/rootfs-new.ubi -m 2048 -p 131072 /tmp/ubinize.ini 2>&1 | tail -1
cp "$B/chroot/tmp/rootfs-new.ubi" "$B/build/rootfs-custom.ubi"

echo "=== обход плохих PEB ($BADPEBS) ==="
if [ -s "$BADPEBS" ]; then
python3 - "$B/build/rootfs-custom.ubi" "$BADPEBS" <<'PYEOF'
import sys, struct, zlib
PEB = 131072
p, badf = sys.argv[1], sys.argv[2]
bads = sorted({int(x) for x in open(badf) if x.strip() and not x.strip().startswith('#')})
d = bytearray(open(p, 'rb').read())
total = len(d) // PEB
bad = [b for b in bads if b < total]
skipped = [b for b in bads if b >= total]
if skipped:
    print(f'вне образа (пропущены): {skipped}')

# пустышка: валидный EC-заголовок (наш image_seq), VID отсутствует ->
# UBI при attach считает такой PEB свободным, проверок диапазона lnum нет
def make_free_peb(ec):
    peb = bytearray(PEB)
    h = bytearray(64)
    h[0:4] = b'UBI#'
    h[4] = 1
    struct.pack_into('>Q', h, 8, 1)
    struct.pack_into('>I', h, 16, 2048)
    struct.pack_into('>I', h, 20, 4096)
    h[24:28] = ec
    struct.pack_into('>I', h, 60, zlib.crc32(bytes(h[:60])) ^ 0xFFFFFFFF)
    peb[0:64] = h
    return peb

ec0 = bytes(d[0:64])[24:28]  # image_seq из первого EC-заголовка
d.extend(b''.join(make_free_peb(ec0) for _ in bad))

tail = len(d) - PEB * len(bad)
for i, b in enumerate(bad):
    bs, ts = b * PEB, tail + i * PEB
    d[bs:bs+PEB], d[ts:ts+PEB] = d[ts:ts+PEB], d[bs:bs+PEB]

open(p, 'wb').write(bytes(d))
tail_pebs = list(range(tail // PEB, tail // PEB + len(bad)))
print(f'плохие PEB {bad} -> хвост {tail_pebs}; образ {len(d)//PEB} PEB')
PYEOF
else
echo "список пуст или отсутствует - собираю образ без дыр"
fi

chown ruslan:ruslan "$B/build/rootfs-custom.ubi"
echo "=== ГОТОВО: $B/build/rootfs-custom.ubi ==="
ls -la "$B/build/rootfs-custom.ubi"
