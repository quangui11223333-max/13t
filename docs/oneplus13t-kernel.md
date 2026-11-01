# 一加 13T（PKX110 / sun / SM8750）官方原版内核源码 —— 改内核工作手册

> 目标：拿**官方原版（未打任何第三方补丁）**的一加 13T 内核源码，自己改、自己编。
> 本文所有 commit / 分支 / 配置项都是从 OnePlusOSS 仓库实际读出来的，不是猜的。

---

## 0. 一句话结论

- **主线基线**：`OnePlusOSS` 三仓，分支 `oneplus/sm8750_b_16.0.0_oneplus_13t`，内核 **6.6.118**（`6.6.118-android15-8-o-4k`，4K 页）。
- **构建入口**：`bash kernel_platform/oplus/build/oplus_build_kernel.sh sun perf`（bazel/kleaf，mixed build：common 出 GKI，msm-kernel 出 boot.img）。
- **只能在 Linux x86_64 上编**（WSL2 / 独立 Linux / GitHub Actions）。Windows 只能用来读代码和改代码。
- **必须的坑**：`CONFIG_MODULE_SIG_PROTECT=n`、跨树补丁要打两棵树、KMI symbol list 要同步、≥25 GiB 空闲磁盘。

---

## 1. 分支 / commit 矩阵（已核对）

| 用途 | 仓库 | 分支 | HEAD commit | 对应固件 |
|---|---|---|---|---|
| msm-kernel（出 boot.img） | `OnePlusOSS/android_kernel_oneplus_sm8750` | `oneplus/sm8750_b_16.0.0_oneplus_13t` | `745702d5ed2c0435f2b1d3bb78bc4f48422d4191` | `PKX110_16.0.10.500(CN01)`，QCOM `AU_LINUX_KERNEL.PLATFORM.4.0.R1.00.00.00.061.111` |
| GKI common | `OnePlusOSS/android_kernel_common_oneplus_sm8750` | 同上 | `4d611c32bedc11cf3ae46aa5e815dfe35707b93f` | `PKX110_16.0.9.400(CN01)`，ACK `android15-6.6-2026-01_r22` |
| vendor 模块 + 设备树 + oplus 构建系统 | `OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750` | 同上 | `6a196f79f77acd55cf302e1696c038e4cad99254` | `PKX110_16.0.10.500(CN01)` |

同一批仓库还有 **ColorOS 15 基线**：`oneplus/sm8750_v_15.0.2_oneplus_13t`（老固件/想回退时用）。
其它 sm8750 机型分支（`oneplus_13`、`ace_6`、`13s`、`pad_2_pro`、`pad_3`、`ace5_pro`）**不要混用**，devicetree 与 DTBO 是按机型耦合的。

内核串固定形态：`6.6.118-android15-8-<gitsha>-4k`，「`o`」= OPLUS 魔改、`4k` = 4K 页。你自己的编译产物里这个串必须与固件里的 vendor 模块对齐，否则模块 `disagrees about version`。

---

## 2. 目标目录结构（装配后）

官方是「一个 `kernel_platform/` + 一个 `vendor/`」的 bazel 工作区，靠 **35 个依赖**（3 个 OnePlusOSS + 25 个 CodeLinaro 镜像 + 7 个 Release 镜像，共 **3.01 GiB**）拼出来：

```
oneplus13t-kernel/                 # 构建必须在这一层执行
├── kernel_platform/
│   ├── common/                    # ← android_kernel_common_oneplus_sm8750 (GKI)
│   ├── msm-kernel/                # ← android_kernel_oneplus_sm8750 (QCOM msm + OPLUS)
│   ├── build/ oplus/ qcom/ tools/ # ← modules 仓的 kernel_platform/*
│   ├── external/ prebuilts/ ...   # ← CLO/Release 依赖（clang、rust、jdk、build-tools…）
│   ├── MODULE.bazel WORKSPACE WORKSPACE.bzlmod
│   └── build_with_bazel.py
└── vendor/
    ├── oplus/{kernel,hardware,sensor,secure}   # OPLUS 私有驱动（充电/触控/显示…）
    ├── qcom/ nxp/ st/                          # WLAN/BT/Audio/Display/Camera 等
```

依赖清单落在 [scripts/deps.json](../scripts/deps.json)（每个条目有 url / 目标路径 / 字节数 / sha256）。

---

## 3. 取源码

### 3.0 最快路径：有真 Linux 机器（推荐）

Windows 侧不用折腾 WSL。把打包好的 `oneplus13t-kernel-setup.tar.gz`（20 KB）
拷到 Linux 机器上，一条命令搞定：

```bash
tar xzf oneplus13t-kernel-setup.tar.gz
cd scripts && bash bootstrap-linux.sh        # WORK=~/work/13t 可自定义
```

它会：检测发行版（apt/dnf/pacman）装依赖 → 装配 35 个依赖（3.01 GiB）→ 完整性预检
（关键文件 / 软链接 / 内核版本 / 剩余空间）→ 打印基线编译命令。
要求：`sudo`、python3、`$HOME` 剩 ≥ 60 GiB、x86_64。

### 3.1 Linux 上装配（bootstrap 内部就是这一步，也可手动跑）

```bash
# 在 Linux / WSL2 里，需要 python3（+ 可选 git）
cd /path/to/work
python3 /path/to/kernels/oneplus13t/scripts/assemble.py --root ./oneplus13t-kernel --jobs 6
```

脚本做的事：按 `deps.json` 下载 → 校验 → 剥掉归档的单一顶级前缀解到对应 `path` → 补 4 个构建必需软链接 → 报告剩余空间。

### 3.2 有 git 时（想 `git log` / `git diff` 改代码，最舒服）

```bash
mkdir -p oneplus13t-kernel/kernel_platform && cd oneplus13t-kernel/kernel_platform
B=oneplus/sm8750_b_16.0.0_oneplus_13t
git clone -b $B --depth 1 https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8750 common
git clone -b $B --depth 1 https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750      msm-kernel
cd .. && git clone -b $B --depth 1 https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750 modules
cp -r modules/kernel_platform/{build,oplus,qcom,tools,WORKSPACE,MODULE.bazel,WORKSPACE.bzlmod,build_with_bazel.py} kernel_platform/
cp -r modules/vendor kernel_platform/../   # 或直接 mv 到 oneplus13t-kernel/vendor
# 其余 32 个 CLO/预置依赖仍走 assemble.py 补
```

### 3.3 已经在 Windows 上给你抓好了一份（可读可改，不能直接编）

`kernels/oneplus13t/src/oneplus13t-kernel/` —— 3.07 GiB / 181,200 文件，结构已按上面拼好。

> ⚠️ **重要**：官方仓里 `kernel_platform/build/*.sh`、`kernel_platform/tools/bazel` 这些本身是**软链接**。Windows 解包后它们变成“内容是目标路径的小文本文件”，**在 Linux 上编会直接失败**。所以这份树用来读代码/改代码/写补丁，真编请在 Linux 侧用 3.1/3.2 重新装配。

> 另一个冷知识（作者文档已注明）：GitHub 的 `/archive/<sha>.tar.gz` **不是确定性打包**，同一 commit 每次字节数都会漂，所以按 sha256 校验必然对不上（我实测三个包都差 ~0.05%）。正确判据是“能否完整解压”（gzip CRC 兜底），只有 `release-mirror` 那几个固定 tarball 才严格校验 size+sha256。

---

## 4. 编译

```bash
cd oneplus13t-kernel
export TOPDIR=$PWD                 # oplus_setup.sh 会读
bash kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

实际展开是：

```bash
./kernel_platform/build/android/prepare_vendor.sh sun perf      # LTO=thin（perf 变体）
```

关键行为（来自 `build.config.msm.sun` / `build.config.msm.perf`）：

| 项 | 值 | 说明 |
|---|---|---|
| `PAGE_SIZE` | `4096` | 固定 4K 页，别改 |
| `BOOT_IMAGE_HEADER_VERSION` | `4` | boot.img v4 |
| `BASE_ADDRESS` | `0x80000000` | |
| `VARIANT` | `perf`（可选 `consolidate`） | 出厂固件用的是 perf |
| `BUILD_VENDOR_DLKM` / `PREPARE_SYSTEM_DLKM` | `1` / `1` | |
| `KMI_ENFORCED` | `1` | 改了导出符号就要过 ABI 检查 |
| `TRIM_NONLISTED_KMI` | `1`（perf） | 不在白名单的 KMI 会被裁掉 |
| `GKI_KMI_SYMBOL_LIST` | `../msm-kernel/android/abi_gki_aarch64_qcom` | 符号白名单 |
| `DEFCONFIG` | `gki_defconfig` + fragment | 见下一节 |

产物（`out/msm-kernel/sun_perf/` 下）：

- `dist/Image` —— 内核本体（37 MiB 量级）
- `dist/boot.img` —— 可直刷
- `dist/dtbo.img`、`dist/merged-dtbs/` —— 设备树
- `dist/*.ko` + `vendor_dlkm.modules.load` / `modules.load`

常用开关（`oplus_setup.sh` 里导出）：

```bash
export RECOMPILE_KERNEL=1      # 只重编内核
export RECOMPILE_DTBO=1        # 只重编 DTBO
export OPLUS_BUILD_KO=true     # 连 vendor ko 一起编（很慢，359 个）
export OPLUS_KO_PATH=drivers/input/touchscreen/focaltech_touch   # 只编单个 ko
export REPACK_IMG=true         # 重打包镜像
export EXTRA_KBUILD_ARGS="--skip abl"    # 默认就跳过 ABL
export OPLUS_USE_JFROG_CACHE=true        # oplus 的 bazel wrapper 支持远端缓存
```

时间基准（供你判断机器够不够）：8 核全量 **3h12m**；其中约 2h 花在 359 个 vendor ko 上，只编内核 + boot.img 才是可接受的量级。4 核 GitHub 免费 runner 只编内核约 5h+。

---

## 5. 改哪里（改内核的热区）

| 想改什么 | 改这些文件 |
|---|---|
| perf 主配置（出厂用的那套） | `kernel_platform/msm-kernel/arch/arm64/configs/vendor/sun_perf.config` |
| OPLUS 公共配置 | 同目录 `sun_oplus_common.config` |
| GKI 侧（common）配置 | `kernel_platform/common/arch/arm64/configs/gki_defconfig` |
| 构建参数/页大小/镜像头 | `msm-kernel/build.config.msm.sun`、`build.config.msm.perf`、`build.config.msm.common` |
| 调度 / 内存 / 文件系统 | `msm-kernel/kernel/sched/`、`msm-kernel/mm/`、`msm-kernel/fs/f2fs/` |
| OPLUS 私有驱动（充电、触控、显示、传感器） | `vendor/oplus/kernel/**` |
| QCOM 驱动（WLAN/BT/显示/音频/相机） | `vendor/qcom/opensource/**` |
| 设备树/机型属性 | `vendor/qcom/opensource/*-devicetree`、`vendor/oplus/**/dts`、`kernel_platform/oplus/**` |
| KMI 导出符号白名单 | `msm-kernel/android/abi_gki_aarch64_qcom` |
| 构建系统本身（bazel target/镜像组装） | `msm-kernel/sun.bzl`、`msm-kernel/msm_kernel_la.bzl`、`kernel_platform/build/android/prepare_vendor.sh` |

改配置不要手改 `.config`（会被 fragment 覆盖），**改 fragment**（`sun_perf.config` 等），或者用 `build/kernel/menuconfig.sh`。

---

## 6. 一定会踩的坑（按踩到概率排序）

1. **`CONFIG_MODULE_SIG_PROTECT`**
   自编内核没有 OPPO 的 trusted key → `mod->sig_ok=false` → `gki_is_module_protected_export()` 拒绝导出 → `rfkill → cfg80211 → mac80211 → qca_cld3` 整链加载失败 → **WiFi/蓝牙全废**。
   处理：`sun_perf.config` 里置 `# CONFIG_MODULE_SIG_PROTECT is not set`（代价是少了导出保护）。

2. **跨树补丁要打两棵树**
   `boot.img` 来自 **msm-kernel** 树；`common` 只产 GKI（Image/模块）。凡是引入跨树符号（典型：SUSFS 的 `susfs_*`）而只改了 common，链接期就会 `undefined symbol`（这就是别人的 run 挂掉的原因）。改之前先想清楚这段代码编进哪棵树。

3. **KMI / ABI 检查**
   `KMI_ENFORCED=1` + `TRIM_NONLISTED_KMI=1` + `KMI_SYMBOL_LIST_ADD_ONLY=1`：你新 `EXPORT_SYMBOL` 的东西不在 `abi_gki_aarch64_qcom` 里就会被裁，vendor 模块照样加载失败。要给外部模块用就同步 symbol list。

4. **`CONFIG_MODULE_SIG_KEY`**
   默认 `certs/signing_key.pem`，自签 key 会改模块签名链；调试期建议明确关掉签名校验相关项，量产思路另说。

5. **别一上来编 vendor ko**
   `OPLUS_BUILD_KO=true` 是 2 小时起步；先只编内核 + boot.img 验证改动，再决定要不要全量。

6. **磁盘**
   装配 3 GiB，编译中间产物轻松几十 GiB。**留 ≥25 GiB**（官方文档口径），实际建议 40 GiB+。

7. **跨大版本别当等价**
   官方只给到 `16.0.0` 分支；如果在 ColorOS 17 固件上跑，内核串同为 `6.6.118-android15-8-o-4k` 可以开机，但 vendor 模块 ABI/CRC 与 17.0.0 原厂内核的差异**没有逐项核对过**。要追 17.x 就盯着 `watch-official-source` 那类巡检，等官方开分支。

8. **`JAVA_HOME` 路径**
   `oplus_setup.sh` 里写的是 `${TOPDIR}/prebuilts/jdk/jdk21/linux-x86`，而 35 依赖里给的是 `kernel_platform/prebuilts/jdk/jdk11`。真报 JAVA_HOME 找不到，要么补 jdk21 到该路径，要么改这一行（bazel 自带 JDK 时通常不影响）。

9. **软链接**（见 §3.3）——Windows 解出来的树，`build/*.sh`、`tools/bazel` 全是坏链接。

---

## 7. 刷机与回滚

```bash
adb shell uname -r                          # 必须与自己固件小版本一致（6.6.118 / 6.6.89…）
adb shell getprop ro.build.version.oplusrom # V16.x.x
adb shell getprop ro.product.name           # PKX110 = 国行 13T
adb shell su -c "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a.img"   # 备份
```

- **AK3 包**（把编出来的 `Image` 塞进 [AnyKernel3-6.6.118-OnePlus13T-v3.6.zip](AnyKernel3-6.6.118-OnePlus13T-v3.6.zip) 骨架）：KernelSU/APatch 管理器「模块 → 从本地安装」，或 TWRP/Recovery 刷。
- **直刷 boot**：`fastboot flash boot out/msm-kernel/sun_perf/dist/boot.img`（A/B 机型注意 `_a`/`_b`）。
- **回滚**：`fastboot flash boot boot_a.img`。

---

## 8. 参考实现（抄思路，不抄闭源代码）

| 项目 | 拿来干什么 |
|---|---|
| [TanCan1998/oneplus-13t-coloros17-kernel-build](https://github.com/TanCan1998/oneplus-13t-coloros17-kernel-build) | **官方入口的完整云端流水线**：35 依赖锁、config 门禁、SUSFS 双树补丁、产物复验；`ci-assemble.py` 就是本文 §3.1 的依据 |
| [cctv18/oppo_oplus_realme_sm8750](https://github.com/cctv18/oppo_oplus_realme_sm8750) | 用 Clang 18 绕过官方 bazel 的通用 OKI 编译脚本 + ccache，编译从 1h+ 压到 6min |
| [CHIZI-0618/OnePlus13T_Kernel_Build](https://github.com/CHIZI-0618/OnePlus13T_Kernel_Build) | 最简 build 脚本（GPL-3.0），想看“最小可用编译流程”看它 |
| [whitewhale0612/...-C16](https://github.com/whitewhale0612/android_kernel_common_oneplus_sm8750-C16) | 成品特性参考：Crystal HybridSwap / ZMS / SDDC / HMBIRD / BBRv3 是怎么挂进 6.6.118 的 |
| [brokestar233/android_kernel_common_oneplus_sm8750](https://github.com/brokestar233/android_kernel_common_oneplus_sm8750) | DT overwriter / module overlay / firmware overlay 这些 SM8750 适配手法 |
| [firelzrd](https://github.com/firelzrd) (`adios`, `le9uo`) | I/O 调度与工作集保护的独立补丁，适合自己挑着合 |

---

## 9. 下一步 checklist

- [ ] 决定基线：ColorOS 16（`sm8750_b_16.0.0`）还是 15（`sm8750_v_15.0.2`）
- [ ] 拿到 Linux 环境：**真 Linux 机器 → `bootstrap-linux.sh`**（首选）；WSL2 只作兜底
- [ ] `python3 scripts/assemble.py` 装配 + 补软链接
- [ ] 先跑一次 **零改动** 编译，确认能出 boot.img 且能开机（基线验证，别省这步）
- [ ] 再改配置/代码，`git init` 或 `diff -ru` 留基线，便于回归
- [ ] 每改一处只验证一件事（先能开机 → 再能 root → 再谈性能）
