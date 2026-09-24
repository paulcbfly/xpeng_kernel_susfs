# xpeng_kernel_susfs（摩托罗拉 xpeng 内核编译）

> **🌐 语言切换**: [English](README.md) | [**简体中文**](README_zh.md)

> **⚠️ 重要声明：本仓库及内核侧 SUSFS 适配为 100% AI 生成（100% AI-GENERATED）。**
> 编译脚本 fork 自 [LuoJuly/android_kernel_motorola_xpeng_build](https://github.com/LuoJuly/android_kernel_motorola_xpeng_build)；
> SUSFS 及模块适配由 AI 依据 [LuoJuly 的参考提交](https://github.com/LuoJuly/android_kernel_motorola_sm7325/commit/2fa1be6d5a63d3958ab2babd56b61f561f74095b)
> 与 [lineage-23.2-SUSFS 分支](https://github.com/LuoJuly/android_kernel_motorola_sm7325/tree/lineage-23.2-SUSFS) 完成，并经自动化工具全流程调试验证。
> **刷机有风险，后果自负。**

> ⚠️ **AI 接管提示**：接手前请先阅读 [`docs/AI_HANDOVER_zh.md`](docs/AI_HANDOVER_zh.md) —— 记录了全部编译问题及解决方案、GitHub Actions 流程、验证方法。

---

## 📱 项目简介

摩托罗拉 **xpeng**（Edge S30 XT2175-2 / G200 5G XT2175-1）**5.4.302 内核**编译脚本仓库，
内置 **ReSukiSU（KernelSU 分支）+ SUSFS v2.2.0** root 隐藏方案，并新增可选模块：

| 模块 | 说明 |
|------|------|
| **Re:Kernel** | 进程/应用检测模块（binder + signal hooks，netlink 上报） |
| **Baseband-guard（BBGuard）** | 基带防护 LSM（子模块 [vc-teahouse/Baseband-guard](https://github.com/vc-teahouse/Baseband-guard)） |
| **BBRv3** | TCP 拥塞控制升级（默认启用 bbr，可选 cubic 回退） |
| **DroidSpaces** | 沙箱/容器运行支持（IPC/PID 命名空间、DEVTMPFS、netfilter NAT/IP_SET、TMPFS xattr/acl） |
| **SUSFS** | Secure User File System（SUS_PATH / SUS_MOUNT / SUS_KSTAT / SPOOF_UNAME / OPEN_REDIRECT / SUS_MAP 等全特性） |
| **谷歌安全补丁** | 从 AOSP 上游移植的 CVE 修复（af_packet UAF、skbuff 共享 frag、ipv6 信息泄露、tipc 双重释放、nfc UAF） |

---

## 🧠 仓库拓扑（两个仓库）

| 仓库 | 角色 | 分支 |
|------|------|------|
| **paulcbfly/xpeng_kernel_susfs**（本仓库） | 编译脚本 + GitHub Actions workflow | `5.4.302-s3rxc32.33-8-25-ReSukiSU` |
| **paulcbfly/android_kernel_motorola_xpeng** | 内核源码（fork 自 LuoJuly）+ 全部适配 commit | `5.4.302-s3rxc32.33-8-25-modules` |

- 编译仓库**不包含内核源码**，Actions 运行时自动 `git clone` 内核仓库指定分支。
- 内核分支 `5.4.302-s3rxc32.33-8-25-modules` = 上游 8-25 + SUSFS 适配（b3ecce7eb）+ 模块扩展（8f74e34f6）。
- 子模块：`KernelSU`→ReSukiSU @ `59c99fdf`（固定，SUSFS v2.2.0 兼容）、`Baseband-guard`→vc-teahouse @ `cef0daa`。

---

## 🎛️ 编译时模块选项切换（重点）

所有模块**默认全开**。触发编译时可在 Action 页面**取消勾选**来关闭，也可以本地用环境变量控制。

### GitHub Actions 图形界面切换

1. 打开仓库 → **Actions** 标签页
2. 点击左侧 `build-resukisu-edge-s30.yml`（Edge S30）或 `build-resukisu-g200.yml`（G200）
3. 点击 **Run workflow** 按钮
4. 展开下拉框，按需勾选/取消以下选项：

| 选项（输入框） | 默认 | 说明 |
|----------------|------|------|
| `enable_susfs` | ✅ 开 | SUSFS v2.2.0 隐藏框架；**关闭后自动回退到 `KSU_MANUAL_HOOK` 模式** |
| `enable_rekernel` | ✅ 开 | Re:Kernel 进程/应用检测模块 |
| `enable_bbguard` | ✅ 开 | Baseband-guard 基带防护 LSM |
| `enable_bbrv3` | ✅ 开 | BBRv3 拥塞控制；关闭回退 `cubic` |
| `enable_droidspaces` | ✅ 开 | DroidSpaces 沙箱配置（IPC/PID 命名空间等） |
| `update_resukisu` | ❌ 关 | ⚠️ 更新 ReSukiSU 到最新 main（**需要 SUSFS v2.3+ 内核补丁，否则编译失败**，不建议开启） |

### 本地编译环境变量

```bash
export ENABLE_SUSFS=true        # false → 关闭 SUSFS，回退 KSU_MANUAL_HOOK
export ENABLE_REKERNEL=true     # false → 关闭 Re:Kernel
export ENABLE_BBGUARD=true      # false → 关闭 Baseband-guard
export ENABLE_BBRV3=true        # false → 关闭 BBRv3，回退 cubic
export ENABLE_DROIDSPACES=true  # false → 关闭 DroidSpaces 配置
export UPDATE_RESUKISU=false    # true → ReSukiSU 更新到 main（危险，见上）
```

> 开关实现方式：`build_resukisu_boot.sh` 在 defconfig 生成后用 `scripts/config --enable/--disable/--set-str` 调整 `.config`，再执行 `olddefconfig`。

---

## 🛠️ 使用方法（刷机）

### fastboot 方式

```
fastboot reboot fastboot
fastboot flash boot boot_ksu.img
# 若需要：
fastboot -w
```

### AnyKernel3 方式（推荐）

在 recovery / Kernel Flasher 中刷入 `AnyKernel3-*.zip`。
它会安装内核并把 WiFi `.ko` 推送到 `/vendor/lib/modules/`（`do.modules=1`）。
**刷完 AnyKernel3 后不要再安装 KernelSU WiFi 模块。**

### 独立 WiFi 包

仅当用 fastboot 刷了 `boot_ksu.img` 时需要（该方式不替换 vendor ko）。
首次开机后用 ReSukiSU Manager 安装 WiFi 模块再重启。

### 产物

- `.ci-work/<variant>/release/` 下：`boot_ksu.img`、`Image`、`wlan_crc_match_*.zip`、`AnyKernel3-*.zip`
- GitHub Release 页面也会自动发布（boot_ksu.img / Image / AnyKernel3 / wlan zip）

---

## 🔄 手动触发编译

```bash
# 需要 gh CLI + 登录（环境已配置 GH_TOKEN）
gh workflow run build-resukisu-edge-s30.yml --ref 5.4.302-s3rxc32.33-8-25-ReSukiSU
# G200:
gh workflow run build-resukisu-g200.yml --ref 5.4.302-s3rxc32.33-8-25-ReSukiSU

# 查看状态
gh run list --workflow build-resukisu-edge-s30.yml --limit 3
```

每月 1 日 UTC 00:00（Edge S30）/ 02:00（G200）自动编译（schedule）。

---

## 📦 已合入的谷歌安全补丁（内核）

| 文件 | 修复内容 |
|------|----------|
| `net/packet/af_packet.c` | fanout UAF（NETDEV_UP 竞态，CVE 类） |
| `net/core/skbuff.c` | shared-frag 标记保留/传递 ×2、pskb_carve zerocopy 引用计数 |
| `net/ipv6/icmp.c` | `ip6_err_gen_icmpv6_unreach()` 未清 `skb2->cb[]`（信息泄露） |
| `net/ipv6/ip6_tunnel.c` | `ip4ip6_err()` 未清 `cb[]`（信息泄露） |
| `net/tipc/msg.c` | `tipc_buf_append()` 双重释放 |
| `net/nfc/llcp_core.c` | LLCP_CLOSED 检查缺失 return（UAF） |

---

## 📚 相关文档

- [`docs/AI_HANDOVER_zh.md`](docs/AI_HANDOVER_zh.md) — **AI 交接文档（中文）**：全部编译问题、解决方案、验证方法、升级路径
- [`docs/AI_HANDOVER.md`](docs/AI_HANDOVER.md) — AI 交接文档（英文版）
- [内核 fork `5.4.302-s3rxc32.33-8-25-modules` 分支](https://github.com/paulcbfly/android_kernel_motorola_xpeng/tree/5.4.302-s3rxc32.33-8-25-modules)

---

*README 中文版更新于 2026-09-24。本仓库为 100% AI 生成项目。*