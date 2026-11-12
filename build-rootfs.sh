#!/usr/bin/env bash
#
# Свой рутфс для VK Mini A113X (Alpine 3.24.1 aarch64).
#
# Архитектура:
#   template/       — ШАБЛОН: кастомные скрипты, конфиги, runlevels, модули ядра,
#                     фирмвари (правишь руками — это твой источник)
#   packages.list   — ШАБЛОН: список apk-пакетов (мир эталонного образа)
#   rootfs/         — эталон: распакованный заводской образ (источник ключей apk)
#   rootfs-apk/     — ПРОДУКТ: собирается apk-build'ом, можно стирать и пересобирать
#   build/          — тулза apk.static, кэш пакетов, готовые .ubi
#
# Пайплайн: apk-build (apk init + мир + оверлей шаблона) → clean → build
#
#   ./build-rootfs.sh extract     — разобрать заводской .ubi в rootfs/ (эталон)
#   ./build-rootfs.sh apk-build   — пересобрать rootfs-apk/ с нуля из template/
#   ./build-rootfs.sh clean       — доочистка: отчёт; с --apply — удалить
#   ./build-rootfs.sh build       — упаковать ROOTFS=dir в .ubi
#
# Права: скрипт сам поднимает себя через sudo — один пароль на запуск.
#
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

CMD="${1:-}"
case "$CMD" in
extract|apk-build|clean|build) ;;
*)
	echo "Использование: $0 extract|apk-build|clean|build"
	echo "  apk-build  пересобрать rootfs-apk/ с нуля: apk init + packages.list + template/"
	echo "  clean      доочистка: отчёт; с --apply — удалить (каталог: 2-й арг)"
	echo "  build      упаковать ROOTFS=dir в .ubi"
	exit 1
	;;
esac

# --- само-элевация: один пароль на весь прогон -------------------------
# (отчёт clean без --apply работает и без root)
NEED_ROOT=1
[ "$CMD" = "clean" ] && [ "${3:-}" != "--apply" ] && NEED_ROOT=0
if [ "$(id -u)" != 0 ] && [ "$NEED_ROOT" = 1 ] && [ "${REEXECED:-}" != 1 ]; then
	exec env REEXECED=1 sudo "$0" "$@"
fi

TEMPLATE="$HERE/template"
PACKAGES="$HERE/packages.list"
ROOTFS_APK="$HERE/rootfs-apk"
BUILD="$HERE/build"
ROOTFS="${ROOTFS:-$HERE/rootfs}"          # эталон: источник ключей apk и .ubi для extract
OUT_UBI="${OUT_UBI:-}"

# Геометрия NAND этой платы — из загрузочного лога (marusia-serial.log):
# PEB 131072, min I/O 2048, LEB = PEB - 2*min_io = 126976, sub-page = страница.
MIN_IO=2048
PEB=131072
LEB=$((PEB - 2 * MIN_IO))
MAX_LEB=1600              # контент ~770 LEB; регион 0x02c00000..0x10000000 вмещает 1731
UBI_REGION=$((0x10000000 - 0x02c00000))   # 212 МиБ под ubi у flasher.sh

APK_URL_BASE="https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64"
APK_VER="apk-tools-static-3.0.8-r0.apk"
CLEAN_KEEP_LOCALES="${CLEAN_KEEP_LOCALES:-ru en}"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "не хватает: $1 ($2)"; }
du_k() { du -xsk "$1" 2>/dev/null | cut -f1 || true; }

ensure_apk_tool() {
	mkdir -p "$BUILD" "$BUILD/apk-keys" "$BUILD/apk-cache"
	if [ ! -x "$BUILD/sbin/apk.static" ]; then
		need curl "apt install curl"
		curl -sL --max-time 120 "$APK_URL_BASE/$APK_VER" -o "$BUILD/apk-tools-static.apk"
		tar -xzf "$BUILD/apk-tools-static.apk" -C "$BUILD" sbin/apk.static
		chmod +x "$BUILD/sbin/apk.static"
	fi
	# Ключи: из эталона; если эталона нет — берём уже подготовленные в build/
	if [ ! -d "$BUILD/apk-keys" ] || [ -z "$(ls -A "$BUILD/apk-keys")" ]; then
		[ -d "$ROOTFS/etc/apk/keys" ] || die "нет ключей: нужен эталон $ROOTFS или $BUILD/apk-keys"
		mkdir -p "$BUILD/apk-keys"
		cp -a "$ROOTFS/etc/apk/keys/." "$BUILD/apk-keys/"
	fi
	if [ ! -s "$BUILD/repositories.txt" ]; then
		printf '%s\n' \
			'https://dl-cdn.alpinelinux.org/alpine/v3.24/main' \
			'https://dl-cdn.alpinelinux.org/alpine/v3.24/community' \
			> "$BUILD/repositories.txt"
	fi
}

# ------------------------------------------------------------------ extract
cmd_extract() {
	[ -f "$ROOTFS/../fw_alpine/alpine3.24.1_rootfs.ubi" ] || die "нет заводского образа"
	[ ! -d "$ROOTFS" ] || die "$ROOTFS уже существует. Удалите и разберите заново."
	need ubireader_extract_files "pip install ubi_reader"

	# Разборка под root: иначе ubireader не создаст узлы /dev.
	ubireader_extract_files "$ROOTFS/../fw_alpine/alpine3.24.1_rootfs.ubi" -o "$BUILD/extract"
	mv "$BUILD"/extract/*/rootfs "$ROOTFS"
	rm -rf "$BUILD/extract"
	chown -R "$(id -u):$(id -g)" "$ROOTFS"

	echo
	echo "Разобрано в $ROOTFS (эталон)."
}

# -------------------------------------------------- apk-build: продукт с нуля
overlay_template() {
	local NEW="$ROOTFS_APK" item
	# Оверлей шаблона поверх свежего apk-дерева.
	# ВАЖНО: template/usr содержит только local/, template/lib — только modules
	# и firmware/aml, поэтому верхние каталоги НЕЛЬЗЯ заменять целиком —
	# только сливать содержимое. Замена целиком допустима для:
	#   usr/local, lib/modules, etc/runlevels (apk их сам не наполняет).
	rm -rf "$NEW/usr/local" "$NEW/lib/modules" "$NEW/etc/runlevels"

	# 1) побайтовая копия файлов, mkdir -p для каталогов — слияние без сюрпризов
	local p
	while IFS= read -r p; do
		p="${p#./}"
		if [ -d "$TEMPLATE/$p" ]; then
			mkdir -p "$NEW/$p"
		elif [ -f "$TEMPLATE/$p" ] || [ -L "$TEMPLATE/$p" ]; then
			cp -af "$TEMPLATE/$p" "$NEW/$p"
		fi
	done < <(cd "$TEMPLATE" && find . -mindepth 1)

	# 2) каталоги-замены целиком
	cp -aT "$TEMPLATE/usr/local" "$NEW/usr/local"
	cp -aT "$TEMPLATE/lib/modules" "$NEW/lib/modules"
	cp -aT "$TEMPLATE/lib/firmware/aml" "$NEW/lib/firmware/aml"
	cp -aT "$TEMPLATE/etc/runlevels" "$NEW/etc/runlevels"

	# 3) Узлы /dev (apk их не создаёт, а ubifs-образ должен нести)
	rm -f "$NEW/dev/console" "$NEW/dev/null" "$NEW/dev/kmsg"
	mknod -m 600 "$NEW/dev/console" c 5 1
	mknod -m 666 "$NEW/dev/null"    c 1 3
	mknod -m 600 "$NEW/dev/kmsg"    c 1 11

	# 4) UART-фикс: root-вход по физическому UART
	grep -qx 'ttyAML0' "$NEW/etc/securetty" || echo ttyAML0 >> "$NEW/etc/securetty"
}

cmd_apk_build() {
	[ -f "$PACKAGES" ] || die "нет $PACKAGES (список пакетов мира)"
	[ -d "$TEMPLATE" ] || die "нет шаблона $TEMPLATE"
	ensure_apk_tool

	if [ -d "$ROOTFS_APK" ]; then
		echo "удаляю старый $ROOTFS_APK..."
		rm -rf "$ROOTFS_APK"
	fi
	mkdir -p "$ROOTFS_APK"

	echo "ставлю мир ($(wc -w < "$PACKAGES") пакетов)..."
	# --allow-untrusted: gl-stub подписан своим ключом (не альпийским)
	"$BUILD/sbin/apk.static" --root "$ROOTFS_APK" --initdb --arch aarch64 --allow-untrusted \
		--keys-dir "$BUILD/apk-keys" --repositories-file "$BUILD/repositories.txt" \
		--cache-dir "$BUILD/apk-cache" --no-progress --clean-protected \
		add $(cat "$PACKAGES")

	# Кастомные apks (pipewire r101) больше не ставятся: выбран pulseaudio
	# вместо pipewire-стека. custom-repo/ оставлен как архив и задел.

	# mpd + upmpdcli: DLNA-рендерер (mpd собран без ffmpeg, выход -> pulse tcp:4713)
	if ls "$BUILD"/custom-repo/aarch64/mpd-0*.apk >/dev/null 2>&1; then
		echo "ставлю mpd..."
		"$BUILD/sbin/apk.static" --root "$ROOTFS_APK" --arch aarch64 --allow-untrusted \
			--keys-dir "$BUILD/apk-keys" --repositories-file "$BUILD/repositories.txt" \
			--cache-dir "$BUILD/apk-cache" --no-progress \
			add \
				"$BUILD"/custom-repo/aarch64/mpd-0*.apk \
				"$BUILD"/custom-repo/aarch64/mpd-openrc-*.apk
	fi

	echo "накатываю шаблон..."
	overlay_template

	# Продукт отдаём пользователю на осмотр; build вернёт root перед упаковкой.
	chown -R "$(id -u):$(id -g)" "$ROOTFS_APK"

	echo
	echo "Собрано в $ROOTFS_APK ($(du_k "$ROOTFS_APK" | awk '{print int($1/1024)}') МиБ)"
	echo "Дальше:"
	echo "  $0 clean $ROOTFS_APK --apply          # доочистка"
	echo "  ROOTFS=$ROOTFS_APK $0 build           # упаковка в .ubi"
}

# -------------------------------------------------------------------- clean
cmd_clean() {
	local dir="${2:-$ROOTFS_APK}"
	local apply=0
	[ "${3:-}" = "--apply" ] && apply=1
	[ -d "$dir" ] || die "нет $dir"

	local before after
	before=$(du_k "$dir")

	local rm_paths=()
	rm_paths+=("$dir/usr/share/man" "$dir/usr/share/doc" "$dir/usr/share/bash-completion")
	if [ -d "$dir/usr/share/locale" ]; then
		local l
		for l in "$dir"/usr/share/locale/*; do
			[ -d "$l" ] || continue
			case " $CLEAN_KEEP_LOCALES " in
			*" $(basename "$l") "*) ;;
			*) rm_paths+=("$l") ;;
			esac
		done
	fi
	if [ -d "$dir/usr/share/zoneinfo" ]; then
		local z
		for z in "$dir"/usr/share/zoneinfo/*; do
			[ -d "$z" ] || continue
			case "$(basename "$z")" in
			Europe|America|Asia|right|posix) ;;
			*) rm_paths+=("$z") ;;
			esac
		done
	fi
	local la
	while IFS= read -r la; do rm_paths+=("$la"); done \
		< <(find "$dir" -name '*.la' 2>/dev/null)

	local p sum=0
	for p in "${rm_paths[@]}"; do
		[ -e "$p" ] || continue
		sum=$((sum + $(du_k "$p")))
	done

	echo "каталог:      $dir"
	echo "размер до:    $((before / 1024)) МиБ"
	echo "кандидатов:   ${#rm_paths[@]}, суммарно $((sum / 1024)) МиБ"
	echo "  (в .ubi экономия примерно вдвое меньше — образ жмётся mkfs.ubifs)"
	echo "оставлено сознательно:"
	echo "  usr/share/misc/magic.mgc (~11 МиБ) — нужен file"
	echo "  terminfo — нужен serial-консоли"
	echo
	if [ "$apply" != 1 ]; then
		echo "это отчёт. Удалить: $0 clean ${2:+\"$2\"} --apply"
		return 0
	fi

	for p in "${rm_paths[@]}"; do
		[ -e "$p" ] && rm -rf "$p"
	done
	after=$(du_k "$dir")
	echo "удалено. размер после: $((after / 1024)) МиБ (было $((before / 1024)))"
}

# -------------------------------------------------------------------- build
cmd_build() {
	[ -d "$ROOTFS" ] || die "нет $ROOTFS"
	need mkfs.ubifs "apt install mtd-utils"
	need ubinize "apt install mtd-utils"

	mkdir -p "$BUILD"
	[ -n "$OUT_UBI" ] || OUT_UBI="$BUILD/$(basename "$ROOTFS").custom.ubi"

	# В образе всё должно принадлежать root: mkfs.ubifs пишет uid/gid с диска.
	chown -R 0:0 "$ROOTFS"
	restore_owner() { chown -R "$(stat -c%u "$HERE")":"$(stat -c%g "$HERE")" "$ROOTFS"; }
	trap restore_owner EXIT

	mkfs.ubifs -r "$ROOTFS" -m "$MIN_IO" -e "$LEB" -c "$MAX_LEB" -o "$BUILD/rootfs.ubifs"

	cat > "$BUILD/ubinize.ini" <<EOF
[rootfs]
mode=ubi
image=$BUILD/rootfs.ubifs
vol_id=0
vol_type=dynamic
vol_name=rootfs
vol_flags=autoresize
vol_alignment=1
EOF

	ubinize -o "$OUT_UBI" -m "$MIN_IO" -p "$PEB" "$BUILD/ubinize.ini"

	trap - EXIT
	restore_owner
	chown "$(id -u):$(id -g)" "$OUT_UBI"

	local size
	size=$(stat -c%s "$OUT_UBI")
	if [ "$size" -gt "$UBI_REGION" ]; then
		die "образ $((size / 1048576)) МиБ не влезает в регион $((UBI_REGION / 1048576)) МиБ — уменьшайте rootfs/"
	fi

	echo
	echo "Готово: $OUT_UBI ($((size / 1048576)) МиБ из $((UBI_REGION / 1048576)) доступных)"
	echo
	echo "Прошивка (ядро и dtb те же, из fw_alpine):"
	echo "  ROOTFS_UBI=\"$OUT_UBI\" $HERE/../flasher.sh   — и пункт 3"
	echo
	echo "Не забудьте: sync на плате перед выдёргиванием питания."
}

case "$CMD" in
extract)   cmd_extract ;;
apk-build) cmd_apk_build ;;
clean)     cmd_clean "$@" ;;
build)     cmd_build ;;
esac
