# xpeng_kernel_susfs（摩托罗拉 xpeng 内核编译）

> **🌐 语言切换**: [English](README.md) | [**简体中文**](README_zh.md)

> **⚠️ 重要声明：本仓库及内核侧 SUSFS / 模块适配为 100% AI 生成（100% AI-GENERATED）。**
> 编译脚本 fork 自 [LuoJuly/android_kernel_motorola_xpeng_build](https://github.com/LuoJuly/android_kernel_motorola_xpeng_build)；
> SUSFS 及可选模块适配由 AI 依据 [LuoJuly sm7325 `lineage-23.2-SUSFS` 分支](https://github.com/LuoJuly/android_kernel_motorola_sm7325/tree/lineage-23.2-SUSFS) 完成，
> 并经本地 WSL 实际编译、刷机、开机验证。
> **刷机有风险，后果自负。**

> ⚠️ **AI 接管提示**：接手前请先阅读 [`docs/AI_HANDOVER_zh.md`](docs/AI_HANDOVER_zh.md) —— 记录了本次适配的全部踩坑、解决方案、GitHub Actions 流程、验证方法。

---

## 📱 项目简介

摩托罗拉 **xpeng**（Edge S30 XT2175-2 / G200 5G XT2175-1）**5.4.302 内核**编译脚本仓库，
内置 **ReSukiSU（KernelSU 分支）**，支持 **SUSFS v2.2 / v2.3 双版本可选**，并可选开启：

| 模块 | 说明 |
|------|------|
| **SUSFS v2.2** | Secure User File System（SUS_PATH / SUS_MOUNT / SUS_KSTAT / SPOOF_UNAME / OPEN_REDIRECT / SUS_MAP 等）。**长期验证的稳定版本，推荐日常使用。** |
| **SUSFS v2.3** | 较新版本，kstat/STATX 重构 + 更完整的 hook 覆盖。已通过编译与开机验证；**如遇到任何 bug，可自行切回 v2.2**。 |
| **Re:Kernel** | v8.5，进程/app 检测（binder + signal hooks） |
| **DroidSpaces** | IPC/PID 命名空间、POSIX_MQUEUE、DEVTMPFS、netfilter/IP_SET、tmpfs ACL/XATTR |
| **Baseband-guard** | BBGuard 电话基带 LSM |
| **BBRv3** | 内置 BBRv3 TCP 拥塞控制代码，默认 `bbr` + `fq` pacing |

> **当前状态（2026-09-26）**：SUSFS **v2.2 与 v2.3** 的模块全开版本均已在 Edge S30 上刷机并**成功开机**。
> 旧 `-modules-nosec` 分支因 BBRv3 改动导致卡开机，已废弃，切勿复用。

### SUSFS 版本对照

| SUSFS 版本 | 内核分支 | 稳定性 | 建议 |
|---|---|---|---|
| **v2.2**（默认） | `5.4.302-s3rxc32.33-8-25-susfs-modules` | ✅ 长期验证，稳定 | **日常使用推荐** |
| **v2.3** | `5.4.302-s3rxc32.33-8-25-susfs-modules-v2.3-astide` | ⚠️ 较新，已通过编译 + 开机验证 | 想尝鲜可用；**有 bug 就回退 v2.2** |

两个版本是**两条独立内核分支**，产物互不兼容，切换只需改一个开关，无需改其他配置。

---

## 🧠 仓库拓扑（两个仓库，缺一不可）

| 仓库 | 角色 | 分支 |
|------|------|------|
| **paulcbfly/xpeng_kernel_susfs**（本仓库） | 编译脚本 + GitHub Actions workflow | `5.4.302-s3rxc32.33-8-25-ReSukiSU` |
| **paulcbfly/android_kernel_motorola_xpeng** | 内核源码 + 全部适配 commit | `…-susfs-modules`（v2.2）<br>`…-susfs-modules-v2.3-astide`（v2.3） |

- 编译仓库**不包含内核源码**，Actions 运行时自动 `git clone` 内核仓库对应分支。
- 内核分支 `5.4.302-s3rxc32.33-8-25-susfs-modules`（**SUSFS v2.2**）：
  - 基座 = 上游 `5.4.302-s3rxc32.33-8-25`
  - + SUSFS v2.2 适配 commit `b3ecce7eb`
  - + 四模块移植 commit `8972cd10c`（Re:Kernel / DroidSpaces / BBGuard / BBRv3）
  - + fq 默认 qdisc commit `b565fa013`
- 内核分支 `5.4.302-s3rxc32.33-8-25-susfs-modules-v2.3-astide`（**SUSFS v2.3**）：
  - 基于 CVE 分支（含 rtmutex / kgsl 安全补丁）
  - + SUSFS v2.3 核心替换（`751b68d7e`）
  - + hook 适配两轮：`a2c9002c4`（proc_namespace/proc-fd/task_mmu/statfs）、
    `4ac98a8fc`（stat/statfs/fdinfo/readdir）
- 子模块：`KernelSU` → ReSukiSU @ `59c99fdf`（固定）

---

## 🎛️ GitHub Actions 开关

workflow_dispatch 提供 **SUSFS 版本选择 + 4 个可选模块开关**（模块默认全部勾选）：

| 开关 | 说明 |
|---|---|
| `susfs_version` | **`v2.2`（默认，稳定）/ `v2.3`** —— 决定使用哪条内核分支 |
| `enable_rekernel` | Re:Kernel v8.5 |
| `enable_droidspaces` | DroidSpaces 命名空间/netfilter/tmpfs 配置 |
| `enable_bbguard` | Baseband-guard LSM |
| `enable_bbrv3` | BBRv3 TCP 拥塞控制 |

> **回退方式**：把 `susfs_version` 选成 `v2.2` 重新跑一次 workflow 即可。本地构建则设 `SUSFS_VERSION=v2.2`。
>
> ⚠️ **关键修复**：旧工作流曾写 `${{ inputs.x || 'true' }}`，导致取消勾选也强制开启。现已改为 `${{ inputs.enable_x }}`，取消勾选真正生效。

## 📦 产物命名

产物名会带上 **SUSFS 版本标识**，v2.2 / v2.3 永不混淆：

`AK3-xpeng-EdgeS30-<模块后缀>-<SUSFS版本>-<build>.zip`

| 勾选组合 | 产物名示例 |
|---|---|
| v2.3 · 全开 | `AK3-xpeng-EdgeS30-ReKernel-DroidSpaces-BBGuard-BBRv3-SUSFSv2.3-r123.zip` |
| v2.2 · 全开 | `AK3-xpeng-EdgeS30-ReKernel-DroidSpaces-BBGuard-BBRv3-SUSFSv2.2-r123.zip` |
| v2.2 · 只开 SUSFS | `AK3-xpeng-EdgeS30-SUSFSv2.2-r123.zip` |

Release 页 `RELEASE_NOTES.md` 会列出 **SUSFS 版本 + 每个功能的 ✅/❌ 勾选状态**。

---

## 🛠️ 使用方法（刷机）

### fastboot 方式

```bash
fastboot reboot fastboot
fastboot flash boot boot_ksu.img
# 若需要：
fastboot -w
```

### AnyKernel3 方式（推荐）

在 recovery / Kernel Flasher 中刷入 `AK3-*.zip`。
它会安装内核并把 WiFi `.ko` 推送到 `/vendor/lib/modules/`（`do.modules=1`）。
**刷完 AnyKernel3 后不要再安装 KernelSU WiFi 模块。**

### 独立 WiFi 包

仅当用 fastboot 刷了 `boot_ksu.img` 时需要（该方式不替换 vendor ko）。
首次开机后用 ReSukiSU Manager 安装 WiFi 模块再重启。

---

## 🔄 手动触发编译

### 网页触发

Actions → `xpeng 5.4.302 ReSukiSU Boot/Kernel...` → **Run workflow** → 勾选/取消模块 → Run。

### CLI 触发

```bash
gh workflow run build-resukisu-edge-s30.yml --ref 5.4.302-s3rxc32.33-8-25-ReSukiSU
gh workflow run build-resukisu-g200.yml --ref 5.4.302-s3rxc32.33-8-25-ReSukiSU

gh run list --workflow build-resukisu-edge-s30.yml --limit 3
```

每月 1 日 UTC 00:00（Edge S30）/ 02:00（G200）自动编译（schedule），默认全开模块。

---

## 🏠 本地构建（Linux 容器/虚拟机已验证）

```bash
export VARIANT=edge-s30      # 或 g200（ENABLE_NFC=true）
export ENABLE_NFC=false

# 选择 SUSFS 版本（默认 v2.2）：
export SUSFS_VERSION=v2.2    # v2.2 = 稳定（推荐） | v2.3 = 较新，有 bug 可回退
# 脚本会自动据此选内核分支：
#   v2.2 -> 5.4.302-s3rxc32.33-8-25-susfs-modules
#   v2.3 -> 5.4.302-s3rxc32.33-8-25-susfs-modules-v2.3-astide

export RESUKISU_VERSION=pinned # pinned | custom
# export RESUKISU_CUSTOM_REF=<commit/branch/tag>  # 仅当 RESUKISU_VERSION=custom 时使用
export KERNEL_URL=https://github.com/paulcbfly/android_kernel_motorola_xpeng.git
# 如需强制指定分支（会覆盖 SUSFS_VERSION 的映射）：
# export KERNEL_BRANCH=<branch>
./scripts/ci/build_resukisu_boot.sh
```

产物：`.ci-work/<variant>/release/`

- `boot_ksu.img` / `Image`
- `wlan_crc_match_*.zip`
- `AK3-*.zip`

> 完整本地构建需下载 clang-r383902b1（约 1.4GB）+ GCC 4.9（约 91MB），磁盘需 >20GB 空闲。
> 完整成功构建耗时约 **43 分钟**（16 核 / 7.4G RAM + 9G swap / JOBS=8）。

---

## 📚 相关文档

- [`docs/AI_HANDOVER_zh.md`](docs/AI_HANDOVER_zh.md) — **AI 交接文档（中文）**：全部编译问题、解决方案、验证方法、升级路径
- [`docs/AI_HANDOVER.md`](docs/AI_HANDOVER.md) — AI 交接文档（英文版）
- [`docs/ARCHIVE-2026-09-25-modules-local.md`](docs/ARCHIVE-2026-09-25-modules-local.md) — 基础模块全开版本归档
- [`docs/ARCHIVE-2026-09-25-cve.md`](docs/ARCHIVE-2026-09-25-cve.md) — CVE 反向移植版本归档

---

*README 中文版更新于 2026-09-26。本仓库为 100% AI 生成项目。*
