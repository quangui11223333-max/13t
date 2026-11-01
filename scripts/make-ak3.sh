#!/usr/bin/env bash
# 用 AnyKernel3 骨架 + 编译出的 Image 打出可刷 zip。
#
# 用法:
#   ./make-ak3.sh -k <Image> [-a <AnyKernel3 目录>] [-o <输出 zip>] [-s <后缀>]
#                 [-d <device,device,...>] [-n <kernel.string>]
#
# 说明:
#   - 13T 是 GKI + init_boot 设备：kernel 在 boot.img，ramdisk 在 init_boot.img。
#     所以 anykernel.sh 用 split_boot + flash_boot（只换 kernel，不动 ramdisk）。
#   - do.devicecheck 默认 0：一加不同区域/固件的 ro.product.device 不一样，
#     先不拦；拿到手机实测值后用 -d 传进来再打开。
#   - AK3 自带的 magiskboot 是 aarch64 静态二进制，在手机端执行，本脚本只负责组包。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/.." && pwd)"

IMG=""
AK3=""
OUT=""
SUFFIX="custom-$(date +%Y%m%d-%H%M)"
DEVS=""
KSTR=""

while getopts "k:a:o:s:d:n:h" opt; do
  case "$opt" in
    k) IMG="$OPTARG" ;;
    a) AK3="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    s) SUFFIX="$OPTARG" ;;
    d) DEVS="$OPTARG" ;;
    n) KSTR="$OPTARG" ;;
    h) sed -n '2,17p' "$0"; exit 0 ;;
    *) exit 2 ;;
  esac
done

# 没给 -k 就按官方树的标准产物位置找
if [ -z "$IMG" ]; then
  for c in "$BASE/src/oneplus13t-kernel/device/qcom/sun-kernel/Image" \
           "$BASE/out/Image" \
           "$(ls -1 "$BASE"/src/oneplus13t-kernel/kernel_platform/out/*/dist/Image 2>/dev/null | head -1)"; do
    [ -n "$c" ] && [ -f "$c" ] && { IMG="$c"; break; }
  done
fi
[ -n "$IMG" ] && [ -f "$IMG" ] || { echo "Image 找不到，用 -k 指定" >&2; exit 2; }
[ -d "$AK3" ] || { echo "AnyKernel3 骨架目录找不到，用 -a 指定（git clone --depth 1 https://github.com/osm0sis/AnyKernel3）" >&2; exit 2; }
[ -f "$AK3/tools/magiskboot" ] || { echo "骨架缺 tools/magiskboot" >&2; exit 2; }
[ -f "$AK3/META-INF/com/google/android/update-binary" ] || { echo "骨架缺 update-binary" >&2; exit 2; }

VER="$(strings -a "$IMG" | grep -m1 'Linux version 6\.6\.' | awk '{print $3}' || true)"
[ -n "$KSTR" ] || KSTR="OnePlus13T ${VER:-6.6.x} ${SUFFIX}"
DEV1="PKX110"; DEV2="sun"
if [ -n "$DEVS" ]; then
  DEV1="$(echo "$DEVS" | cut -d, -f1)"
  DEV2="$(echo "$DEVS" | cut -d, -f2- | tr ',' ' ')"
  DOCHECK=1
else
  DOCHECK=0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -a "$AK3/." "$WORK/ak3/"
rm -rf "$WORK/ak3/.git" "$WORK/ak3/.github"

echo "== 生成 anykernel.sh"
sed -e "s|@KERNEL_STRING@|${KSTR}|g" \
    -e "s|@DEVICECHECK@|${DOCHECK}|g" \
    -e "s|@DEVICE1@|${DEV1}|g" \
    -e "s|@DEVICE2@|${DEV2}|g" \
    "$HERE/ak3-anykernel.sh" > "$WORK/ak3/anykernel.sh"

echo "== 放入 Image ($(du -h "$IMG" | cut -f1)) : $(strings -a "$IMG" | grep -m1 'Linux version' | cut -c1-90)"
cp -f "$IMG" "$WORK/ak3/Image"

mkdir -p "$BASE/out"
[ -n "$OUT" ] || OUT="$BASE/out/AnyKernel3-OnePlus13T-${VER:-6.6.x}-${SUFFIX}.zip"
rm -f "$OUT"

echo "== 打 zip"
( cd "$WORK/ak3" && zip -qr9 "$OUT" . -x '.git*' )
echo "OK  $OUT"
ls -lh "$OUT"
( cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" ) || true
echo
echo "刷入方式（三选一）:"
echo "  1) KernelSU / APatch 管理器 → 模块 → 从本地安装 → 选这个 zip"
echo "  2) TWRP/OrangeFox → Install → 选这个 zip"
echo "  3) 解压后 fastboot flash boot boot.img（本包不含 boot.img，需自行重打包）"
echo
echo "首次务必先 fastboot boot 验证，别直接 flash——见 docs/oneplus13t-kernel.md 的回滚章节"
