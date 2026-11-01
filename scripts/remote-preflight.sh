#!/usr/bin/env bash
# Preflight an assembled OnePlus 13T kernel tree. Read-only: builds nothing.
#   bash remote-preflight.sh [TREE_DIR]
set -u
TREE="${1:-$HOME/work/13t/oneplus13t-kernel}"

say() { printf '\n== %s\n' "$*"; }
ok()  { printf '  ok    %s\n' "$*"; }
bad() { printf '  MISS  %s\n' "$*"; FAILED=$((FAILED+1)); }
FAILED=0

say "0) tree"
[ -d "$TREE" ] || { echo "no tree at $TREE"; exit 2; }
echo "  path   : $TREE"
echo "  size   : $(du -sh "$TREE" | cut -f1)"
echo "  entries: $(find "$TREE" | wc -l)  files: $(find "$TREE" -type f | wc -l)"
echo "  free   : $(df -h "$TREE" | awk 'NR==2{print $4}')"

say "1) source trees"
for p in \
  kernel_platform/common/Makefile \
  kernel_platform/common/arch/arm64/configs/gki_defconfig \
  kernel_platform/msm-kernel/build.config.msm.sun \
  kernel_platform/msm-kernel/sun.bzl \
  kernel_platform/msm-kernel/arch/arm64/configs/vendor/sun_perf.config \
  kernel_platform/msm-kernel/arch/arm64/configs/vendor/sun_oplus_common.config \
  kernel_platform/msm-kernel/android/abi_gki_aarch64_qcom \
  kernel_platform/oplus/build/oplus_build_kernel.sh \
  kernel_platform/oplus/build/oplus_setup.sh \
  kernel_platform/build/android/prepare_vendor.sh \
  vendor/oplus/kernel ; do
  [ -e "$TREE/$p" ] && ok "$p" || bad "$p"
done

say "2) required symlinks (Windows-extracted trees get these wrong)"
for l in \
  kernel_platform/.source_date_epoch_dir \
  kernel_platform/build_with_bazel.py \
  kernel_platform/build/msm_kernel_extensions.bzl \
  kernel_platform/build/abl_extensions.bzl \
  kernel_platform/tools/bazel ; do
  if [ -L "$TREE/$l" ]; then
    tgt=$(readlink "$TREE/$l")
    if [ -e "$TREE/$l" ]; then ok "$l -> $tgt"; else bad "$l -> $tgt (dangling)"; fi
  elif [ -e "$TREE/$l" ]; then
    printf '  WARN  %s exists but is NOT a symlink (%s bytes)\n' "$l" "$(stat -c%s "$TREE/$l")"
  else
    bad "$l"
  fi
done

say "3) version"
awk '/^(VERSION|PATCHLEVEL|SUBLEVEL)/{printf "%s%s",(NR>1?".":""),$3}' "$TREE/kernel_platform/common/Makefile"; echo
grep -m1 -r 'LOCALVERSION' "$TREE/kernel_platform/common/Makefile" 2>/dev/null || true

say "4) prebuilt toolchain"
CL=$(ls -d "$TREE"/kernel_platform/prebuilts/clang/host/linux-x86/clang-* 2>/dev/null | head -1)
if [ -n "$CL" ]; then
  echo "  clang dir: ${CL#$TREE/}"
  "$CL/bin/clang" --version 2>&1 | head -2 | sed 's/^/    /'
else
  bad "clang prebuilt"
fi
JDK=$(ls -d "$TREE"/kernel_platform/prebuilts/jdk/jdk* 2>/dev/null | head -1)
[ -n "$JDK" ] && ok "jdk: ${JDK#$TREE/}" || bad "prebuilts/jdk"
[ -x "$TREE/kernel_platform/prebuilts/build-tools/linux-x86/bin/make" ] && ok "prebuilt make" || echo "  note: no prebuilt make (system make will be used)"
ls -d "$TREE"/kernel_platform/prebuilts/rust/linux-x86/* >/dev/null 2>&1 && ok "rust prebuilt" || bad "prebuilts/rust"

say "5) vendor config guard (the WiFi/BT killer)"
for c in "$TREE"/kernel_platform/msm-kernel/arch/arm64/configs/vendor/sun_perf.config \
         "$TREE"/kernel_platform/msm-kernel/arch/arm64/configs/vendor/sun_oplus_common.config; do
  printf '  %s:\n' "$(basename "$c")"
  grep -E 'MODULE_SIG_PROTECT|MODULE_SIG_KEY|MODULE_SIG=' "$c" 2>/dev/null | sed 's/^/    /' || echo "    (no MODULE_SIG entries)"
done

say "6) build entry dry look"
grep -nE 'prepare_vendor\.sh|LTO' "$TREE/kernel_platform/oplus/build/oplus_build_kernel.sh" | sed 's/^/  /'

say "7) verdict"
if [ "$FAILED" -eq 0 ]; then
  echo "  READY -- tree is complete, symlinks real, toolchain present"
else
  echo "  $FAILED item(s) missing -- rerun assemble.py or fix the symlinks above"
fi
exit 0
