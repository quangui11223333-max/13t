#!/usr/bin/env bash
# 把编出来的 Image 塞进 AnyKernel3 骨架，产出可刷 zip
# 用法:
#   ./repack-ak3.sh [-k path/to/Image] [-b path/to/ak3-skeleton.zip] [-o out.zip] [-s suffix]
# 默认读 src/oneplus13t-kernel/out/msm-kernel/sun_perf/dist/Image
# 默认用同目录下已下载的 AnyKernel3-6.6.118-OnePlus13T-v3.6.zip 作骨架
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/.." && pwd)"
IMG="$BASE/src/oneplus13t-kernel/out/msm-kernel/sun_perf/dist/Image"
SKEL="$BASE/AnyKernel3-6.6.118-OnePlus13T-v3.6.zip"
SUFFIX="custom-$(date +%Y%m%d-%H%M)"
OUT=""

while getopts "k:b:o:s:h" opt; do
  case "$opt" in
    k) IMG="$OPTARG" ;;
    b) SKEL="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    s) SUFFIX="$OPTARG" ;;
    h) sed -n '2,7p' "$0"; exit 0 ;;
    *) exit 2 ;;
  esac
done

[ -f "$IMG" ]  || { echo "Image not found: $IMG"  >&2; exit 2; }
[ -f "$SKEL" ] || { echo "AK3 skeleton not found: $SKEL" >&2; exit 2; }
[ -n "$OUT" ] || OUT="$BASE/out/AnyKernel3-6.6.x-OnePlus13T-$SUFFIX.zip"
mkdir -p "$(dirname "$OUT")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== unpack skeleton"
unzip -q "$SKEL" -d "$WORK/ak3"
[ -f "$WORK/ak3/anykernel.sh" ] || { echo "skeleton has no anykernel.sh" >&2; exit 3; }

echo "== swap Image ($(du -h "$IMG" | cut -f1))"
cp -f "$IMG" "$WORK/ak3/Image"

# 版本串写进 anykernel.sh，方便刷完在 KSU/Magisk 管理器里认出来
VER="$(strings -a "$IMG" | grep -m1 'Linux version 6\.6\.' | awk '{print $3}' || true)"
if [ -n "${VER:-}" ]; then
  sed -i "s|^kernel.string=.*|kernel.string=OnePlus13T ${VER} ${SUFFIX}|" "$WORK/ak3/anykernel.sh"
  echo "== kernel.string -> OnePlus13T ${VER} ${SUFFIX}"
fi

echo "== zip"
( cd "$WORK/ak3" && zip -qr9 "$OUT" . -x '.git*' )
echo "OK  $OUT"
sha256sum "$OUT" 2>/dev/null || true
echo
echo "flash: KernelSU/APatch 管理器 → 模块 → 从本地安装；或 TWRP → Install"
