#!/usr/bin/env bash
# 严格照 oplus_setup.sh 的变量，逐个验证打包 boot.img 需要的路径是否存在。
set -u
TOPDIR="${1:-$HOME/work/13t/oneplus13t-kernel}"
ACKDIR="$TOPDIR/kernel_platform"
MISS=0
OK=0
chk() { # chk <描述> <路径>
  if [ -e "$2" ]; then OK=$((OK+1)); printf '  ok    %-34s %s\n' "$1" "${2#$TOPDIR/}"
  else MISS=$((MISS+1)); printf '  MISS  %-34s %s\n' "$1" "${2#$TOPDIR/}"; fi
}

echo "== TOPDIR=$TOPDIR"
echo "== 1) JAVA_HOME 相关（oplus_setup.sh:41 硬编码 jdk21）"
chk "TOPDIR/prebuilts/jdk/jdk21"        "$TOPDIR/prebuilts/jdk/jdk21/linux-x86"
chk "ACKDIR/prebuilts/jdk/jdk11"        "$ACKDIR/prebuilts/jdk/jdk11/linux-x86/bin/java"
chk "ACKDIR/prebuilts/jdk/jdk21"        "$ACKDIR/prebuilts/jdk/jdk21/linux-x86"

echo "== 2) 打包工具链（缺一个就出不了 boot.img）"
chk "python3"        "$ACKDIR/prebuilts/build-tools/path/linux-x86/python3"
chk "cpio"           "$ACKDIR/prebuilts/build-tools/path/linux-x86/cpio"
chk "lz4"            "$ACKDIR/prebuilts/kernel-build-tools/linux-x86/bin/lz4"
chk "simg2img"       "$ACKDIR/prebuilts/kernel-build-tools/linux-x86/bin/simg2img"
chk "img2simg"       "$ACKDIR/prebuilts/kernel-build-tools/linux-x86/bin/img2simg"
chk "mkfs.erofs"     "$ACKDIR/prebuilts/kernel-build-tools/linux-x86/bin/mkfs.erofs"
chk "build_image"    "$ACKDIR/prebuilts/kernel-build-tools/linux-x86/bin/build_image"
chk "mkdtimg"        "$ACKDIR/prebuilts/kernel-build-tools/linux-x86/bin/mkdtimg"
chk "mkbootfs"       "$ACKDIR/prebuilts/kernel-build-tools/linux-x86/bin/mkbootfs"
chk "avbtool"        "$ACKDIR/prebuilts/kernel-build-tools/linux-x86/bin/avbtool"
chk "llvm-strip"     "$ACKDIR/prebuilts/clang/host/linux-x86/llvm-binutils-stable/llvm-strip"
chk "mkbootimg.py"   "$ACKDIR/tools/mkbootimg/mkbootimg.py"
chk "unpack_bootimg" "$ACKDIR/tools/mkbootimg/unpack_bootimg.py"

echo "== 3) OPLUS 原厂镜像模板（repack 的输入，缺了必失败）"
chk "prebuild dir"   "$ACKDIR/oplus/prebuild"
chk "origin_img"     "$ACKDIR/oplus/prebuild/origin_img"
chk "boot_tmp"       "$ACKDIR/oplus/prebuild/boot_tmp"
chk "vendor_boot_tmp" "$ACKDIR/oplus/prebuild/vendor_boot_tmp"
chk "oplus/tools"    "$ACKDIR/oplus/tools"

echo "== 4) oplus/prebuild 里到底有什么"
if [ -d "$ACKDIR/oplus/prebuild" ]; then
  du -sh "$ACKDIR/oplus/prebuild" 2>/dev/null
  find "$ACKDIR/oplus/prebuild" -maxdepth 2 -type f 2>/dev/null | head -20 | sed "s|$ACKDIR/||"
else
  echo "  (目录不存在)"
fi

echo "== 5) 结论: ok=$OK  missing=$MISS"
exit 0
