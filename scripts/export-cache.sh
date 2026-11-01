#!/usr/bin/env bash
# A 鏂规钀藉湴锛氭妸瑁呴厤濂界殑渚濊禆褰掓。锛坃dl锛夊揩鐓у洖 Windows 鐩橈紝浣滀负绂荤嚎缂撳瓨銆?# 杩欐墠鏄€屾彁鍓嶄笅杞姐€嶇湡姝ｆ湁鐢ㄧ殑褰㈡€?鈥斺€?瑁呭ソ涔嬪悗涓€娆″崟鍚戝綊妗ｏ紝
# 浠ュ悗鎹㈠熀绾?閲嶈鏍戜笉鐢ㄥ啀涓?3 GiB銆?#
# 鐢ㄦ硶锛?#   bash export-cache.sh                       # 榛樿褰掓。鍒?/mnt/d/kernel-cache/oneplus13t
#   DEST=/mnt/d/xxx bash export-cache.sh
#
# 杩樺師锛堥噸寤烘爲鏃朵紭鍏堢敤鏈湴缂撳瓨锛岄伩鍏嶉噸澶嶄笅杞斤級锛?#   cp -r /mnt/d/kernel-cache/oneplus13t/_dl ~/work/13t/_dl    # 鍏堟嫹鍥?ext4 鍐嶇敤
#   python3 ~/work/13t/assemble.py --root ~/work/13t/oneplus13t-kernel --arch-dir ~/work/13t/_dl

set -euo pipefail
SRC="${SRC:-$HOME/work/13t/_dl}"
DEST="${DEST:-/mnt/d/kernel-cache/oneplus13t}"

[ -d "$SRC" ] || { echo "_dl not found: $SRC锛堝厛璺?wsl-bootstrap.sh锛? >&2; exit 2; }
mkdir -p "$DEST/_dl"

echo "== 褰掓。 $SRC -> $DEST/_dl"
rsync -a --info=progress2 --delete --stats "$SRC/" "$DEST/_dl/"
cp -f "$(dirname "$0")/deps.json" "$DEST/deps.json" 2>/dev/null || true

echo
echo "== 娓呭崟锛堝彲鏍稿 size锛宺elease-mirror 鐨?sha256 涔熷彲鏍稿锛?
du -sh "$DEST/_dl"
ls -1 "$DEST/_dl" | wc -l | xargs echo "  褰掓。鏁?"
echo
echo "== 鎻愮ず"
echo "  D 鐩樺綋鍓嶅墿浣欙細$(df -h /mnt/d | awk 'NR==2{print $4}')"
echo "  杩欎唤缂撳瓨鍙湪 x86_64 Linux 涓婃湁鐢紙clang/rust/jdk 閮芥槸 linux-x86_64 棰勭疆浜岃繘鍒讹級"
echo "  鎹㈡満鍣?閲嶈 WSL 鍚庢妸 _dl 鎷峰洖 ext4 鍐嶄氦缁?assemble.py锛屽彲璺宠繃鍏ㄩ儴涓嬭浇"
