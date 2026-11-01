# 这台 Arch 的定位与日常改内核流程

实测时间：装完源码树之后（就是这次）

```
CPU        4 核             load average 1.40 / 1.70 / 1.91
内存       7.2 GiB 总       已用 4.6 GiB / available 只剩 2.5 GiB
Swap       3.6 GiB         已用 1.3 GiB
/home      77 G            已用 20 G，剩 54 G
~/work/13t 14 G            源码树 11 G + _dl 3.1 G
```

## 结论先说：这台机器不编译内核，只改代码

不是"慢一点也能跑"，是**跑不了**：

| 阶段 | 峰值内存需求 | 这台机器 |
|---|---|---|
| GKI `common` 单编 | 6–8 GB | 只有 2.5 GB 可用 |
| 全量 `sun perf`（LTO thin + 359 个 vendor ko） | 12–16 GB | 差一个数量级 |

而且机器上已经跑着这些常驻东西（实测 RSS）：

| 进程 | RSS | 是什么 |
|---|---|---|
| `llama-server` | **1.0 GB** | 本地模型服务 |
| `python main.py` | 534 MB | AstrBot |
| `Isolated Web Co` + `firefox` | 482 + 474 MB | 浏览器 |
| `qq` 主进程 + 若干 zygote | 336 MB + 6×40–220 MB | NapCat 用的 QQ 客户端 |
| `qzone_post.py` / node bridge | 29 MB + 96 MB | 你的 QQ 空间推送 |
| docker `napcat` + `astrbot` | — | 容器 |

用户级 systemd 在跑：`hostctl.service`、`onebot-qzone.service`、`qzone-post.service`。

把 LTO 链接塞进这堆里，结果是 **OOM killer 挑一个杀**——大概率挑中 AstrBot 或 QQ，机器人直接掉线，而且内核编译也会因为被 OOM 打断而白跑几小时。所以：

- **编译 → GitHub Actions**（4 vCPU / 16 GB + 16 G swap），见 [actions-setup.md](actions-setup.md)
- **这台 Arch → 改代码 + `git diff` 出补丁 + 看源码**

## 什么时候真的非要在本机编

只有一种情况值得：你怀疑是编译器/环境问题而不是代码问题，需要一个 10 分钟级别的快速验证。做法是先腾机器：

```bash
# 1) 停机器人和它的伴生服务
systemctl --user stop hostctl.service onebot-qzone.service qzone-post.service
docker stop napcat astrbot
pkill -f llama-server        # 1 GB
pkill -f '/opt/QQ/qq'        # QQ 客户端本体

# 2) 看回来了多少
free -h

# 3) 还不够就临时扩 swap（磁盘够，54 G 可用）
sudo fallocate -l 16G /swapfile2
sudo chmod 600 /swapfile2 && sudo mkswap /swapfile2 && sudo swapon /swapfile2

# 4) 低优先级编，只编 GKI 那一半（不打包 boot.img）
cd ~/work/13t/oneplus13t-kernel
nice -n 19 ionice -c3 bash kernel_platform/oplus/build/oplus_build_kernel.sh sun perf

# 5) 编完把 swap 收掉、服务起回来
sudo swapoff /swapfile2 && sudo rm /swapfile2
docker start napcat astrbot
systemctl --user start hostctl.service onebot-qzone.service qzone-post.service
```

**别做**：在这台机器上编全量并期望它跑完。4 核 + LTO thin，官方 8 核要 3h12m，这里至少 8 小时起步，中途还被 OOM 打断。

## 给机器人加个内存上限（建议做，防它自己涨）

编译不在这台跑之后，这个不是必须的，但能让机器更稳：

```bash
systemctl --user edit astrbot          # 换成你实际的服务名
# 在打开的编辑器里写：
# [Service]
# MemoryMax=1G
# MemoryHigh=800M

systemctl --user daemon-reload && systemctl --user restart astrbot
```

`llama-server` 同理（`MemoryMax=2G`），这样它不会在内存紧张时把系统拖进 swap 抖动。

## 日常改内核的闭环（已经给你搭好了）

源码树已经是一个 git 仓库，两个提交：

```
<sha>  local: disable CONFIG_MODULE_SIG_PROTECT (WiFi/BT modules must load)
<sha>  baseline: official OnePlus 13T (PKX110/sun/SM8750) 6.6.118 arm64 4k
```

所以"改了什么"随时能看，也能一键变成 Actions 吃的补丁：

```bash
cd ~/work/13t/oneplus13t-kernel

# 改代码（改完先看改了什么）
git status
git diff --stat
git diff kernel_platform/msm-kernel/drivers/xxx/yyy.c

# 变成补丁，丢给仓库的 patches/
git diff > ~/13t-repo/patches/0002-my-change.patch
#   注意：多个文件一起改就一条 diff 全带上；只挑部分改动用
#   git diff -- <路径>

# 想丢掉改动回到基线
git checkout -- <路径>

# 想从零重来（源码被搞乱了）
git reset --hard HEAD
```

补丁进仓库后 `git push`（Windows 侧用 `scripts\push-repo.ps1 -Token ...`），
Actions 里 `patches/*.patch` 会被自动 `git apply`，编完把 `boot.img` 当 artifact 给你。

## 排除在 git 之外的东西（有意的）

`.git/info/exclude` 里排掉了：`prebuilts/`、`external/`、`tools/`、`qcom/`、`common-modules/`、`out/`、`LOGDIR/`。

理由：这些是**工具链和第三方依赖**，不是你要改的代码，加进去会让 `.git` 膨胀到几个 G 且让 `git status` 变慢。真需要改它们时用 `git add -f <路径>`。

## 磁盘预算

| 项目 | 现在 | 还会涨 |
|---|---|---|
| `~/work/13t/_dl` | 3.1 G | 不动（离线缓存，重装树要用） |
| `~/work/13t/oneplus13t-kernel` | 11 G | `.git` 约 +1–2 G |
| 本机若真编一次 `out/` | — | +30–40 G |

54 G 可用够用，但**本机编一次就会掉到 15 G 左右**，编完记得 `rm -rf out/`。

## 别忘的两件事

1. **版本串必须和手机固件匹配**：`6.6.118` 对应 ColorOS 16.x/17。刷前用
   `adb shell uname -r` 和 `getprop ro.build.version.oplusrom` 核对，
   不一致会导致 `disagrees about version`，模块加载失败、WiFi/相机/指纹全哑。
2. **`CONFIG_MODULE_SIG_PROTECT` 必须关**（`patches/0001` 已经做了）。这是自编内核最常见的"能开机但 WiFi 死"。
