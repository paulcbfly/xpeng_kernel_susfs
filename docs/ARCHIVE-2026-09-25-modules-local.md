# 版本归档 — 2026-09-25 modules local build

> 本归档记录一个**已验证可用**的本地构建版本：
> 内核分支 `5.4.302-s3rxc32.33-8-25-susfs-modules` 全开模块（SUSFS + Re:Kernel + DroidSpaces + BBGuard + BBRv3），
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
| 编译仓库 commit | `8ac6c41ce0309f2ec4a1f9842e457aa5600d9b3d` |
| 内核源码分支 | `paulcbfly/android_kernel_motorola_xpeng` @ `5.4.302-s3rxc32.33-8-25-susfs-modules` |
| 内核源码 HEAD | `b565fa0139ea26f4f5ae52e3733f4ef784d6fcdc` |
| 内核源码父提交 | `8972cd10cc7107f0f4b6f0c3e0e0e0e0e0e0e0e0` |
| KernelSU / ReSukiSU | `v4.1.0-1332-g59c99fdf` |
| 状态 | ✅ 已刷机开机成功 |

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
| **完整成功构建** | **~43.5 分钟** |

---

## 产物清单

### 本地原始文件名

| 本地文件 | md5 | 大小 |
|---|---|---|
| `output/boot_ksu-modules.img` | `9489f395653560724e260a9fde770ca4` | 96.0 MB |
| `output/Image` | `5c6de62e02e1eb10d79c0953e9fc83a0` | 41.0 MB |
| `output/AnyKernel3-xpeng-EdgeS30-modules.zip` | `9a59758535888de6e3e85583757ebfbb` | 31.3 MB |
| `output/wlan_crc_match-modules-ksu.zip` | `c12546c28670588ba20da1e82f6bfe94` | 10.6 MB |

### GitHub Release 中的文件名

Release tag: `MMI-5.4.302-S3RXC32.33-8-25-ReSukiSU-EdgeS30-modules-local`

| Release asset | 大小 |
|---|---|
| `boot_ksu.img` | 96.0 MB |
| `Image` | 41.0 MB |
| `AK3-xpeng-EdgeS30-ReKernel-DroidSpaces-BBGuard-BBRv3-local.zip` | 31.3 MB |
| `wlan_crc_match_5.4.302-ksu-modules-local.zip` | 10.6 MB |

Release 页：https://github.com/paulcbfly/xpeng_kernel_susfs/releases/tag/MMI-5.4.302-S3RXC32.33-8-25-ReSukiSU-EdgeS30-modules-local

---

## 关键验证

1. **编译成功**：`build_resukisu_boot.sh` RC=0
2. **内核校验**：magiskboot 解包 `boot_ksu.img` 得到的 kernel 与编译 `Image` 字节完全一致（43186688 字节）
3. **vermagic**：`5.4.302-moto-gb565fa0139ea-dirty`
4. **.config 关键项命中**：
   - `CONFIG_KSU=y`
   - `CONFIG_KSU_SUSFS=y`
   - `CONFIG_REKERNEL=y`
   - `CONFIG_BBG=y`
   - `CONFIG_LSM="lockdown,yama,selinux,baseband_guard"`
   - `CONFIG_TCP_CONG_BBR=y`
   - `CONFIG_DEFAULT_TCP_CONG="bbr"`
   - `CONFIG_DEFAULT_NET_SCH="fq"`
5. **实际刷机**：已在 Edge S30 通过 fastboot 刷入 `boot_ksu.img`，成功开机进入系统。

---

## 注意事项

- 这是**本地手动构建**版本，不是 GitHub Actions 自动生成的 run number 版本。
- 文件名中的 `-local` 用于区分 Actions 自动构建产物。
- 若后续 GitHub Actions 成功跑出新模块构建，推荐优先使用 Actions 产物（run number 版本）。
- 旧 `-modules-nosec` 分支因 BBRv3 卡开机已废弃，**切勿复用**。

---

## 复现命令

```bash
# WSL2 Ubuntu-22.04
ln -sf /usr/bin/python3 /usr/local/bin/python

export VARIANT=edge-s30
export ENABLE_NFC=false
export UPDATE_RESUKISU=false
export KERNEL_URL=https://github.com/paulcbfly/android_kernel_motorola_xpeng.git
export KERNEL_BRANCH=5.4.302-s3rxc32.33-8-25-susfs-modules

./scripts/ci/build_resukisu_boot.sh
```

产物目录：`.ci-work/edge-s30/release/`

---

*归档生成时间：2026-09-25。本版本经实际刷机验证可用。*
