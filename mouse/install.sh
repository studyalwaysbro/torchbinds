#!/usr/bin/env bash
# Replaces Ubuntu's ckb-next 0.6.0 (too old for the Scimitar RGB Elite 1b1c:1be3) with a build of the
# upstream source at commit 833ab509, which supports it. Run with: sudo bash install.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run this with sudo."; exit 1; }
USERNAME="${SUDO_USER:-yeeterson}"
SRC=/home/yeeterson/projects/torchbinds/mouse/ckb-next
LOG=/home/yeeterson/projects/torchbinds/mouse/install.log
exec > >(tee "$LOG") 2>&1
chown "$USERNAME" "$LOG" 2>/dev/null || true
echo "== 1/4 build tools"
apt-get install -y cmake build-essential libudev-dev qtbase5-dev qttools5-dev qttools5-dev-tools zlib1g-dev libpulse-dev \
  libquazip5-dev libqt5x11extras5-dev libxcb-screensaver0-dev libxcb-ewmh-dev libxcb1-dev libdbusmenu-qt5-dev
echo "== 2/4 remove the old version"
systemctl disable --now ckb-next-daemon 2>/dev/null || true
apt-get remove -y ckb-next || true
echo "== 3/4 build (a few minutes)"
cd "$SRC"
sudo -u "$USERNAME" rm -rf build
sudo -u "$USERNAME" cmake -H. -Bbuild -DCMAKE_BUILD_TYPE=Release -DSAFE_INSTALL=OFF -DSAFE_UNINSTALL=OFF -DPREFER_QT6=OFF
sudo -u "$USERNAME" cmake --build build --target all -- -j"$(nproc)"
echo "== 4/4 install and start"
cmake --build build --target install
systemctl daemon-reload
systemctl enable --now ckb-next-daemon
sleep 4
echo
if ls -d /dev/input/ckb[1-9] >/dev/null 2>&1; then
  echo "MOUSE FOUND: $(cat /dev/input/ckb[1-9]/model 2>/dev/null | head -1)"
else
  echo "The daemon is running but has not picked up the mouse yet. Unplug the mouse, plug it back in, and tell Claude."
fi
echo "DONE. Tell Claude it finished."
