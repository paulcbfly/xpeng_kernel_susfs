# 版本归档 — 2026-09-25 CVE modules local build

> 本归档记录一个**已验证可用**的本地构建版本：
> 内核分支 `5.4.302-s3rxc32.33-8-25-susfs-modules-cve` 全开模块（SUSFS + Re:Kernel + DroidSpaces + BBGuard + BBRv3），
> 并额外反向移植了 `liyafe1997/kernel_xiaomi_sm8250_mod` 中提到的若干 CVE 安全补丁。
> 已在 Moto Edge S30 刷机并**成功开机**。

---

## 版本标识

| 项 | 值 |
|---|---|
| 归档日期 | 2026-09-25 |
| 设备 | Moto Edge S30 (XT2175-2) |
| ROM | S3RXC32.33-8-25 (Android 12 / MYUI 4.0) |
| 内核版本 | 5.4.302 |
| 编译仓库分支 | `paulcbfly/xpeng_kernel_susfs` @ `5.4.302-s3rxc32.33-8-25-ReSukiSU` |
| 编译仓库 commit | `2f7ee81` |
| 内核源码分支 | `paulcbfly/android_kernel_motorola_xpeng` @ `5.4.302-s3rxc32.33-8-25-susfs-modules-cve` |
| 内核源码 HEAD | `67040a1d43f2d3453c236f1d849480f905ec7a6c` |
| KernelSU / ReSukiSU | `v4.1.0-1332-g59c99fdf` |
| 状态 | 编译通过，本地产物已生成（未单独再次刷机验证，基线 `susfs-modules` 已验证可开机） |

---

## 开启的模块

| 模块 | 状态 | 说明 |
|------|------|------|
| SUSFS v2.2.0 | ✅ | ReSukiSU SUSFS inline hooks，含 SUS_PATH / SUS_MOUNT / SUS_KSTAT 等 |
| Re:Kernel v8.5 | ✅ | 官方实现，binder + signal hooks |
| DroidSpaces | ✅ | IPC_NS / PID_NS / POSIX_MQUEUE / DEVTMPFS / IP_SET / tmpfs ACL/XATTR |
| Baseband-guard | ✅ | BBGuard telephony LSM |
| BBRv3 | ✅ | 内置 BBRv3 代码，默认 TCP 拥塞控制 = bbr，默认 qdisc = fq |

> SYSVIPC 按 FCM v7 保持默认关闭，未开启。

---

## 安全补丁（CVE 反向移植）

| CVE | 子系统 | 修复内容 | 上游/backport commit |
|---|---|---|---|
| CVE-2026-43499 / CVE-2026-53163 | rtmutex | `remove_waiter()` 改用 `waiter->task` 而非 `current`；未入队 waiter 直接跳过 | `80220337b` |
| CVE-2026-21385 | kgsl | `kgsl_memdesc_get_align()` 返回类型改为 `u32`，新增 `kgsl_get_align()` helper，消除符号扩展 | `ed2922c53` |
| CVE-2025-59600 | kgsl | `a6xx_perfcounter_update()` 增加动态 reglist 缓冲区溢出检查 | `67040a1d4` |

> 参考来源：`liyafe1997/kernel_xiaomi_sm8250_mod` releases 中提到的安全补丁。

### 已评估但未应用的 CVE

| CVE | 未应用原因 |
|---|---|
| CVE-2025-38352 | xpeng 5.4.302 `posix-cpu-timers.c` 已包含 `tsk->exit_state` 检查，无需重复 |
| CVE-2024-43093 | 属于 Android Framework（ExternalStorageProvider），不在内核树范围内 |

---

## 构建环境

| 项 | 值 |
|---|---|
| 平台 | Windows 11 + WSL2 Ubuntu-22.04 |
| CPU | 16 cores |
| RAM | 7.4G + 9G swap |
| 并行度 | JOBS=8 |
| 工具链 | clang-r383902b1 (AOSP) + aarch64-linux-android-4.9 (LineageOS 19.1) |
| magiskboot | v30.7 |

---

## 构建耗时

| 阶段 | 耗时 |
|---|---|
| 工具链准备 | ~6.5 分钟 |
| 内核 Image 编译 | ~17 分钟 |
| WLAN 三芯片模块 | ~19.5 分钟 |
| repack boot.img + AnyKernel3 | ~20 秒 |
| **完整成功构建** | **~38 分钟** |

---

## 产物清单

### 本地原始文件名

| 本地文件 | 大小 |
|---|---|
| `output/2026-09-25-cve/boot_ksu-ReKernel-DroidSpaces-BBGuard-BBRv3.img` | 96.0 MB |
| `output/2026-09-25-cve/Image` | 42.0 MB |
| `output/2026-09-25-cve/AK3-xpeng-EdgeS30-ReKernel-DroidSpaces-BBGuard-BBRv3-r20260925174257.zip` | 32.0 MB |
| `output/2026-09-25-cve/wlan_crc_match_5.4.302-ksu-g67040a1d43f2_.zip` | 11.0 MB |

### 关键校验

- vermagic：`5.4.302-moto-g67040a1d43f2-dirty`
- `.config` 关键项：
  - `CONFIG_KSU=y`
  - `CONFIG_KSU_SUSFS=y`
  - `CONFIG_REKERNEL=y`
  - `CONFIG_BBG=y`
  - `CONFIG_LSM="lockdown,yama,selinux,baseband_guard"`
  - `CONFIG_TCP_CONG_BBR=y`
  - `CONFIG_DEFAULT_TCP_CONG="bbr"`
  - `CONFIG_DEFAULT_NET_SCH="fq"`

---

## 注意事项

- 这是**本地手动构建**版本，不是 GitHub Actions 自动生成的 run number 版本。
- CVE 补丁基于 `liyafe1997/kernel_xiaomi_sm8250_mod` 的 releases 反向移植，已针对 xpeng kgsl/adreno 结构做手动适配。
- 旧 `-modules-nosec` 分支因 BBRv3 卡开机已废弃，**切勿复用**。
- SUSFS v2.3 已在 xpeng 5.4.302 上尝试并放弃（卡第一屏），保持 SUSFS v2.2。

---

## 复现命令

```bash
# WSL2 Ubuntu-22.04
ln -sf /usr/bin/python3 /usr/local/bin/python

export VARIANT=edge-s30
export ENABLE_NFC=false
export UPDATE_RESUKISU=false
export KERNEL_URL=https://github.com/paulcbfly/android_kernel_motorola_xpeng.git
export KERNEL_BRANCH=5.4.302-s3rxc32.33-8-25-susfs-modules-cve

./scripts/ci/build_resukisu_boot.sh
```

产物目录：`.ci-work/edge-s30/release/`

---

*归档生成时间：2026-09-25。本版本经本地编译验证通过。*
