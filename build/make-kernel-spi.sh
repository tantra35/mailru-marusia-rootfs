#!/usr/bin/env bash
# Сборка БОЕВОГО ядра с BSP-патчем spicc (SMC=0 + XCH, unprepare без teardown)
# для прошивки на живую колонку: НИКАКИХ initramfs и USB_G_SERIAL — конфиг
# чистый marusia_mini_defconfig + только патч драйвера. Версия совпадает с
# модулями rootfs (6.18.56-vk-mini-a113x) → rootfs не трогается, flasher
# item 3 с пустым ROOTFS_UBI пишет только ядро+dtb+envs.
#
# Запуск: ./build/make-kernel-spi.sh   → build/Image-spi-live
# Конфиг: $B/config_alpine (родной конфиг автора, из «a0 готово»/z0 for dev)
set -euo pipefail

B="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KSRC="${KSRC:-$B/../../kernel-src}"
ALPINE_CFG="${ALPINE_CFG:-$B/config_alpine}"
TEXTOFF=0x1080000

grep -q "SMC auto-DMA живёт только первую цепочку" "$KSRC/drivers/spi/spi-meson-spicc.c" ||
	{ echo "ВНИМАНИЕ: патч BSP-дисциплины в spi-meson-spicc.c не найден!" >&2; exit 1; }
command -v aarch64-linux-gnu-gcc >/dev/null ||
	{ echo "нет aarch64-linux-gnu-gcc" >&2; exit 1; }

cd "$KSRC"
# родной конфиг автора (config_alpine, из «a0 готово»/z0 for dev) — он уже
# содержит MODVERSIONS=y, LOCALVERSION_AUTO=n и весь =m-набор: wifi (W1_AML),
# BT-стек, zram, crypto-CE, watchdog, efuse. Никаких докруток поверх.
cp "$ALPINE_CFG" .config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig > /dev/null

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION= -j"$(nproc)" Image modules
# LOCALVERSION= (пустой, но SET) обязателен: без него setlocalversion лепит
# "+" к релизу за незакоммиченные dwc2/dwc3 debug-диффы → vermagic не совпадёт

grep -q '^#define UTS_RELEASE "6.18.56-vk-mini-a113x"$' include/generated/utsrelease.h ||
	{ echo "UTS_RELEASE != 6.18.56-vk-mini-a113x:" >&2; cat include/generated/utsrelease.h >&2; exit 1; }

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

cp "$KSRC/arch/arm64/boot/Image" "$B/Image-spi-live"
echo "=== ГОТОВО: $B/Image-spi-live ($(stat -c%s "$B/Image-spi-live") байт) ==="
echo "=== деплой (только ядро+dtb+envs, рутфс нет):"
echo "===   IMAGE=$B/Image-spi-live ROOTFS_UBI=/nonexistent ./flasher.sh 3 ==="
