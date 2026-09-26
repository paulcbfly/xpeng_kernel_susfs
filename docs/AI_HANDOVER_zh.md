# AI 交接文档（中文版）— xpeng_kernel_susfs

> 本文档由 AI 编写，用于让**下一个 AI（或人类维护者）无需重新摸索**即可接管本仓库的
> SUSFS + ReSukiSU + 可选模块内核编译任务。记录了内核移植与编译相关的踩坑、根因、修复方法、
> GitHub Actions 编译流程和版本归档。
> 
> **本文档对应可用版本：2026-09-25 CVE 模块全开本地构建**，已在 Edge S30 刷机并成功开机。

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
| `paulcbfly/android_kernel_motorola_xpeng` | 内核源码 + 适配 commit + 从 sm8250 反向移植的 CVE 补丁 | `5.4.302-s3rxc32.33-8-25-susfs-modules-cve` |
| `paulcbfly/android_kernel_motorola_xpeng` | 内核源码 + CVE 补丁 + **从 AstideLabs sm8250 反向移植的 SUSFS v2.3**（全量编译通过，待刷机验证） | `5.4.302-s3rxc32.33-8-25-susfs-modules-v2.3-astide` |

- 编译仓库**不含内核源码**，workflow 运行时 `git clone` 内核仓库指定分支。
- 内核分支 `5.4.302-s3rxc32.33-8-25-susfs-modules`：
  - 基座 = 上游 `5.4.302-s3rxc32.33-8-25`
  - + SUSFS 适配 commit `b3ecce7eb`（SUSFS v2.2.0 + ReSukiSU 子模块 pin 59c99fdf）
  - + 四模块移植 commit `8972cd10c`（Re:Kernel / DroidSpaces / BBGuard / BBRv3）
  - + fq 默认 qdisc commit `b565fa013`
- 内核分支 `5.4.302-s3rxc32.33-8-25-susfs-modules-cve`：
  - 与 `susfs-modules` 相同
  - + 从 `liyafe1997/kernel_xiaomi_sm8250_mod` 反向移植的安全补丁：
    - `80220337b` — rtmutex：CVE-2026-43499 / CVE-2026-53163
    - `ed2922c53` — kgsl：对齐值符号扩展问题（CVE-2026-21385）
    - `67040a1d4` — kgsl：perfcounter 动态列表缓冲区溢出（CVE-2025-59600）
- 内核分支 `5.4.302-s3rxc32.33-8-25-susfs-modules-v2.3-astide`：
  - 基于 `susfs-modules-cve`
  - + SUSFS v2.3 核心文件替换（来自 `AstideLabs/android_kernel_xiaomi_sm8250` commit `0b8a115ddd41`）
  - + hook 点适配（第一轮 `a2c9002c4`）：`proc_namespace.c`、`proc/fd.c`、`proc/task_mmu.c`、`statfs.c`
  - + hook 点适配（第二轮 `4ac98a8fc`）：`fs/stat.c`、`fs/notify/fdinfo.c`、`fs/statfs.c`、`fs/readdir.c`
  - 状态：**全量编译通过（`RC=0`，零 `ERROR:`）**，产物 vermagic `5.4.302-moto-g4ac98a8fc25c-dirty`，
    待刷机验证。产物见 `D:\githubs30\output\2026-09-26-v23\`。
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

### 问题 #4（配置合并）：DroidSpaces 与 SYSVIPC 的 FCM 冲突

**现象**：DroidSpaces 某些配置要求 `CONFIG_SYSVIPC=y`，但 xpeng 基线中它是关的。

**根因**：FCM v7 要求某些 IPC 配置保持默认（关），DroidSpaces 的 KABI 补丁通过把 `sysv` 相关字段移入 KABI 保留槽解决兼容性。

**处置**：
- 打 KABI 补丁（LuoJuly commit `f05b8df8`）
- 保持 `CONFIG_SYSVIPC` 默认关闭
- 启用 `IPC_NS`、`PID_NS`、`POSIX_MQUEUE` 等 DroidSpaces 所需命名空间

---

### 问题 #5（BBGuard LSM）：`CONFIG_LSM` 字符串格式与校验

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

- 主机系统：Ubuntu 22.04（或等效 Linux 容器/虚拟机）
- 16 核 / 7.4G RAM + 9G swap
- 编译仓库路径：`/root/xpeng-build`
- 内核源码路径：`/root/kernel-src`

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
| WLAN 编译报 `python: not found` | 构建环境缺少 `python` 命令 | `ln -sf /usr/bin/python3 /usr/local/bin/python` |
| `CONFIG_LSM` 含 `bpf` 报错 | xpeng 树无 `security/bpf` | 从 LSM 串中去掉 `bpf` |
| `DEFAULT_QDISC="fq"` 找不到 | xpeng 用 `DEFAULT_NET_SCH` | `NET_SCH_DEFAULT=y` + `DEFAULT_FQ=y` |
| `NETFILTER_XT_TARGET_REJECT` 找不到 | xpeng 用 `IP_NF_TARGET_REJECT` | 换成 `IP_NF_TARGET_REJECT=y` |
| `drivers/net/rekernel/Kconfig` 不存在 | 旧 netlink 版残留 | 删 `drivers/net/Kconfig` + `Makefile` 引用 |

---

## 7. 未来升级路径

### 升级 SUSFS v2.3.0 / 最新 ReSukiSU — 第二次尝试进行中

第一次尝试使用 `bcrtvkcs/susfs4ksu@gki-android16-5.4` 的参考文件替换 `fs/susfs.c`、`include/linux/susfs.h`、`include/linux/susfs_def.h`，并对 v2.2 hook 加兼容 stub，编译通过但刷入 Edge S30 后**卡第一屏反复重启**，已废弃并删除。

第二次尝试改用 `AstideLabs/android_kernel_xiaomi_sm8250`（基于 4.19.y）的 commit `0b8a115ddd41` 作为 SUSFS v2.3 核心来源，并把 hook 点迁移到 v2.3 API。AstideLabs 仓库随后用 `616911eb2dc9` 回退了 `susfs_inline_hook` 方式的 KernelSU 集成（`a7d3ad67a9d5`），因此 xpeng port 保持现有 ReSukiSU 集成不变。

#### v2.3 的关键 API 变化（务必理解）

| v2.2 写法 | v2.3 写法 |
|---|---|
| `susfs_sus_kstat_spoof_generic_fillattr(inode, stat)`（2 参） | `susfs_sus_kstat_spoof_generic_fillattr(inode, stat, result_mask)`（3 参） |
| `generic_fillattr()` 内**无条件** spoof | 由 `vfs_getattr_nosec()` 按 `result_mask` 上的 `STATX_SUS_KSTAT` / `STATX_SUS_KSTAT_FUSE` 位驱动 |
| 无 | 新增 `susfs_is_inode_sus_kstat(inode, &is_fuse)` |
| 无 | 新增 `susfs_sus_kstat_spoof_inotify_fdinfo(&ino, &dev)` |
| 无 | 新增 `susfs_sus_kstat_spoof_proc_fd_seq_show(&mnt_id, &ino, dev)` |
| 无 | 新增 `susfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino)` |
| 无 | 新增 `susfs_sus_kstat_spoof_vfs_statfs(inode, buf, &is_fuse)` |

`STATX_SUS_KSTAT` / `STATX_SUS_KSTAT_FUSE` 定义在 `include/linux/susfs_def.h`。

#### 已完成的 commit（分支 `5.4.302-s3rxc32.33-8-25-susfs-modules-v2.3-astide`）

| commit | 内容 |
|---|---|
| `751b68d7e` | 替换 `fs/susfs.c`、`include/linux/susfs.h`、`include/linux/susfs_def.h` 为 v2.3 核心 |
| `a2c9002c4` | 适配 hub：`proc_namespace.c`、`proc/fd.c`、`proc/task_mmu.c`、`statfs.c` |
| `4ac98a8fc` | 补齐 `stat.c`、`statfs.c`、`notify/fdinfo.c`、`readdir.c` |

#### 静态验证结果（已完成）

- 增量编译：`CC fs/readdir.o fs/stat.o fs/statfs.o fs/notify/fdinfo.o` → **RC=0，无 warning**
- 全符号检查：86 个 `susfs_*` 符号，**0 个 MISSING**
- 新引用的 3 个 v2.3 API 调用点签名与 `fs/susfs.c` 定义**逐字一致**

**备注**：`fs/readdir.c` 的 26 个上游 SUS_PATH hunk 在基线里已全部存在（基础分支已给 5 个 readdir 变体加过 hook），本次只调整了 include 位置以对齐上游排版，无行为变化。

**状态**：核心 + 全部 hook 更新已推送，**全量编译已通过**（`RC=0`，零 `ERROR:`），产物在 `D:\githubs30\output\2026-09-26-v23\`；**待刷机验证**。

#### 全量构建验证结果（2026-09-26 10:29，`RC=0`）

| 校验项 | 结果 |
|---|---|
| 构建 `ERROR:` 计数 | **0** |
| Image vermagic | `5.4.302-moto-g4ac98a8fc25c-dirty` |
| 三个 WLAN ko vermagic | 与 Image **逐字一致** ✅ |
| `boot_ksu.img` 内 kernel vs `Image` | sha256 **完全相同**（`daa3c852…`） ✅ |
| v2.3 新增符号是否编入 Image | 6/6 **PRESENT** ✅ |

v2.3 新增符号实测存在：`susfs_is_inode_sus_kstat`、`susfs_sus_kstat_spoof_generic_fillattr`、`…_spoof_inotify_fdinfo`、`…_spoof_proc_fd_seq_show`、`…_spoof_show_map_vma`、`…_spoof_vfs_statfs`。

校验脚本：`tools/verify_v23_release.sh`、`tools/verify_v23_wlan.sh`、`tools/verify_v23_symbols.sh`、`tools/export_v23.sh`。

### 新增模块

- 参考 LuoJuly sm7325 lineage 分支的 commit
- 注意 xpeng 与 sm7325 的 defconfig 路径、Kconfig 符号、LSM 字符串差异
- 每个新模块必须单独开关，默认建议 OFF，验证稳定后再默认 ON

---

## 8. 版本归档

本次验证通过的版本归档见：

- [`docs/ARCHIVE-2026-09-25-modules-local.md`](ARCHIVE-2026-09-25-modules-local.md) — 基础模块全开版本
- [`docs/ARCHIVE-2026-09-25-cve.md`](ARCHIVE-2026-09-25-cve.md) — 同上，额外包含 CVE 反向移植（rtmutex + kgsl）

---

*文档生成时间：2026-09-25。作者：AI 助手（100% AI-generated project）。*
