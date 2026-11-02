#!/bin/bash
# РАБОЧИЙ образ: mkfs.ubifs(-x zstd) → патч DOUBLE_HASH+CRC → ubinize
set -euo pipefail
B=/home/ruslan/Загрузки/marusia/build-rootfs
SRCTREE=$B/rootfs
OUT=$B/build/rootfs-custom.ubi

# 1. копируем дерево в chroot
rm -rf $B/chroot/tmp/tree
REEXECED=1 pkexec env REEXECED=1 bash -c "cp -a $SRCTREE $B/chroot/tmp/tree"
echo "=== mkfs.ubifs 2.3.1 -x zstd ==="
chroot $B/chroot sh -c 'mkfs.ubifs -r /tmp/tree -m 2048 -e 126976 -c 1600 -x zstd -o /tmp/rootfs.ubifs' 2>&1 | tail -1

# 2. патч SB: flags |= DOUBLE_HASH + пересчёт CRC
echo "=== патч DOUBLE_HASH ==="
chroot $B/chroot python3 - $B/chroot/tmp/rootfs.ubifs $B/chroot/tmp/rootfs-patched.ubifs <<'PYEOF'
import sys, struct, zlib
src, dst = sys.argv[1], sys.argv[2]
d = bytearray(open(src,'rb').read())
flags = struct.unpack('<I', d[0x1c:0x20])[0]
print(f"flags до: {flags}")
if not flags & 4:
    struct.pack_into('<I', d, 0x1c, flags | 4)
    node_len = struct.unpack('<I', d[16:20])[0]
    crc = zlib.crc32(bytes(d[8:node_len])) ^ 0xFFFFFFFF
    struct.pack_into('<I', d, 4, crc)
print(f"flags после: {struct.unpack('<I', d[0x1c:0x20])[0]}")
open(dst,'wb').write(bytes(d))
PYEOF

# 3. ubinize на хосте (параметры NAND из лога колонки)
echo "=== ubinize ==="
cat > $B/build/ubinize.ini <<EOF
[rootfs]
mode=ubi
image=$B/chroot/tmp/rootfs-patched.ubifs
vol_id=0
vol_type=dynamic
vol_name=rootfs
vol_flags=autoresize
vol_alignment=1
EOF
ubinize -o "$OUT" -m 2048 -p 131072 $B/build/ubinize.ini 2>&1 | tail -1

echo "=== ГОТОВО: $OUT ==="
ls -la "$OUT"

# 4. проверка: супер-блок должен совпадать с авторским по flags/compr
python3 -c "
import struct
d = open('$OUT','rb').read(2*131072+4096+96)
flags = struct.unpack('<I', d[0x1c:0x20])[0]
compr = struct.unpack('<H', d[0x54:0x56])[0]
print(f'SB: flags={flags} (DOUBLE_HASH={bool(flags&4)}), compr={compr} (ZSTD)' if compr==3 else f'SB: flags={flags}, compr={compr}')
"
