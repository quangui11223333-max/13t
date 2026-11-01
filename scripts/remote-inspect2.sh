#!/usr/bin/env bash
# Round 2: clang-r510928, abl_extensions references, gki_defconfig SIG_PROTECT in both trees.
set -u
TREE="${1:-$HOME/work/13t/oneplus13t-kernel}"
say() { printf '\n== %s\n' "$*"; }

say "1) clang-r510928 --version"
CL="$TREE/kernel_platform/prebuilts/clang/host/linux-x86/clang-r510928"
ls "$CL/bin" 2>/dev/null | head -8
"$CL/bin/clang" --version 2>&1 | head -3
echo "  clang-stable:"; ls -ld "$TREE/kernel_platform/prebuilts/clang/host/linux-x86/clang-stable" 2>/dev/null

say "2) who references abl_extensions.bzl"
grep -rn 'abl_extensions' "$TREE/kernel_platform/build/" 2>/dev/null | head -10
grep -rn 'abl_extensions' "$TREE/kernel_platform/" --include='*.bzl' --include='*.bazel' 2>/dev/null | head -10

say "3) bootable / edk2 anywhere?"
find "$TREE" -maxdepth 5 -type d \( -name bootable -o -name edk2 \) 2>/dev/null | head
ls "$TREE/kernel_platform/" | head -30

say "4) MODULE_SIG_PROTECT in common gki_defconfig"
grep -n 'MODULE_SIG' "$TREE/kernel_platform/common/arch/arm64/configs/gki_defconfig" 2>/dev/null | head
echo "  -- msm-kernel gki_defconfig:"; grep -n 'MODULE_SIG' "$TREE/kernel_platform/msm-kernel/arch/arm64/configs/gki_defconfig" 2>/dev/null | head

say "5) which defconfig does sun perf use?"
grep -nE 'DEFCONFIG|FRAGMENT|gki_defconfig|sun_perf' "$TREE/kernel_platform/msm-kernel/build.config.msm.sun" 2>/dev/null | head -20
echo "  -- build.config.msm.common (if any):"
grep -nE 'DEFCONFIG|FRAGMENT' "$TREE/kernel_platform/msm-kernel/build.config.msm.common" 2>/dev/null | head -10

say "6) sun_oplus_common.config really empty?"
wc -c "$TREE/kernel_platform/msm-kernel/arch/arm64/configs/vendor/sun_oplus_common.config" 2>/dev/null
ls -la "$TREE/kernel_platform/msm-kernel/arch/arm64/configs/vendor/" | head -12
exit 0
