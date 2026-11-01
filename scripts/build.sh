#!/usr/bin/env bash
# 一加 13T（PKX110 / sun / sm8750）官方内核构建包装脚本
# 用法:
#   ./build.sh                 # 全默认：性能变体 perf，只编内核+镜像（不含 359 个 vendor ko）
#   ./build.sh --full-ko       # 连 vendor ko 一起编（+2h）
#   ./build.sh --kernel-only   # 只重编内核
#   ./build.sh --dtbo-only     # 只重编 DTBO
#   TREE=/path/to/oneplus13t-kernel ./build.sh
set -euo pipefail

TREE="${TREE:-$(cd "$(dirname "$0")/.." && pwd)/src/oneplus13t-kernel}"
PLATFORM="${PLATFORM:-sun}"      # sun = SM8750 平台
VARIANT="${VARIANT:-perf}"       # perf（出厂同款）| consolidate
FULL_KO=0; KERNEL_ONLY=0; DTBO_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --full-ko)     FULL_KO=1 ;;
    --kernel-only) KERNEL_ONLY=1 ;;
    --dtbo-only)   DTBO_ONLY=1 ;;
    -h|--help)     sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

cd "$TREE" || { echo "tree not found: $TREE" >&2; exit 2; }

# ---- 预检 ----------------------------------------------------------------
fail() { echo "PREFLIGHT FAIL: $*" >&2; exit 1; }
[ -d kernel_platform/common ]     || fail "kernel_platform/common missing"
[ -d kernel_platform/msm-kernel ] || fail "kernel_platform/msm-kernel missing"
[ -d vendor/oplus ]               || fail "vendor/oplus missing"
[ -f kernel_platform/oplus/build/oplus_build_kernel.sh ] || fail "oplus build entry missing"

# 软链接完好性（Windows 解包会把它们变成普通小文本文件）
for f in kernel_platform/tools/bazel kernel_platform/build/android/prepare_vendor.sh; do
  if [ -f "$f" ] && [ ! -L "$f" ] && [ "$(stat -c%s "$f")" -lt 200 ]; then
    fail "$f is a broken pseudo-symlink (extracted on Windows). Re-assemble on Linux (scripts/assemble.py)."
  fi
done

FREE_GIB=$(df -BG --output=avail . | tail -1 | tr -dc '0-9')
[ "${FREE_GIB:-0}" -ge 25 ] || fail "only ${FREE_GIB} GiB free, need >= 25 GiB"

command -v python3 >/dev/null || fail "python3 required"
command -v rsync   >/dev/null || echo "warn: rsync missing (some bazel steps want it)"

# ---- 环境 ----------------------------------------------------------------
export TOPDIR="$PWD"
export ANDROID_BUILD_TOP="$TOPDIR"
mkdir -p "$TOPDIR/LOGDIR" "$TOPDIR/out"

# 可选：让 bazel 走 oplus 的远端缓存（账号/token 需自行配置）
# export OPLUS_USE_JFROG_CACHE=true
# export OPLUS_USE_BUILDBUDDY_REMOTE_BUILD=true

[ "$KERNEL_ONLY" = 1 ] && export RECOMPILE_KERNEL=1
[ "$DTBO_ONLY"   = 1 ] && export RECOMPILE_DTBO=1
[ "$FULL_KO"     = 1 ] && export OPLUS_BUILD_KO=true

# ---- 构建 ----------------------------------------------------------------
echo "== building $PLATFORM/$VARIANT in $PWD"
bash kernel_platform/oplus/build/oplus_build_kernel.sh "$PLATFORM" "$VARIANT"

# ---- 产物 ----------------------------------------------------------------
OUT="out/msm-kernel/${PLATFORM}_${VARIANT}"
echo "== artifacts under $OUT"
ls -lh "$OUT/dist/Image" "$OUT/dist/boot.img" "$OUT/dist/dtbo.img" 2>/dev/null || true
echo "== kernel string in Image:"
strings -a "$OUT/dist/Image" 2>/dev/null | grep -m3 'Linux version 6\.6\.' || true
echo
echo "flash:  fastboot flash boot $OUT/dist/boot.img   (or repack with scripts/repack-ak3.sh)"
