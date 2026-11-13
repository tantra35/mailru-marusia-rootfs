#!/usr/bin/env bash
# Сборка Image-ramrootfs: ядро со ВШИТЫМ initramfs-сканером плохих PEB.
#
# Почему вшитый: вендорский booti НЕ принимает отдельный initrd (проверено
# слепым перебором 2026-11-14: с initrd-аргументом ядро не стартует, без —
# стартует). Как у автора: CONFIG_INITRAMFS_SOURCE + marusia_mini_ram.config.
#
# Результат: build/Image-ramrootfs (text_offset=0x1080000, как у автора —
# booti кладёт образ ровно в KERNEL_ADDR). Пункт 5 flasher.sh.
#
# Запуск: ./build/make-ramrootfs-kernel.sh
# Тулчейн: gcc-aarch64-linux-gnu (apt). Исходники: ~/Загрузки/marusia/kernel-src
set -euo pipefail

B="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TREE="${TREE:-$B/../rootfs}"                    # aarch64-дерево: busybox, musl
KSRC="${KSRC:-$B/../../kernel-src}"             # исходники ядра автора
TEXTOFF=0x1080000                               # как в fw_alpine/Image автора
STAGE="$B/initramfs-scan"

[ -x "$TREE/bin/busybox" ] || {
	echo "нет $TREE/bin/busybox — сначала собери дерево (./build-rootfs.sh apk-build)" >&2
	exit 1
}
[ -f "$KSRC/Makefile" ] || {
	echo "нет исходников ядра в $KSRC — git clone --depth 1 comp18man/vk-capsula-mini-a113x-linux" >&2
	exit 1
}
command -v aarch64-linux-gnu-gcc >/dev/null ||
	{ echo "нет aarch64-linux-gnu-gcc: apt install gcc-aarch64-linux-gnu flex bison libssl-dev" >&2; exit 1; }

# 1) initramfs-каталог: busybox+musl+init+scan+config
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/lib" "$STAGE/dev" "$STAGE/proc" "$STAGE/sys" "$STAGE/tmp" "$STAGE/config"
cp "$TREE/bin/busybox" "$STAGE/bin/busybox"
cp -L "$TREE/lib/ld-musl-aarch64.so.1" "$STAGE/lib/"
cp "$B/initramfs-init" "$STAGE/init"
cp "$B/scan-bad-pebs" "$STAGE/scan"
chmod 755 "$STAGE/init" "$STAGE/scan" "$STAGE/bin/busybox"
ln -s busybox "$STAGE/bin/sh"

# 2) несжатый cpio в корень исходников (INITRAMFS_SOURCE относительный)
(cd "$STAGE" && find . -print0 | cpio --null -o -H newc -R 0:0 --quiet) \
	> "$KSRC/initramfs.cpio"

# 3) ядро: defconfig автора + ram-фрагмент
cd "$KSRC"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- marusia_mini_defconfig > /dev/null
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- marusia_mini_ram.config > /dev/null
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig > /dev/null
grep -q '^CONFIG_INITRAMFS_SOURCE="initramfs.cpio"$' .config ||
	{ echo "INITRAMFS_SOURCE не применился — смотри .config" >&2; exit 1; }

# 4) сборка Image
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image

# 5) text_offset: Linux пишет 0, а вендорский booti грузит образ по
#    SDRAM_BASE + text_offset; SDRAM_BASE здесь 0 → без патча образ уезжает
#    в ноль и booti кричит "Bad Linux ARM64 Image magic!". У автора 0x1080000.
python3 - "$KSRC/arch/arm64/boot/Image" "$TEXTOFF" <<'EOF'
import struct, sys
p, off = sys.argv[1], int(sys.argv[2], 16)
d = bytearray(open(p, 'rb').read(64))
assert d[56:60] == b'ARM\x64', 'это не arm64 Image'
struct.pack_into('<Q', d, 8, off)
f = open(p, 'r+b')
f.write(bytes(d))
f.close()
EOF

cp "$KSRC/arch/arm64/boot/Image" "$B/../Image-ramrootfs"
echo "=== ГОТОВО: $B/../Image-ramrootfs ($(stat -c%s "$B/../Image-ramrootfs") байт) ==="
