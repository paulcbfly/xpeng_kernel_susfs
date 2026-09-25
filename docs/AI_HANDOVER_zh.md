# AI 交接文档（中文版）— xpeng_kernel_susfs

> 本文档由 AI 编写，用于让**下一个 AI（或人类维护者）无需重新摸索**即可接管本仓库的
> SUSFS + ReSukiSU + 可选模块内核编译任务。记录了本次适配的全部踩坑、根因、修复方法、
> GitHub Actions 编译流程和版本归档。
> 
> **本文档对应可用版本：2026-09-25 模块全开本地构建**，已在 Edge S30 刷机并成功开机。

---

## 0. 项目一句话

Motorola xpeng（Edge S30 / G200，代号 xpeng，**5.4 内核**）的编译脚本仓库，
内核集成 **SUSFS v2.2.0** + **ReSukiSU（固定 commit 59c99fdf）**，
并可选开启 **Re:Kernel + Baseband-guard + BBRv3 + DroidSpaces**，
用 GitHub Actions 自动编译并发布 Release。

---

## 1. 仓库拓扑（两个仓库，缺一不可）

| 仓库 | 角色 | 分支 |
|------|------|------|
| `paulcbfly/xpeng_kernel_susfs` | **编译仓库**：build 脚本 + GitHub Actions workflow | `5.4.302-s3rxc32.33-8-25-ReSukiSU` |
| `paulcbfly/android_kernel_motorola_xpeng` | 内核源码 + 全部适配 commit | `5.4.302-s3rxc32.33-8-25-susfs-modules` |

- 编译仓库**不含内核源码**，workflow 运行时 `git clone` 内核仓库指定分支。
- 内核分支 `5.4.302-s3rxc32.33-8-25-susfs-modules`：
  - 基座 = 上游 `5.4.302-s3rxc32.33-8-25`
  - + SUSFS 适配 commit `b3ecce7eb`（SUSFS v2.2.0 + ReSukiSU 子模块 pin 59c99fdf）
  - + 四模块移植 commit `8972cd10c`（Re:Kernel / DroidSpaces / BBGuard / BBRv3）
  - + fq 默认 qdisc commit `b565fa013`
- 子模块：`KernelSU` → ReSukiSU @ `59c99fdf`（固定，SUSFS v2.2.0 兼容）

### 关键文件修改点（编译仓库）

- `.github/workflows/build-resukisu-edge-s30.yml`（Edge S30）、`build-resukisu-g200.yml`（G200）
  - `KERNEL_URL` → `https://github.com/paulcbfly/android_kernel_motorola_xpeng.git`
  - `KERNEL_BRANCH` → `5.4.302-s3rxc32.33-8-25-susfs-modules`
  - `UPDATE_RESUKISU` → `${{ inputs.update_resukisu || 'false' }}`（默认不更新）
  - 新增 4 个模块输入：`enable_rekernel` / `enable_droidspaces` / `enable_bbguard` / `enable_bbrv3`（默认全 true）
  - **不再保留 `enable_susfs`**：SUSFS 是基线，始终开启
  - **修复 `|| 'true'` Bug**：旧写法 `inputs.x || 'true'` 会让取消勾选失效，现已改为直接传 `inputs.enable_x`
- `scripts/ci/build_resukisu_boot.sh`
  - `KERNEL_URL` / `KERNEL_BRANCH` 默认值同上
  - `build_module_tag()` 根据启用的模块生成产物后缀
  - `build_kernel()`：defconfig 生成后、`olddefconfig` 前，用 `scripts/config` 按 `ENABLE_*` 环境变量调整 `.config`
- `scripts/ci/pack_anykernel3.sh`
  - 产物 zip 改名为 `AK3-xpeng-EdgeS30-<模块后缀>-<build>.zip`
  - Release notes 中列出各模块勾选状态

---

## 2. 编译问题与解决方案（按严重程度）

### 问题 #1（致命，已废弃）：旧 `-modules-nosec` 分支卡开机

**现象**：早期 `-modules-nosec` 分支编译成功，但刷入后无法开机。

**根因**：该分支的 BBRv3 TCP 改动与 xpeng 5.4.302 基线不兼容，导致启动阶段网络初始化失败。

**处置**：
- 删除 `-modules-nosec` 分支，**切勿复用**。
- 重新基于稳定的 `5.4.302-s3rxc32.33-8-25-susfs` 分支，严格参考 **LuoJuly/android_kernel_motorola_sm7325 `lineage-23.2-SUSFS`** 分支的适配 commit。

---

### 问题 #2（关键）：LuoJuly sm7325 适配移植到 xpeng 的差异

sm7325 是 lineage 内核，xpeng 是 MMI 内核，不能直接 `git apply`。

| sm7325 原做法 | xpeng 树实际情况 | 调整 |
|---|---|---|
| defconfig 目标 = `lineage_xpeng.config` | MMI 用 `ext_config/moto-lahaina-xpeng.config` 片段 | 改写到 `ext_config/moto-lahaina-xpeng.config` |
| `CONFIG_DEFAULT_QDISC="fq"` | 只有 `CONFIG_DEFAULT_NET_SCH` | 改成 `NET_SCH_DEFAULT=y` + `DEFAULT_FQ=y` |
| `NETFILTER_XT_TARGET_REJECT` | 只有 `IP_NF_TARGET_REJECT` | 换成 `IP_NF_TARGET_REJECT=y` |
| CONFIG_LSM 含 `bpf` | 本树无 `security/bpf` | 去掉 `bpf` |
| `CONFIG_TCP_ECN=y` | 5.4 主线无此符号 | 跳过 |
| `TCP_CONG_BRUTAL` | 两棵树都没有源码 | 跳过 |

**移植方法**：
- 新增/修改文件纯净时可用 `git apply --include=...` 提取特定路径
- `defconfig`、`.gitmodules`、`drivers/Kconfig`、`drivers/Makefile`、`security/Kconfig`、`security/Makefile` 必须手动改
- Re:Kernel 最终版在 `drivers/rekernel/`，不要的旧 netlink 版在 `drivers/net/rekernel/` 必须删除残留引用

---

### 问题 #3（本地构建阻塞）：缺 `python` 命令导致 WLAN 编译失败

**现象**：

```
/bin/sh: 1: python: not found
.../qcacld-3.0/.wlan/Kbuild:36: .../configs/default_defconfig: No such file or directory
```

**根因**：`qcacld-3.0/.wlan/Kbuild` 第 33 行调用 `python -c "import os.path; print(os.path.relpath(...))"`，
Ubuntu 22.04 默认只有 `python3`，没有 `python`。返回空导致 `WLAN_ROOT` 路径错误，找不到 `configs/default_defconfig`。

**修复**：

```bash
ln -sf /usr/bin/python3 /usr/local/bin/python
```

GitHub Actions 的 ubuntu-22.04 runner 自带 `python`，所以 CI 不踩此坑。

---

### 问题 #4（下载阻塞）：`ghproxy.net` 不代理 `api.github.com`，magiskboot 下载 403

**现象**：

```
curl: (22) The requested URL returned error: 403
```

**根因**：脚本用 `ghproxy.net` 代理 `api.github.com` 获取 Magisk release，但该代理返回 403。

**修复**：
- 直接访问 GitHub API 取最新 tag
- 直连下载 Magisk APK
- 从 APK 中提取 `lib/x86_64/libmagiskboot.so` 作为 `magiskboot`

参考脚本：`tools/get_magiskboot.sh`

---

### 问题 #5（WSL 进程管理）：后台 `nohup ... &` 进程在 `wsl.exe` 退出时被杀

**根因**：`wsl.exe` 调用结束时，其启动的登录 shell 及子进程会被终止，`nohup` 也保不住。

**处置**：
- 长任务必须用 **Bash 工具 `run_in_background=true` 包住 `wsl.exe` 调用**
- 不要依赖 `nohup ... &` 跨 `wsl.exe` 会话保活

---

### 问题 #6（代理无效）：Windows 代理无法自动被 WSL git 使用

**现象**：用户挂了 Windows 代理，但 WSL 里 `git clone` 仍然直连，速度慢/断流。

**根因**：
- WSL2 是 NAT 网络，`127.0.0.1` 是 WSL 自己的回环，不是 Windows
- WSL 里没有 `http_proxy`/`https_proxy` 环境变量，git 也没配代理
- Windows 系统代理可能是关闭的
- 代理客户端没开 Allow LAN，WSL 连不到 Windows 网关上的代理端口

**处置**：
- 最快方案：直接用 `ghproxy.net` 镜像（实测 ~2.7 MB/s，稳定）
- 若必须走代理：客户端开 Allow LAN，WSL 里 `export https_proxy=http://<Windows网关IP>:端口`

---

### 问题 #7（配置合并）：DroidSpaces 与 SYSVIPC 的 FCM 冲突

**现象**：DroidSpaces 某些配置要求 `CONFIG_SYSVIPC=y`，但 xpeng 基线中它是关的。

**根因**：FCM v7 要求某些 IPC 配置保持默认（关），DroidSpaces 的 KABI 补丁通过把 `sysv` 相关字段移入 KABI 保留槽解决兼容性。

**处置**：
- 打 KABI 补丁（LuoJuly commit `f05b8df8`）
- 保持 `CONFIG_SYSVIPC` 默认关闭
- 启用 `IPC_NS`、`PID_NS`、`POSIX_MQUEUE` 等 DroidSpaces 所需命名空间

---

### 问题 #8（BBGuard LSM）：`CONFIG_LSM` 字符串格式与校验

**现象**：开启 BBGuard 后内核启动 LSM 注册失败，或 `.config` 中 `CONFIG_LSM` 被错误覆盖。

**根因**：`CONFIG_LSM` 是一个双引号字符串，例如 `"lockdown,yama,baseband_guard"`。直接用 `scripts/config --set-str` 时若包含空格或特殊字符会出错。

**处置**：
- 在 `build_kernel()` 中读取当前 `CONFIG_LSM` 值，把 `baseband_guard` 追加进去
- 保留原有 LSM（如 `lockdown,yama,selinux`）
- 不要覆盖为固定字符串

---

## 3. GitHub Actions 编译流程

### 触发方式

```bash
gh workflow run build-resukisu-edge-s30.yml --ref 5.4.302-s3rxc32.33-8-25-ReSukiSU
gh workflow run build-resukisu-g200.yml --ref 5.4.302-s3rxc32.33-8-25-ReSukiSU
gh run list --workflow build-resukisu-edge-s30.yml --limit 3
gh run view <RUN_ID> --log-failed     # 失败日志
```

- 每月 1 日 UTC 00:00（Edge S30）/ 02:00（G200）自动跑（schedule），默认全开模块
- 网页触发：Actions 页 → Run workflow → 勾选/取消模块选项

### workflow 内部流程（约 40-60 分钟）

1. `actions/checkout` 编译仓库 `5.4.302-s3rxc32.33-8-25-ReSukiSU`
2. 缓存/下载工具链：`clang-r383902b1`（AOSP）+ GCC 4.9（Lineage 19.1）+ magiskboot
3. `build_resukisu_boot.sh`：
   - `fetch_kernel`：clone 内核 fork 的 `5.4.302-s3rxc32.33-8-25-susfs-modules`（--recursive）
   - `update_resukisu`：pin KernelSU 子模块到 59c99fdf（默认）
   - `setup_toolchain`、`build_kernel`（generate_defconfig → **模块开关** → olddefconfig → Image）
   - `build_wlan_modules`（WiFi ko）
   - `repack_boot`（magiskboot 打包 boot_ksu.img）
   - `pack_anykernel3`（Image + WiFi kos，AK3 命名）
4. 上传 artifact + 创建 GitHub Release（body 含模块勾选状态）

### 产物命名

```
AK3-xpeng-EdgeS30-ReKernel-DroidSpaces-BBGuard-BBRv3-r{N}.zip
boot_ksu.img
Image
wlan_crc_match_5.4.302-ksu-g<sha>_.zip
```

---

## 4. 模块开关实现细节

`build_kernel()` 中，在 `make vendor/lahaina-qgki_defconfig` 之后、`olddefconfig` 之前：

```bash
sha="${KERNEL_DIR}/scripts/config"
"$sha" --file "${OUT_DIR}/.config" --enable/--disable/--set-str <CONFIG> ...
```

| 环境变量 | 关闭时操作 |
|---|---|
| `ENABLE_REKERNEL=false` | `--disable REKERNEL` |
| `ENABLE_BBGUARD=false` | `--disable BBG`；从 `CONFIG_LSM` 移除 `baseband_guard` |
| `ENABLE_BBRV3=false` | `--disable TCP_CONG_BBR DEFAULT_BBR`；`--set-str DEFAULT_TCP_CONG cubic` |
| `ENABLE_DROIDSPACES=false` | `--disable POSIX_MQUEUE IPC_NS PID_NS DEVTMPFS NETFILTER_XT_SET IP_SET` 等 |

> SUSFS 是基线，始终开启，没有 `ENABLE_SUSFS` 开关。

---

## 5. 本地复现构建（已验证）

### 环境

- Windows 11 + WSL2 `Ubuntu-22.04`
- 16 核 / 7.4G RAM + 9G swap
- `/root/xpeng-build`（编译仓库）+ `/root/kernel-src`（内核源码）

### 步骤

```bash
# 1. 确保 python 软链存在
ln -sf /usr/bin/python3 /usr/local/bin/python

# 2. 运行编译
export VARIANT=edge-s30
export ENABLE_NFC=false
export UPDATE_RESUKISU=false
export KERNEL_URL=https://github.com/paulcbfly/android_kernel_motorola_xpeng.git
export KERNEL_BRANCH=5.4.302-s3rxc32.33-8-25-susfs-modules
./scripts/ci/build_resukisu_boot.sh
```

### 耗时基线

| 阶段 | 耗时 |
|---|---|
| 工具链首次下载 | ~6.5 分钟 |
| 内核 Image 编译 | ~17 分钟 |
| WLAN 三芯片模块 | ~19.5 分钟 |
| repack + AnyKernel3 | ~20 秒 |
| **完整成功构建** | **~43.5 分钟** |

### 产物

`.ci-work/<variant>/release/`：

- `boot_ksu.img` / `Image`
- `wlan_crc_match_*.zip`
- `AK3-*.zip`

---

## 6. 踩坑速查表（TL;DR）

| 症状 | 原因 | 处置 |
|------|------|------|
| 刷入后卡开机 | 旧 `-modules-nosec` 分支 BBRv3 不兼容 | 用新 `susfs-modules` 分支 |
| WLAN 编译报 `python: not found` | WSL 无 `python` 命令 | `ln -sf /usr/bin/python3 /usr/local/bin/python` |
| `ghproxy.net` 403 | 它不透传 `api.github.com` | GitHub API / Magisk 下载走直连 |
| WSL 后台 clone 被中断 | `wsl.exe` 退出杀子进程 | Bash 工具 `run_in_background=true` 包 `wsl.exe` |
| `CONFIG_LSM` 含 `bpf` 报错 | xpeng 树无 `security/bpf` | 从 LSM 串中去掉 `bpf` |
| `DEFAULT_QDISC="fq"` 找不到 | xpeng 用 `DEFAULT_NET_SCH` | `NET_SCH_DEFAULT=y` + `DEFAULT_FQ=y` |
| `NETFILTER_XT_TARGET_REJECT` 找不到 | xpeng 用 `IP_NF_TARGET_REJECT` | 换成 `IP_NF_TARGET_REJECT=y` |
| `drivers/net/rekernel/Kconfig` 不存在 | 旧 netlink 版残留 | 删 `drivers/net/Kconfig` + `Makefile` 引用 |

---

## 7. 未来升级路径

### 升级 SUSFS v2.3.0 / 最新 ReSukiSU

1. 内核侧：用 `cctv18/susfs4oki`（v2.3.0）替换 `fs/susfs.c`、`include/linux/susfs.h`、`include/linux/susfs_def.h`；
   **注意 AS_FLAGS 从 `inode->i_state` → `inode->i_mapping->flags`**，所有 hook 文件里的 set_bit/test_bit 都要同步改；
   v2.3.0 新增 `fs/super.c` hook，5.4 需手动移植。
2. 放开 `UPDATE_RESUKISU`（改回 schedule 强制或默认 true）。
3. 升级后本地先验证编译通过再推送。

### 新增模块

- 参考 LuoJuly sm7325 lineage 分支的 commit
- 注意 xpeng 与 sm7325 的 defconfig 路径、Kconfig 符号、LSM 字符串差异
- 每个新模块必须单独开关，默认建议 OFF，验证稳定后再默认 ON

---

## 8. 版本归档

本次验证通过的版本归档见：

- [`docs/ARCHIVE-2026-09-25-modules-local.md`](ARCHIVE-2026-09-25-modules-local.md)

---

*文档生成时间：2026-09-25。作者：AI 助手（100% AI-generated project）。*
