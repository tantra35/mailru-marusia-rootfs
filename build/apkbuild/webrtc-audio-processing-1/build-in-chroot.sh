#!/bin/sh
# Сборка webrtc-audio-processing-1 (патченные пороги AEC3) в чруте VK Mini
rm -f /dev/null && mknod -m 666 /dev/null c 1 3
cd /home/builder/package/community/webrtc-audio-processing-1 || exit 9
abuild -r > /tmp/wap-build.log 2>&1
echo EXIT=$?
tail -12 /tmp/wap-build.log
