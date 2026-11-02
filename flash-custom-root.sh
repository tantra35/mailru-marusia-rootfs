#!/bin/bash
# Прошивка rootfs-custom.ubi (пункт 3 меню flasher.sh).
# Автоопределение раскладки:
#   каталог проекта:  <проект>/build-rootfs/build/rootfs-custom.ubi
#   клон репозитория: <репо>/build/rootfs-custom.ubi
cd "$(dirname "$0")" || exit 1
if [ -f build-rootfs/build/rootfs-custom.ubi ]; then
    ROOTFS_UBI=$PWD/build-rootfs/build/rootfs-custom.ubi
elif [ -f build/rootfs-custom.ubi ]; then
    ROOTFS_UBI=$PWD/build/rootfs-custom.ubi
else
    echo "rootfs-custom.ubi не найден — собери через build/rebuild.sh" >&2
    exit 1
fi
exec ./flasher.sh
