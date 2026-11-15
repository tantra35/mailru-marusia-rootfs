# mailru-marusia-rootfs

Воспроизводимая сборка Alpine Linux rootfs для **VK Capsula Mini (Mail.ru Маруся)** на Amlogic A113X — с полностью сетевым аудио: микрофон и динамик колонки доступны по TCP 4713 (PulseAudio), DLNA-рендерер «Marusia», mpd + upmpdcli, Spotify Connect (spotifyd), sshd.

```
NanoPi6 (LVA) ──WiFi──> tcp://<колонка>:4713  ← микрофон PDM + динамик
телефон ───────DLNA──> «Marusia» (upmpdcli) → mpd (:6600) → PulseAudio
телефон ───Spotify Connect──> spotifyd → PulseAudio
```

## Железо

- Amlogic A113X (4× Cortex-A53 @ 1.2 ГГц), 256 МиБ DDR3
- NAND Toshiba TC58NVG1S3HBAI4, 256 МиБ (PEB 128 КиБ, LEB 124 КиБ)
- WiFi/BT `aml_w1` (SDIO), PDM-микрофоны (2 живых канала), усилитель NTP8910A, светодиодное кольцо, тач-панель
- Serial console: `ttyAML0` 115200

## Что внутри rootfs

- Alpine Linux 3.24, OpenRC, busybox mdev
- **PulseAudio 17.0** (своя сборка, system-mode): unix-сокет для локальных клиентов + **TCP 4713** (ACL: LAN) — микрофон и динамик колонки доступны по сети
- **mpd 0.24.15** (своя сборка, вывод через PulseAudio) — порт 6600
- **upmpdcli 1.9.17** — DLNA-рендерер «Marusia» (только рендерер, `openhome=0`)
- **spotifyd 0.4.2** (Alpine community, pulseaudio-бэкенд) — Spotify Connect, авторизация через zeroconf: телефон видит колонку прямо в приложении Spotify, логин/пароль не нужны
- `/lib/firmware/eq_8918.bin` — калибровка усилителя NTP8910/8918 (из расшифрованного вендор-ядра); **без неё усилитель молчит** — драйвер NTP8918 подгружает её при первом открытии PCM
- 59 стоковых звуков в `/etc/sounds` (проигрываются `paplay`)
- sshd, iwd + `net-wifi-wait` (после ассоциации поднимает DHCP `udhcpc` — как в авторском `wifi-connect-iwd`), bluetooth + bluealsa
- НЕТ: pipewire, espeak, mpg123 CLI, mesa, ffmpeg

## Структура репозитория

| Путь | Что это |
|---|---|
| `template/` | Оверлей поверх базового Alpine: конфиги, init-скрипты, звуки, пользователи, mdev.conf |
| `rootfs/etc/apk/world` | Список пакетов (мир) для apk-init |
| `build/rebuild.sh` | Сборка `.ubi` из дерева + обход плохих PEB (`$BAD_PEB_FILE`, по умолчанию `bad-pebs-shtab.txt`) |
| `build/add-mpd.sh` | Установка mpd+upmpdcli в дерево, конфиги, группы |
| `build/add-spotifyd.sh` | Установка spotifyd (Spotify Connect) в дерево: пакет, юзер, pulse-access, init.d + рунлевел |
| `build/bootstrap-chroot.sh` / `finish-chroot.sh` | Развёртывание chroot-сборщика под qemu-aarch64 |
| `build/simple-image.sh` | Упрощённая упаковка (без обхода bad PEB) |
| `build/custom-repo/aarch64/*.apk` | Наши пакеты: pulseaudio-r100, mpd-r100, gl-stub |
| `build/apkbuild/` | APKBUILD'ы (mpd, pulseaudio, gl-stub, pipewire-архив) |
| `build/sbin/apk.static` | apk-tools-static (x86_64) |
| `build/repositories.txt` | Alpine 3.24 + наш custom-repo |
| `bad-pebs-shtab.txt` (рядом с репо, в git **не входит**) | **Плохие PEB штабовой колонки** — обход при прошивке. Для другой платы свой файл через `BAD_PEB_FILE` |
| `build/scan-bad-pebs` | Сканер плохих PEB: на живой плате из `/tmp` (ramfs) или внутри initramfs (`/scan`) |
| `build/initramfs-init` + `build/scan-bad-pebs` | Сканер и его initramfs-«рутфс» (busybox+musl) |
| `build/make-ramrootfs-kernel.sh` | Сборка `Image-ramrootfs`: ядро автора со вшитым сканером (INITRAMFS_SOURCE, text_offset=0x1080000) для пункта 5 flasher.sh |
| `flasher.sh` | Прошивальщик: USB-burn (окно 450 мс), бэкап, raw-запись сегментами |
| `build-rootfs.sh` | Сборка дерева rootfs с нуля (apk-init + оверлей) |
| `marusia_defconfig` | Kernel defconfig для ядра автора |
| `firmware/` | Kernel Image + DTB (ядро: [comp18man/vk-capsula-mini-a113x-linux](https://github.com/comp18man/vk-capsula-mini-a113x-linux)) |

## Сборка rootfs с нуля

### Оригинальный рецепт упаковки (автор образа, [комментарий в статье](https://debianlive.ru/2026/08/vk-mini-legacy-amlogic-a113x-%D1%87%D0%B0%D1%81%D1%82%D1%8C-1-%D1%81%D1%82%D0%B0%D0%B2%D0%B8%D0%BC-alpine-%D1%81%D0%BE-%D1%81%D0%B2%D0%B5%D0%B6%D0%B8%D0%BC-%D0%BC%D0%B0%D0%B9%D0%BD%D0%BB%D0%B0/), mtd-utils 2.3.0)

```bash
mkfs.ubifs \
  --root alpine \
  --min-io-size 2048 \
  --leb-size 126976 \
  --max-leb-cnt 1661 \
  --compr zstd \
  --space-fixup \
  --output rootfs.ubifs

ubinize \
  --output alpine3.24.1_rootfs.ubi \
  --peb-size 131072 \
  --min-io-size 2048 \
  --vid-hdr-offset 2048 \
  ubinize.cfg
```

`ubinize.cfg` — как наш `build/ubinize.ini` (rootfs, dynamic, autoresize). `--max-leb-cnt 1661` = 1696 PEB − 2 (таблица томов) − 33 (~2% резерв под bad-блоки).

**Наша сборка (`rebuild.sh`) сознательно не использует `--space-fixup`** (флаги образа = 0, не 4): флешер стирает весь регион перед записью, поэтому фальшиво-стёртых страниц в образе нет, а fixup-бурст первого монтирования (~11 с перезаписи всех свободных LEB) на изношенном/обесточенном NAND приводил к коррупции индекса /usr/lib. На здоровом NAND авторский вариант с `--space-fixup` корректен.

Требования: Linux x86_64, `qemu-user-binfmt`, `git`, сетевой доступ к dl-cdn.alpinelinux.org.

```bash
# 1. Дерево rootfs из чистого Alpine 3.24 (apk-init) + оверлей из template/
sudo ./build-rootfs.sh

# 2. mpd + upmpdcli + конфиги + группы (наши пакеты из custom-repo/)
sudo ./build/add-mpd.sh

# 3. Упаковка в .ubi с обходом плохих PEB
sudo ./build/rebuild.sh
```

Результат: `build/rootfs-custom-<BOARD>.ubi` (`BOARD` по умолчанию `shtab`, ~106 МиБ; для другой платы — `BOARD=nova sudo bash build/rebuild.sh`).

### Откуда берутся кастомные пакеты

`build/custom-repo/aarch64/*.apk` собраны APKBUILD'ами из `build/apkbuild/` в chroot-окружении (qemu-aarch64). Для пересборки: `bootstrap-chroot.sh` → `abuild -r`. Подпись пакетов — приватным ключом, который **не входит в репозиторий**; ставьте свои (`abuild-keygen`) и используйте `--allow-untrusted`.

## Плохие блоки NAND (PEB) — почему это важно

NAND-память колонки может содержать **плохие блоки** (PEB) — заводские (помечены производителем) и появляющиеся при износе. UBI в целом умеет их обходить, но наш процесс сборки и прошивки пишет образ во flash **напрямую, посекторно, своим загрузчиком** — поэтому плохие блоки нужно исключить заранее, на двух этапах:

1. **При сборке rootfs** (`build/rebuild.sh`): содержимое плохих PEB переносится в хвост образа, а на их место кладутся пустышки — образ «разъезжается» так, чтобы живые данные не попали в битовые блоки.
2. **При прошивке** (`flasher.sh`, пункт 3): образ пишется **сегментами**, пропуская плохие PEB — U-Boot ни разу не получает шанс сдвинуть поток данных своим skip'ом.

Список плохих блоков у каждой платы свой и хранится в отдельном файле (`BAD_PEB_FILE`). Как снять список со своей колонки и весь workflow — см. «Сканирование NAND» ниже. Если плата новая и NAND целая — файл можно не указывать (обычная прошивка без обхода).

Для проверки NAND прямо на колонке (даже без рабочей rootfs) есть RAM-сканер: ядро со вшитым сканером грузится в ОЗУ по USB-C, читает все PEB и показывает результат — сканеру UART не нужен, всё работает через USB-C.

## Прошивка

```bash
# колонка в режиме USB burn (InUsbBurn, окно ~450 мс после reset)
./flasher.sh   # пункт 3 меню
```

`flasher.sh` (пункт 3) стирает регион rootfs и пишет образ **сегментами**, пропуская деградировавшие блоки NAND из bad-pebs-файла (путь: переменная `BAD_PEB_FILE`, по умолчанию `bad-pebs-shtab.txt` уровнем выше репо). Какой образ шить и какой bad-файл брать, flasher определяет по выбранной плате сам: `build/rootfs-custom-<плата>.ubi` (префикс `marusia-` у каталога платы из `flasher_stuff/` отбрасывается); явные `ROOTFS_UBI`/`BAD_PEB_FILE` из окружения сильнее автоопределения. Обёртки `flash-custom-root-*.sh` — просто способ передать эти пути через окружение (**обязательно `export`**: неэкспортированная переменная умирает на `exec` и флешер молча возьмёт стоковый образ).

**Как снять список плохих PEB с конкретной платы** — `build/scan-bad-pebs`, две роли:

1. **Плата ещё грузится (есть ssh)** — скрипт в ramfs, во flash ничего не пишет:
```bash
scp build/scan-bad-pebs root@<IP>:/tmp/
ssh root@<IP> 'sh /tmp/scan-bad-pebs > /tmp/bad-pebs-<имя>.txt'
scp root@<IP>:/tmp/bad-pebs-<имя>.txt .   # рядом с репо; файлы в git не входят
```
2. **Плата пустая/руфс сломан** — RAM-сканер flasher.sh (пункт 5 «Скан плохих PEB»): в ОЗУ грузится `Image-ramrootfs` — ядро автора **со вшитым initramfs-сканером** (собирается `build/make-ramrootfs-kernel.sh`; нужен кросс-тулчейн `gcc-aarch64-linux-gnu flex bison libssl-dev` и исходники ядра в `~/Загрузки/marusia/kernel-src`). NAND только читается. Вендорский booti отдельный initrd НЕ принимает — поэтому initramfs вшит в Image. Вывод идёт через **USB-C** (ACM-gadget → `/dev/ttyACM0`) — flasher показывает лог живьём и сохраняет список в `bad-pebs-<имя>.txt`; UART — запасной канал, список там между маркерами `# === 8< ===`.

Ловит заводские bad-блоки и PEB с неисправимой ECC («error -74»); исправимые битфлипы не видит (за ними следит `ubihealthd`). Старый способ тоже работает: `dmesg` (`bad node at LEB N` → PEB N+2).

Дальше файл через переменную окружения — и пересборка, и прошивка используют один и тот же список:
```bash
BAD_PEB_FILE=$HOME/Загрузки/marusia/bad-pebs-<имя>.txt build/rebuild.sh
BAD_PEB_FILE=$HOME/Загрузки/marusia/bad-pebs-<имя>.txt ./flasher.sh
```
По умолчанию оба берут `bad-pebs-shtab.txt` уровнем выше репо (штабовая колонка); эти файлы — частная история плат, в git не входят. Пустой/отсутствующий файл = образ без дыр.

После первой загрузки всё поднимается само (порядок: `iwd` → `net-wait`, он же поднимает `udhcpc` → `alsa` (restore микшера) → `pulseaudio` → `mpd` → `upmpdcli` → `marusia-d` → `sshd`):
1. WiFi: PSK уже вшит в `/var/lib/iwd` — подключится сам, адрес придёт по DHCP
2. `ssh root@<IP>` — пароль в `shtab-private/shadow` (в публичном README не публикуется)
3. Spotify Connect: телефон → приложение Spotify → «Devices» → колонка

## Известные особенности

- **Порядок старта и сеть**: `net-wait` поднимает DHCP (`udhcpc`, как в авторском `wifi-connect-iwd`) и блокирует запуск `upmpdcli`/`mpd`/`pulseaudio`/`sshd` до появления IPv4 на wlan0. Если WiFi пропадёт уже во время работы, SSDP-анонсы upmpdcli возобновляет `net-watch` (рестарт upmpdcli по появлению адреса, `ip monitor`); ручное лечение: `rc-service upmpdcli restart`.
- **Микшер при загрузке**: `alsa`-сервис восстанавливает `/var/lib/alsa/asound.state` (`alsactl restore`) — в т.ч. маршрут `FRDDR_A SINK SEL = OUT 2` на усилитель. Каталог должен принадлежать root (rebuild.sh нормализует), иначе restore не применится и звука не будет.
- Полная перепрошивка стирает `/var/lib/iwd`, но PSK-файл вшит в образ — WiFi автоподключается при первом буте.
- **Владельцы /var**: `rebuild.sh` выставляет сервисные uid/gid числами (pulse 104:106, mpd 103:18, upmpdcli 105:105, chrony 100:101, `/var/empty` root 711) — дерево собирается от uid 1000, и без нормализации демоны падают на правах доступа (pulseaudio — на tdb-базах, sshd — на `/var/empty`).
- `mkfs.ubifs` собирается **без** `-F` (SPACE_FIXUP): флешер стирает весь регион перед записью, fixup-бурст на деградировавшем NAND опасен (приводил к коррупции индекса /usr/lib).
- Вход горячий: PDM пишет с пиком ~44%; для LVA при необходимости `pactl set-source-volume alsa_input.hw_0_1 80%`.
- `hw:0,2` (второй capture-линк) — не подключён (RMS 0), рабочие микрофоны только на `hw:0,1`.

## Благодарности

- [comp18man/vk-capsula-mini-a113x-linux](https://github.com/comp18man/vk-capsula-mini-a113x-linux) — ядро мейнлайн для VK Capsula Mini (автор образов и статьи)
- [debianlive.ru — VK Mini Legacy Amlogic A113X, часть 1](https://debianlive.ru/2026/08/vk-mini-legacy-amlogic-a113x-%D1%87%D0%B0%D1%81%D1%82%D1%8C-1-%D1%81%D1%82%D0%B0%D0%B2%D0%B8%D0%BC-alpine-%D1%81%D0%BE-%D1%81%D0%B2%D0%B5%D0%B6%D0%B8%D0%BC-%D0%BC%D0%B0%D0%B9%D0%BD%D0%BB%D0%B0/) — базовая статья по установке Alpine
- Mail.ru — за устройство, которое можно перепрошивать

## Лицензия

MIT — см. [LICENSE](LICENSE).
