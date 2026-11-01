# 用 GitHub Actions 编一加 13T 内核（全量 `sun perf`）

本机只有 4 核 / 7.2 GB（可用 3.0 GiB），全量 `perf` 会 OOM；而托管 runner 是 **4 vCPU / 16 GB**，够用。
本机（Arch）只负责改代码 + `git push`，编译和出 `boot.img` 全在云端。

工作流文件：[.github/workflows/build-oneplus13t.yml](../../.github/workflows/build-oneplus13t.yml)

---

## 1. 仓库要长什么样

仓库根目录 = `kernels/oneplus13t/` 这个目录的内容：

```
.github/workflows/build-oneplus13t.yml   # 工作流本体
scripts/deps.json                        # 35 个依赖的 url/sha256（工作流靠它装配）
scripts/assemble.py                      # 装配器（含软链接修复）
scripts/repack-ak3.sh                    # 可选：把 Image 打成可刷 zip
patches/*.patch                          # 可选：你的改动（没有就零改动基线）
tools/AnyKernel3-*.zip                   # 可选：29.6 MB，有它才出可刷 zip
```

> 3 GiB 的源码树**不要提交**——runner 每次按 `deps.json` 自己拉（GitHub→GitHub 很快），
> 并用 `actions/cache` 把 `_dl` 缓存住，第二次起省 5–8 分钟。

---

## 2. 建仓并推上去（在 Arch 上做，它装了 git）

```bash
# ① 从 Windows 把这几个文件推过来（在 Windows 侧执行）：
#    tools\pscp.exe -r kernels\oneplus13t\scripts  archyouran@192.168.1.138:~/13t-repo/
#    tools\pscp.exe -r kernels\oneplus13t\.github  archyouran@192.168.1.138:~/13t-repo/

# ② 在 Arch 上：
cd ~/13t-repo
git init -b main
printf 'oneplus13t-kernel/\n_dl/\nout-artifacts/\n*.log\n' > .gitignore
git add -A && git commit -m "oneplus13t: official sm8750 kernel build via Actions"

# ③ 推到你的仓库（先在 GitHub 上建空仓库，不要勾 README）
git remote add origin https://github.com/<你的账号>/<仓库名>.git
git push -u origin main
```

推需要凭据：**用 PAT**（Settings → Developer settings → Personal access tokens → Fine-grained，勾 `Contents: Read and write`），
用户名填你的账号，密码粘 PAT。

---

## 3. 跑一次

- 进 Actions → `build-oneplus13t-kernel` → **Run workflow**
  - `variant`: `perf`（默认，日常用）/ `consolidate`（保守，LTO 也 thin 但精简变体）
  - `baseline`: 只用于标注产物，切基线要改 `scripts/deps.json` 里的分支名
- 也可以改 `patches/` 后 `git push`，`paths` 命中会自动触发

**首跑预计 1.5–2.5 小时**（含装配 5–8 分钟、LTO thin + 359 个 vendor ko）。
`concurrency` 已设成同分支只跑一个，连点不会叠。

---

## 4. 产出在哪

跑完在 run 页面底部 **Artifacts**：

| 产物 | 说明 |
|---|---|
| `oneplus13t-perf-<run>` | `Image`、`boot.img`、`dtbo.img`、`vendor_dlkm.modules.load`、`build.log` |
| `build-log-fail-<run>` | 只在失败时出现：`build.log` + `LOGDIR/**`，直接定位编译错误 |

`Verify artifacts` 这一步会打出来（看日志确认）：

- `strings Image | grep 'Linux version 6.6.'` → 应是 `6.6.118-android15-8-<sha>-4k`
- `dist/*.ko` 数量 → 应接近 **359**
- `vendor_dlkm.modules.load` 行数
- `CONFIG_MODULE_SIG_PROTECT` → 必须是 `is not set`（否则刷完 WiFi/蓝牙死，这是官方坑）
- `boot.img` 头 64 字节 → 确认 `ANDROID!` 魔数 + header version 4

---

## 5. 刷机和回滚

1. 先备份：`adb shell su -c "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a.img"`（或 recovery 里备份 boot 分区）
2. 解锁 bootloader（一加需申请深度测试），`fastboot flash boot boot.img` 或 `fastboot boot boot.img` 先试启动
3. 有 `dtbo.img` 就一起刷（改了设备树才需要）
4. 版本串必须和你的固件一致：`adb shell uname -r`、`getprop ro.build.version.oplusrom`
   —— **不一致会 `disagrees about version` 加载 ko 失败**，WiFi/相机/指纹全哑
5. 回滚：`fastboot flash boot boot_a_backup.img`，或 recovery 恢复备份

---

## 6. 常见失败与对策

| 现象 | 原因 | 对策 |
|---|---|---|
| `No space left on device` | 托管 runner 只有约 14 GB | `free-disk-space` 步骤已加；仍不够就把 `swap` 从 16 G 降到 8 G |
| bazel OOM / killed | 编译峰值内存高 | 已加 16 G swap；还不行就在 `oplus_setup.sh` 传 `--local_ram_resources=8192` |
| `disagrees about version` | ko 与 Image 版本串不一致 | 关 `CONFIG_MODULE_SIG_PROTECT`，确认 `LOCALVERSION` 一致 |
| `JAVA_HOME` 找不到 | `oplus_setup.sh` 指向 `prebuilts/jdk/jdk21` | 检查 `_dl` 里 jdk 版本；必要时 `export JAVA_HOME=$TREE/prebuilts/jdk/jdk11/linux-x86` |
| WiFi/蓝牙不起 | `CONFIG_MODULE_SIG_PROTECT=y` | 改 `sun_perf.config` 后重跑 |
| 卡在 4 小时超时 | 4 vCPU + LTO thin 太慢 | 把 `timeout-minutes` 提到 360，或去掉部分 vendor ko |

---

## 7. 和本机分工

| 在哪 | 干什么 |
|---|---|
| 本机 Arch（4 核 7.2 G） | 读代码、改代码、`git diff`、`git push`；装配树（已装好，`~/work/13t/oneplus13t-kernel`）用于**看源码和本地 grep** |
| GitHub Actions（4 核 16 G） | 全量编译、产物校验、出 `boot.img` 与可刷 zip |
| 真机 | `fastboot boot` 试启动 → 确认能开机 → 再 `flash` |
