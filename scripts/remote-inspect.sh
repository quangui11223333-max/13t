#!/usr/bin/env bash
# Investigate oddities found by remote-preflight.sh
set -u
TREE="${1:-$HOME/work/13t/oneplus13t-kernel}"

say() { printf '\n== %s\n' "$*"; }

say "1) clang prebuilt layout"
ls -d "$TREE"/kernel_platform/prebuilts/clang/host/linux-x86/*/ 2>/dev/null
C=$(ls -d "$TREE"/kernel_platform/prebuilts/clang/host/linux-x86/clang-* 2>/dev/null | head -1)
echo "  dir: $C"
ls "$C" 2>/dev/null | head -20
echo "  looking for clang binaries:"
find "$C" -maxdepth 3 -name 'clang*' -type f 2>/dev/null | head -10
find "$TREE/kernel_platform/prebuilts/clang" -maxdepth 4 -name 'clang' -type f 2>/dev/null | head -5

say "2) MODULE_SIG_PROTECT origin"
grep -rn 'MODULE_SIG_PROTECT' "$TREE/kernel_platform/msm-kernel/arch/arm64/configs/" 2>/dev/null | head -10
grep -rn 'MODULE_SIG_PROTECT' "$TREE/kernel_platform/msm-kernel/arch/arm64/" 2>/dev/null | head -5
grep -rn 'MODULE_SIG_PROTECT' "$TREE/vendor/oplus" 2>/dev/null | head -10
grep -rln 'MODULE_SIG_PROTECT' "$TREE/kernel_platform/msm-kernel" 2>/dev/null | head -10

say "3) abl_extensions.bzl / bootable tree"
find "$TREE" -maxdepth 6 -name 'abl_extensions.bzl' 2>/dev/null
ls -d "$TREE"/kernel_platform/bootable 2>/dev/null || echo "  no kernel_platform/bootable"
find "$TREE" -maxdepth 4 -type d -name bootable 2>/dev/null | head

say "4) kernel version (clean read)"
V=$(sed -n 's/^VERSION = //p' "$TREE/kernel_platform/common/Makefile" | head -1)
P=$(sed -n 's/^PATCHLEVEL = //p' "$TREE/kernel_platform/common/Makefile" | head -1)
S=$(sed -n 's/^SUBLEVEL = //p' "$TREE/kernel_platform/common/Makefile" | head -1)
E=$(sed -n 's/^EXTRAVERSION = //p' "$TREE/kernel_platform/common/Makefile" | head -1)
echo "  $V.$P.$S$E"

say "5) sun_perf.config size + first lines"
wc -l "$TREE/kernel_platform/msm-kernel/arch/arm64/configs/vendor/sun_perf.config"
head -5 "$TREE/kernel_platform/msm-kernel/arch/arm64/configs/vendor/sun_perf.config"
grep -c '' "$TREE/kernel_platform/msm-kernel/arch/arm64/configs/vendor/sun_oplus_common.config"
exit 0
