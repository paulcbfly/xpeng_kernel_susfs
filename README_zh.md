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
内置 **ReSukiSU（KernelSU 分支）+ SUSFS v2.2.0**，并可选开启：

| 模块 | 说明 |
|------|------|
| **SUSFS** | Secure User File System（SUS_PATH / SUS_MOUNT / SUS_KSTAT / SPOOF_UNAME / OPEN_REDIRECT / SUS_MAP 等） |
| **Re:Kernel** | v8.5，进程/app 检测（binder + signal hooks） |
| **DroidSpaces** | IPC/PID 命名空间、POSIX_MQUEUE、DEVTMPFS、netfilter/IP_SET、tmpfs ACL/XATTR |
| **Baseband-guard** | BBGuard 电话基带 LSM |
| **BBRv3** | 内置 BBRv3 TCP 拥塞控制代码，默认 `bbr` + `fq` pacing |

> **当前状态（2026-09-25）**：模块全开版本已在 Edge S30 上刷机并**成功开机**。
> 旧 `-modules-nosec` 分支因 BBRv3 改动导致卡开机，已废弃，切勿复用。

---

## 🧠 仓库拓扑（两个仓库，缺一不可）

| 仓库 | 角色 | 分支 |
|------|------|------|
| **paulcbfly/xpeng_kernel_susfs**（本仓库） | 编译脚本 + GitHub Actions workflow | `5.4.302-s3rxc32.33-8-25-ReSukiSU` |
| **paulcbfly/android_kernel_motorola_xpeng** | 内核源码 + 全部适配 commit | `5.4.302-s3rxc32.33-8-25-susfs-modules` |

- 编译仓库**不包含内核源码**，Actions 运行时自动 `git clone` 内核仓库指定分支。
- 内核分支 `5.4.302-s3rxc32.33-8-25-susfs-modules`：
  - 基座 = 上游 `5.4.302-s3rxc32.33-8-25`
  - + SUSFS 适配 commit `b3ecce7eb`
  - + 四模块移植 commit `8972cd10c`（Re:Kernel / DroidSpaces / BBGuard / BBRv3）
  - + fq 默认 qdisc commit `b565fa013`
- 子模块：`KernelSU` → ReSukiSU @ `59c99fdf`（固定，SUSFS v2.2.0 兼容）

---

## 🎛️ GitHub Actions 模块开关

workflow_dispatch 提供 4 个可选模块开关（默认全部勾选）：

- `enable_rekernel` — Re:Kernel v8.5
- `enable_droidspaces` — DroidSpaces 命名空间/netfilter/tmpfs 配置
- `enable_bbguard` — Baseband-guard LSM
- `enable_bbrv3` — BBRv3 TCP 拥塞控制

> ⚠️ **关键修复**：旧工作流曾写 `${{ inputs.x || 'true' }}`，导致取消勾选也强制开启。现已改为 `${{ inputs.enable_x }}`，取消勾选真正生效。

## 📦 产物命名

AnyKernel3 zip 改名为 `AK3-xpeng-EdgeS30-<模块后缀>-<build>.zip`：

| 勾选组合 | 产物名示例 |
|---|---|
| 全开 | `AK3-xpeng-EdgeS30-ReKernel-DroidSpaces-BBGuard-BBRv3-r123.zip` |
| 只开 SUSFS | `AK3-xpeng-EdgeS30-r123.zip` |

Release 页 `RELEASE_NOTES.md` 会列出每个功能的 ✅/❌ 勾选状态。

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
export SUSFS_VERSION=2.2     # 2.2 = 稳定, 2.3 = 最新 SUSFS（需对应内核分支）
export RESUKISU_VERSION=pinned # pinned | latest | custom
# export RESUKISU_CUSTOM_REF=<commit/branch/tag>  # 仅当 RESUKISU_VERSION=custom 时使用
export KERNEL_URL=https://github.com/paulcbfly/android_kernel_motorola_xpeng.git
export KERNEL_BRANCH=5.4.302-s3rxc32.33-8-25-susfs-modules
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
- [`docs/ARCHIVE-2026-09-25-modules-local.md`](docs/ARCHIVE-2026-09-25-modules-local.md) — 本次可用版本归档

---

*README 中文版更新于 2026-09-25。本仓库为 100% AI 生成项目。*
