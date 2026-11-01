#!/usr/bin/env bash
# 摸清这台 Arch 上 QQ 机器人怎么跑的，以及编译期可用资源。
set -u
say() { printf '\n== %s\n' "$*"; }

say "0) 机器"
nproc
free -h
df -h /home | tail -1
uptime

say "1) systemd 里像机器人的服务"
systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null \
  | grep -iE 'qq|bot|napcat|nonebot|lagrange|mirai|astrbot|onebot' || echo "  (none)"

say "2) 用户级 systemd"
systemctl --user list-units --type=service --state=running --no-pager --no-legend 2>/dev/null \
  | grep -iE 'qq|bot|napcat|nonebot|lagrange|mirai|astrbot|onebot' || echo "  (none)"

say "3) docker 容器"
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null || echo "  (docker 不可用或无权限)"

say "4) 进程里像机器人的"
ps -eo pid,ppid,rss,pcpu,etime,comm,args --sort=-rss 2>/dev/null | head -1
ps -eo pid,ppid,rss,pcpu,etime,comm,args --sort=-rss 2>/dev/null \
  | grep -iE 'qq|bot|napcat|nonebot|lagrange|mirai|astrbot|onebot|node|python' \
  | grep -v grep | head -15 || echo "  (none)"

say "5) 占内存前 8"
ps -eo pid,rss,comm --sort=-rss 2>/dev/null | head -9

say "6) ccache / 编译缓存现状"
command -v ccache >/dev/null && { ccache --version | head -1; ccache -s 2>/dev/null | head -6; } || echo "  ccache 未安装"
echo "  bazel: $(command -v bazel || echo none)"
ls -d "$HOME/.cache/bazel" 2>/dev/null && du -sh "$HOME/.cache/bazel" 2>/dev/null

say "7) 已经占掉的空间"
du -sh "$HOME/work/13t" 2>/dev/null
du -sh "$HOME/.cache" 2>/dev/null
