#!/usr/bin/env bash
# OnePlus 13T (PKX110 / sun / SM8750) official kernel -- bootstrap on a real Linux box.
#
#   bash bootstrap-linux.sh                     # auto-detect, install deps, assemble, preflight
#   WORK=~/work/13t bash bootstrap-linux.sh     # custom work dir (default: ~/work/13t)
#   JOBS=8 bash bootstrap-linux.sh              # parallel downloads
#   SKIP_DEPS=1 bash bootstrap-linux.sh         # assume packages already installed
#
# Needs: sudo (for packages), python3, curl. Everything else is installed here.
# Disk: 3 GiB sources + 30-60 GiB build output. Keep >= 60 GiB free on $HOME.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-$HOME/work/13t}"
TREE="$WORK/oneplus13t-kernel"
ARCH="$WORK/_dl"
JOBS="${JOBS:-$(nproc)}"

say() { printf '\n=== %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 2; }

say "0/5 host check"
. /etc/os-release 2>/dev/null || true
echo "  distro : ${PRETTY_NAME:-unknown}"
echo "  kernel : $(uname -r)  arch: $(uname -m)"
echo "  cpu    : $(nproc) threads   mem: $(free -h | awk '/^Mem:/{print $2}')"
echo "  home   : $(df -h "$HOME" | awk 'NR==2{print $4" free on "$6}')"
[ "$(uname -m)" = "x86_64" ] || echo "  WARN: prebuilt clang/rust are linux-x86_64; $(uname -m) may fail"
FREE_GIB=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc '0-9')
[ "${FREE_GIB:-0}" -ge 60 ] || echo "  WARN: only ${FREE_GIB} GiB free in \$HOME, want >= 60 GiB"
[ -f "$HERE/deps.json" ] || die "deps.json not found next to this script (copy the whole scripts/ dir)"
[ -f "$HERE/assemble.py" ] || die "assemble.py not found next to this script"

say "1/5 install build dependencies"
if [ "${SKIP_DEPS:-0}" = "1" ]; then
  echo "  skipped (SKIP_DEPS=1)"
elif command -v apt-get >/dev/null; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential git python3 rsync zip unzip bc bzip2 cpio flex bison \
    libssl-dev libelf-dev kmod device-tree-compiler file
elif command -v dnf >/dev/null; then
  sudo dnf install -y gcc gcc-c++ make git python3 rsync zip unzip bc bzip2 cpio \
    flex bison openssl-devel elfutils-libelf-devel kmod dtc
elif command -v pacman >/dev/null; then
  sudo pacman -Sy --needed --noconfirm base-devel git python rsync zip unzip bc cpio \
    flex bison openssl libelf kmod dtc
else
  die "unknown package manager; install manually: gcc make git python3 rsync zip unzip bc bzip2 cpio flex bison libssl-dev libelf-dev kmod dtc"
fi
echo "  gcc: $(gcc --version | head -1)"

say "2/5 prepare $WORK"
mkdir -p "$WORK" "$ARCH" "$TREE"
cp -f "$HERE/"{deps.json,assemble.py,build.sh,repack-ak3.sh} "$WORK/" 2>/dev/null || true
ls -1 "$WORK"

say "3/5 assemble 35 official deps (~3.01 GiB, first run 10-30 min)"
cd "$WORK"
python3 assemble.py --root "$TREE" --arch-dir "$ARCH" --jobs "$JOBS"

say "4/5 preflight the assembled tree"
cd "$TREE"
missing=0
for p in kernel_platform/common/Makefile \
         kernel_platform/msm-kernel/build.config.msm.sun \
         kernel_platform/msm-kernel/sun.bzl \
         kernel_platform/oplus/build/oplus_build_kernel.sh \
         kernel_platform/msm-kernel/arch/arm64/configs/vendor/sun_perf.config \
         kernel_platform/prebuilts/clang/host/linux-x86 \
         vendor/oplus/kernel; do
  if [ -e "$p" ]; then echo "  ok   $p"; else echo "  MISS $p"; missing=1; fi
done
printf '  kernel version: '; awk '/^(VERSION|PATCHLEVEL|SUBLEVEL)/{printf "%s%s",(NR>1?".":""),$3}' kernel_platform/common/Makefile; echo
sb=0
for f in kernel_platform/tools/bazel kernel_platform/build/android/prepare_vendor.sh; do
  [ -L "$f" ] || { echo "  BAD  $f is not a symlink"; sb=1; }
done
[ "$sb" = 0 ] && echo "  symlinks: ok"
echo "  free after assemble: $(df -h . | awk 'NR==2{print $4}')"

say "5/5 done"
[ "$missing" = 0 ] || echo "  NOTE: some deps missing above -- rerun: python3 $WORK/assemble.py --root $TREE --arch-dir $ARCH --only <name>"

cat <<EOF

==========================================================
Baseline build first (zero changes, verify it boots):

  cd $TREE
  bash $WORK/build.sh              # = oplus_build_kernel.sh sun perf
  # artifact: out/msm-kernel/sun_perf/dist/{Image,boot.img,dtbo.img}

Then repack into a flashable zip:

  bash $WORK/repack-ak3.sh -k $TREE/out/msm-kernel/sun_perf/dist/Image

Keep an offline copy of the deps for future rebuilds:

  mkdir -p ~/kernel-cache && rsync -a $ARCH/ ~/kernel-cache/_dl/
==========================================================
EOF
