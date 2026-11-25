#!/usr/bin/env bash
# Сборка Image-ramrootfs-spi: ядро с ПАТЧЕННЫМ spi-meson-spicc (BSP-дисциплина
# DMA: SMC=0, XCH-старт, без per-message teardown) и вшитым initramfs со
# spi-test. Цель — multi-кадровый цикл кольца БЕЗ rebind из RAM, флеш не пишется.
#
# Схема скопирована с make-ramrootfs-kernel.sh (сканер PEB): вендорский booti
# НЕ принимает отдельный initrd — initramfs вшит через CONFIG_INITRAMFS_SOURCE.
#
# Запуск: SPI_TEST=/tmp/spi-test-arm64 ./build/make-ramrootfs-spi.sh
# Результат: build/Image-ramrootfs-spi (text_offset=0x1080000).
# Загрузка: sudo ~/Загрузки/marusia/ram-spi-test.sh  (= flasher.sh, пункт 9,
# переменная SPI_IMAGE; пункт 5 и SCAN_IMAGE — это СКАНЕР PEB, не путать).
set -euo pipefail

B="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TREE="${TREE:-$B/../rootfs}"                    # aarch64-дерево: busybox, musl
KSRC="${KSRC:-$B/../../kernel-src}"             # исходники ядра (с патчем spicc)
SPI_TEST="${SPI_TEST:-/tmp/spi-test-arm64}"     # статический aarch64 Go-бинарь
DUR="${DUR:-30}"                                # секунд цикла
TEXTOFF=0x1080000

GEN="$B/gen_init_cpio"
[ -x "$GEN" ] || gcc -O2 -o "$GEN" "$KSRC/usr/gen_init_cpio.c"
STAGE="$B/initramfs-spi"

[ -x "$TREE/bin/busybox" ] || { echo "нет $TREE/bin/busybox" >&2; exit 1; }
[ -x "$SPI_TEST" ] || { echo "нет $SPI_TEST (собери: cd spi-test && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build ...)" >&2; exit 1; }
file "$SPI_TEST" | grep -q aarch64 || { echo "$SPI_TEST не aarch64" >&2; exit 1; }
[ -f "$B/initramfs-init-spi" ] || { echo "нет $B/initramfs-init-spi" >&2; exit 1; }
grep -q "SMC auto-DMA живёт только первую цепочку" "$KSRC/drivers/spi/spi-meson-spicc.c" ||
	{ echo "ВНИМАНИЕ: патч BSP-дисциплины в spi-meson-spicc.c не найден!" >&2; exit 1; }
command -v aarch64-linux-gnu-gcc >/dev/null ||
	{ echo "нет aarch64-linux-gnu-gcc" >&2; exit 1; }

# 1) staging initramfs
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/lib" "$STAGE/dev" "$STAGE/proc" "$STAGE/sys" "$STAGE/tmp"
cp "$TREE/bin/busybox" "$STAGE/bin/busybox"
cp -L "$TREE/lib/ld-musl-aarch64.so.1" "$STAGE/lib/"
cp "$B/initramfs-init-spi" "$STAGE/init"
cp "$SPI_TEST" "$STAGE/bin/spi-test"
cp "$B/initramfs-panel" "$STAGE/panel"
chmod 755 "$STAGE/init" "$STAGE/bin/busybox" "$STAGE/bin/spi-test" "$STAGE/panel"
ln -s busybox "$STAGE/bin/sh"

{
	echo "dir /bin 0755 0 0"
	echo "file /bin/busybox $STAGE/bin/busybox 0755 0 0"
	echo "slink /bin/sh /bin/busybox 0777 0 0"
	echo "file /bin/spi-test $STAGE/bin/spi-test 0755 0 0"
	for a in mount mkdir ls sleep tee head cat sed date grep uname ln rmdir mknod; do
		echo "slink /bin/$a /bin/busybox 0777 0 0"
	done
	# readlink — критичен: проверка привязки spidev в init (FATAL 8822 из-за
	# его отсутствия ловлено 2026-11-14); dmesg/tail — для spi_diag
	for a in readlink dmesg tail; do
		echo "slink /bin/$a /bin/busybox 0777 0 0"
	done
	echo "dir /lib 0755 0 0"
	echo "file /lib/ld-musl-aarch64.so.1 $STAGE/lib/ld-musl-aarch64.so.1 0755 0 0"
	echo "dir /dev 0755 0 0"
	echo "nod /dev/console 0600 0 0 c 5 1"
	echo "nod /dev/null 0666 0 0 c 1 3"
	echo "nod /dev/tty 0620 0 0 c 5 0"
	echo "dir /proc 0755 0 0"
	echo "dir /sys 0755 0 0"
	echo "dir /tmp 0755 0 0"
	echo "file /init $STAGE/init 0755 0 0"
	echo "file /bin/panel $STAGE/panel 0755 0 0"
} | "$GEN" - > "$KSRC/initramfs-spi.cpio"

# 2) ядро: defconfig автора + наш initramfs + USB g_serial консоль
cd "$KSRC"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- marusia_mini_defconfig > /dev/null
scripts/config --file .config --set-str INITRAMFS_SOURCE "initramfs-spi.cpio"
scripts/config --file .config -e USB_G_SERIAL
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig > /dev/null
grep -q '^CONFIG_INITRAMFS_SOURCE="initramfs-spi.cpio"$' .config ||
	{ echo "INITRAMFS_SOURCE не применился" >&2; exit 1; }

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image

# 3) text_offset=0x1080000 (Linux пишет 0; вендорский booti грузит по
#    SDRAM_BASE + text_offset, SDRAM_BASE здесь 0)
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

cp "$KSRC/arch/arm64/boot/Image" "$B/Image-ramrootfs-spi"
echo "=== ГОТОВО: $B/Image-ramrootfs-spi ($(stat -c%s "$B/Image-ramrootfs-spi") байт) ==="
echo "=== загрузка: RECOVERY=$B/Image-ramrootfs-spi sudo ./flasher.sh 5 ==="
