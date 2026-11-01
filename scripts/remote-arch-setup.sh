#!/usr/bin/env bash
# Arch-specific dependency install for the OnePlus 13T kernel build.
# Runs non-interactively: password comes from $SUDOPW (default 12345678).
#
#   SUDOPW='...' bash remote-arch-setup.sh
set -u
PW="${SUDOPW:-12345678}"

say() { printf '\n== %s\n' "$*"; }

say "0) identity"
echo "  user : $(id -un)  groups: $(id -Gn)"
echo "  os   : $(. /etc/os-release; echo "$PRETTY_NAME")"
echo "  mem  : $(free -h | awk '/^Mem:/{print $2" total, "$7" available"}')"
echo "  disk : $(df -h "$HOME" | awk 'NR==2{print $4" free at "$6}')"

say "1) pacman -S --needed (no -Sy: partial upgrade is worse on Arch)"
echo "$PW" | sudo -S -p '' pacman -S --needed --noconfirm \
  base-devel rsync zip unzip bc bzip2 cpio flex bison \
  openssl libelf kmod dtc lz4 zstd lsb-release 2>&1 | tail -25
rc=${PIPESTATUS[0]}
echo "  pacman exit: $rc"

say "2) verify required tools"
miss=0
for t in rsync unzip zip bc cpio flex bison dtc lz4 zstd python3 git gcc make ld; do
  if command -v "$t" >/dev/null; then
    printf '  ok   %-9s %s\n' "$t" "$(command -v "$t")"
  else
    printf '  MISS %-9s\n' "$t"; miss=1
  fi
done

say "3) kernel build prerequisites not packaged as binaries"
echo "  (clang / rust / jdk / build-tools come from the 35 vendored deps, not from pacman)"

say "4) result"
[ "$miss" = 0 ] && echo "  ALL PRESENT -- ready for assemble.py" || echo "  something missing, see MISS above"
exit 0
