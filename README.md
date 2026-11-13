# mailru-marusia-rootfs

Воспроизводимая сборка Alpine Linux rootfs для **VK Capsula Mini (Mail.ru Маруся)** на Amlogic A113X — с полностью сетевым аудио: микрофон и динамик колонки доступны по TCP 4713 (PulseAudio), DLNA-рендерер «Marusia», mpd + upmpdcli, sshd.

```
NanoPi6 (LVA) ──WiFi──> tcp://<колонка>:4713  ← микрофон PDM + динамик
телефон ───────DLNA──> «Marusia» (upmpdcli) → mpd (:6600) → PulseAudio
```

## Железо

- Amlogic A113X (4× Cortex-A53 @ 1.2 ГГц), 256 МиБ DDR3
- NAND Toshiba TC58NVG1S3HBAI4, 256 МиБ (PEB 128 КиБ, LEB 124 КиБ)
- WiFi/BT `aml_w1` (SDIO), PDM-микрофоны (2 живых канала), усилитель NTP8910A, светодиодное кольцо, тач-панель
- Serial console: `ttyAML0` 115200 (root/1)

## Что внутри rootfs

- Alpine Linux 3.24, OpenRC, busybox mdev
- **PulseAudio 17.0** (своя сборка, system-mode): unix-сокет для локальных клиентов + **TCP 4713** (ACL: LAN) — микрофон и динамик колонки доступны по сети
- **mpd 0.24.15** (своя сборка, вывод через PulseAudio) — порт 6600
- **upmpdcli 1.9.17** — DLNA-рендерер «Marusia» (только рендерер, `openhome=0`)
- 59 стоковых звуков в `/etc/sounds` (проигрываются `paplay`)
- sshd (root/1), iwd (WiFi-конфиг сохраняется в образе), bluetooth + bluealsa
- НЕТ: pipewire, espeak, mpg123 CLI, mesa, ffmpeg

## Структура репозитория

| Путь | Что это |
|---|---|
| `template/` | Оверлей поверх базового Alpine: конфиги, init-скрипты, звуки, пользователи, mdev.conf |
| `rootfs/etc/apk/world` | Список пакетов (мир) для apk-init |
| `build/rebuild.sh` | Сборка `.ubi` из дерева + обход плохих PEB (`$BAD_PEB_FILE`, по умолчанию `bad-pebs-shtab.txt`) |
| `build/add-mpd.sh` | Установка mpd+upmpdcli в дерево, конфиги, группы |
| `build/bootstrap-chroot.sh` / `finish-chroot.sh` | Развёртывание chroot-сборщика под qemu-aarch64 |
| `build/simple-image.sh` | Упрощённая упаковка (без обхода bad PEB) |
| `build/custom-repo/aarch64/*.apk` | Наши пакеты: pulseaudio-r100, mpd-r100, gl-stub |
| `build/apkbuild/` | APKBUILD'ы (mpd, pulseaudio, gl-stub, pipewire-архив) |
| `build/sbin/apk.static` | apk-tools-static (x86_64) |
| `build/repositories.txt` | Alpine 3.24 + наш custom-repo |
| `bad-pebs-shtab.txt` (рядом с репо, в git **не входит**) | **Плохие PEB штабовой колонки** — обход при прошивке. Для другой платы свой файл через `BAD_PEB_FILE` |
| `build/scan-bad-pebs` | Сканер плохих PEB: на живой плате из `/tmp` (ramfs) или внутри initramfs (`/scan`) |
| `build/initramfs-init` + `build/make-scan-initramfs.sh` | Сборка `scan-initramfs.cpio.gz` (busybox+musl+сканер) для пункта 5 flasher.sh — скан с пустой платы через UART |
| `flasher.sh` | Прошивальщик: USB-burn (окно 450 мс), бэкап, raw-запись сегментами |
| `flash-custom-root.sh` | Обёртка: прошить rootfs-custom.ubi |
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

Результат: `build-rootfs/build/rootfs-custom.ubi` (~103 МиБ).

### Откуда берутся кастомные пакеты

`build/custom-repo/aarch64/*.apk` собраны APKBUILD'ами из `build/apkbuild/` в chroot-окружении (qemu-aarch64). Для пересборки: `bootstrap-chroot.sh` → `abuild -r`. Подпись пакетов — приватным ключом, который **не входит в репозиторий**; ставьте свои (`abuild-keygen`) и используйте `--allow-untrusted`.

## Прошивка

```bash
# колонка в режиме USB burn (InUsbBurn, окно ~450 мс после reset)
./flash-custom-root.sh
```

`flasher.sh` (пункт 3) стирает регион rootfs и пишет образ **сегментами**, пропуская деградировавшие блоки NAND из bad-pebs-файла (путь: переменная `BAD_PEB_FILE`, по умолчанию `bad-pebs-shtab.txt` уровнем выше репо).

**Как снять список плохих PEB с конкретной платы** — `build/scan-bad-pebs`, две роли:

1. **Плата ещё грузится (есть ssh)** — скрипт в ramfs, во flash ничего не пишет:
```bash
scp build/scan-bad-pebs root@<IP>:/tmp/
ssh root@<IP> 'sh /tmp/scan-bad-pebs > /tmp/bad-pebs-<имя>.txt'
scp root@<IP>:/tmp/bad-pebs-<имя>.txt .   # рядом с репо; файлы в git не входят
```
2. **Плата пустая/руфс сломан** — RAM-сканер flasher.sh (пункт 5 «Скан плохих PEB», образ `build/scan-initramfs.cpio.gz` собирается `build/make-scan-initramfs.sh`): ядро+initramfs целиком в ОЗУ, NAND только читается, список печатается в UART между маркерами `# === 8< ===` — скопируйте из PuTTY в файл.

Ловит заводские bad-блоки и PEB с неисправимой ECC («error -74»); исправимые битфлипы не видит (за ними следит `ubihealthd`). Старый способ тоже работает: `dmesg` (`bad node at LEB N` → PEB N+2).

Дальше файл через переменную окружения — и пересборка, и прошивка используют один и тот же список:
```bash
BAD_PEB_FILE=$HOME/Загрузки/marusia/bad-pebs-<имя>.txt build/rebuild.sh
BAD_PEB_FILE=$HOME/Загрузки/marusia/bad-pebs-<имя>.txt ./flasher.sh
```
По умолчанию оба берут `bad-pebs-shtab.txt` уровнем выше репо (штабовая колонка); эти файлы — частная история плат, в git не входят. Пустой/отсутствующий файл = образ без дыр.

После первой загрузки:
1. WiFi: `wifi-connect-iwd` (в этом образе PSK уже вшит — подключится сам)
2. `ssh root@<IP>` (пароль `1`) — всё уже работает

## Известные особенности

- **Порядок старта и сеть**: `net-wait` блокирует запуск `upmpdcli`/`mpd`/`pulseaudio`/`sshd` до появления IPv4 на wlan0 (iwd подключается асинхронно) — сервисы всегда стартуют с уже готовой сетью. Ограничение: если WiFi пропадёт уже во время работы, SSDP-анонсы upmpdcli не возобновятся автоматически — на этот случай планируется хук в `marusia-d` (рестарт upmpdcli по netlink-событию). Ручное лечение: `rc-service upmpdcli restart`.
- Полная перепрошивка стирает `/var/lib/iwd`, но PSK-файл вшит в образ — WiFi автоподключается при первом буте.
- `mkfs.ubifs` собирается **без** `-F` (SPACE_FIXUP): флешер стирает весь регион перед записью, fixup-бурст на деградировавшем NAND опасен (приводил к коррупции индекса /usr/lib).
- Вход горячий: PDM пишет с пиком ~44%; для LVA при необходимости `pactl set-source-volume alsa_input.hw_0_1 80%`.
- `hw:0,2` (второй capture-линк) — не подключён (RMS 0), рабочие микрофоны только на `hw:0,1`.

## Благодарности

- [comp18man/vk-capsula-mini-a113x-linux](https://github.com/comp18man/vk-capsula-mini-a113x-linux) — ядро мейнлайн для VK Capsula Mini (автор образов и статьи)
- [debianlive.ru — VK Mini Legacy Amlogic A113X, часть 1](https://debianlive.ru/2026/08/vk-mini-legacy-amlogic-a113x-%D1%87%D0%B0%D1%81%D1%82%D1%8C-1-%D1%81%D1%82%D0%B0%D0%B2%D0%B8%D0%BC-alpine-%D1%81%D0%BE-%D1%81%D0%B2%D0%B5%D0%B6%D0%B8%D0%BC-%D0%BC%D0%B0%D0%B9%D0%BD%D0%BB%D0%B0/) — базовая статья по установке Alpine
- Mail.ru — за устройство, которое можно перепрошивать

## Лицензия

MIT — см. [LICENSE](LICENSE).
