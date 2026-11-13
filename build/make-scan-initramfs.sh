#!/usr/bin/env bash
# Сборка initramfs-сканера плохих PEB: build/scan-initramfs.cpio.gz (~1.6 МиБ).
#
# Состав: busybox + ld-musl-aarch64 из дерева rootfs/ + /init + /scan
# (= build/scan-bad-pebs). Ядро грузит это в RAM (RD_GZIP=y в defconfig),
# /init монтирует proc/sys/dev и гонит скан в UART. NAND не пишется.
#
# Результат подхватывает flasher.sh (пункт «Скан плохих PEB»):
#   SCINITRD=путь ./flasher.sh   (по умолчанию $HERE/scan-initramfs.cpio.gz)
# Передобавить после обновления busybox в дереве: ./build/make-scan-initramfs.sh
#
# Выход: ./build/make-scan-initramfs.sh [путь-результата]
set -euo pipefail

B="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TREE="${TREE:-$B/../rootfs}"   # aarch64-дерево, откуда берутся busybox и musl
TREE="$(cd -- "$TREE" && pwd)" # физический путь: qemu -L не ресолвит ".."
OUT="${1:-$B/scan-initramfs.cpio.gz}"
STAGE="$B/initramfs-scan"

[ -x "$TREE/bin/busybox" ] || {
	echo "нет $TREE/bin/busybox — сначала собери дерево (./build-rootfs.sh apk-build)" >&2
	exit 1
}

rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/lib" "$STAGE/dev" "$STAGE/proc" "$STAGE/sys" "$STAGE/tmp" "$STAGE/config"
cp "$TREE/bin/busybox" "$STAGE/bin/busybox"
cp -L "$TREE/lib/ld-musl-aarch64.so.1" "$STAGE/lib/"
cp "$B/initramfs-init" "$STAGE/init"
cp "$B/scan-bad-pebs" "$STAGE/scan"
chmod 755 "$STAGE/init" "$STAGE/scan" "$STAGE/bin/busybox"
ln -s busybox "$STAGE/bin/sh"

# -R: в архиве uid/gid root, а не сборщика — внутри initramfs всё равно root,
# но пусть архив не намекает на чужие uid.
(cd "$STAGE" && find . -print0 | cpio --null -o -H newc -R 0:0 --quiet | gzip -9) > "$OUT"

echo "=== ГОТОВО: $OUT ($(stat -c%s "$OUT") байт) ==="
echo "Аплеты в busybox (nanddump должен быть):"
# Отдельно от pipefail: qemu выходит с ненулевым rc даже при успешном --list
applets="$(qemu-aarch64 -L "$TREE" "$STAGE/bin/busybox" --list 2>/dev/null || true)"
grep -qx nanddump <<< "$applets" ||
	echo "  ВНИМАНИЕ: nanddump в этом busybox не найден, скан работать не будет!"
