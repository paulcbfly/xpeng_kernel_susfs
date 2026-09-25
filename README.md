# xpeng_kernel_susfs

> **🌐 Languages / 语言**: [**English**](README.md) | [简体中文](README_zh.md)

> **⚠️ IMPORTANT: This repository and its kernel-side SUSFS / module integrations are 100% AI-GENERATED.**
> Build scripts are forked from [LuoJuly/android_kernel_motorola_xpeng_build](https://github.com/LuoJuly/android_kernel_motorola_xpeng_build);
> SUSFS and optional module adaptations were produced by an AI agent following
> [LuoJuly's sm7325 `lineage-23.2-SUSFS` branch](https://github.com/LuoJuly/android_kernel_motorola_sm7325/tree/lineage-23.2-SUSFS),
> then verified by actual WSL compile + flash + boot on Edge S30.
> **Use at your own risk.**

> ⚠️ **AI handover note**: Before taking over, read [`docs/AI_HANDOVER.md`](docs/AI_HANDOVER.md) — it records all pitfalls, fixes, GitHub Actions flow, and verification methods.

---

## Project

Build scripts for Motorola **xpeng** (Edge S30 XT2175-2 / G200 5G XT2175-1) **5.4.302 kernel**,
with **ReSukiSU + SUSFS v2.2.0**, plus optional modules:

| Module | Description |
|--------|-------------|
| **SUSFS** | Secure User File System (SUS_PATH / SUS_MOUNT / SUS_KSTAT / SPOOF_UNAME / OPEN_REDIRECT / SUS_MAP) |
| **Re:Kernel** | v8.5 process/app detection via binder + signal hooks |
| **DroidSpaces** | IPC/PID namespaces, POSIX_MQUEUE, DEVTMPFS, netfilter/IP_SET, tmpfs ACL/XATTR |
| **Baseband-guard** | BBGuard telephony LSM |
| **BBRv3** | Built-in BBRv3 TCP congestion control; default `bbr` + `fq` pacing |

> **Current status (2026-09-25)**: The all-modules-enabled build has been flashed and boots successfully on Edge S30.
> The old `-modules-nosec` branch caused boot failure due to its BBRv3 changes and is **abandoned**.

---

## Repository topology

| Repository | Role | Branch |
|------------|------|--------|
| `paulcbfly/xpeng_kernel_susfs` (this repo) | Build scripts + GitHub Actions workflow | `5.4.302-s3rxc32.33-8-25-ReSukiSU` |
| `paulcbfly/android_kernel_motorola_xpeng` | Kernel source + all adaptation commits | `5.4.302-s3rxc32.33-8-25-susfs-modules` |

- This repo does **not** contain kernel sources; the workflow clones the kernel repo at build time.
- Kernel branch `5.4.302-s3rxc32.33-8-25-susfs-modules`:
  - Base = upstream `5.4.302-s3rxc32.33-8-25`
  - + SUSFS commit `b3ecce7eb`
  - + 4-module port commit `8972cd10c` (Re:Kernel / DroidSpaces / BBGuard / BBRv3)
  - + fq default qdisc commit `b565fa013`
- Submodule: `KernelSU` → ReSukiSU @ `59c99fdf` (pinned for SUSFS v2.2.0 compatibility)

---

## GitHub Actions module toggles

workflow_dispatch provides 4 optional module toggles (default ON):

- `enable_rekernel` — Re:Kernel v8.5
- `enable_droidspaces` — DroidSpaces namespace/netfilter/tmpfs configs
- `enable_bbguard` — Baseband-guard LSM
- `enable_bbrv3` — BBRv3 TCP congestion control

> ⚠️ **Key fix**: The old workflow used `${{ inputs.x || 'true' }}`, which silently forced every module ON even when unchecked. It now uses `${{ inputs.enable_x }}`, so unchecking actually disables the module.

## Artifact naming

AnyKernel3 zip is now named `AK3-xpeng-EdgeS30-<module-suffix>-<build>.zip`:

| Enabled modules | Example artifact name |
|-----------------|-----------------------|
| All 4 | `AK3-xpeng-EdgeS30-ReKernel-DroidSpaces-BBGuard-BBRv3-r123.zip` |
| SUSFS only | `AK3-xpeng-EdgeS30-r123.zip` |

The Release page `RELEASE_NOTES.md` lists each feature as ✅ enabled or ❌ disabled.

---

## HOW TO USE

### fastboot

```bash
fastboot reboot fastboot
fastboot flash boot boot_ksu.img
# If needed:
fastboot -w
```

### AnyKernel3 (recommended)

Flash `AK3-*.zip` in recovery / Kernel Flasher. It installs the kernel and pushes WiFi `.ko`
to `/vendor/lib/modules/` (`do.modules=1`). **Do not install the KernelSU WiFi module after flashing AnyKernel3.**

### Standalone WiFi zip

Only needed if you flashed `boot_ksu.img` via fastboot (that path does not replace vendor kos).
Install via ReSukiSU Manager after first boot, then reboot.

---

## Manual CI trigger

### Web

Actions → `xpeng 5.4.302 ReSukiSU Boot/Kernel...` → **Run workflow** → check/uncheck modules → Run.

### CLI

```bash
gh workflow run build-resukisu-edge-s30.yml --ref 5.4.302-s3rxc32.33-8-25-ReSukiSU
gh workflow run build-resukisu-g200.yml --ref 5.4.302-s3rxc32.33-8-25-ReSukiSU

gh run list --workflow build-resukisu-edge-s30.yml --limit 3
```

Monthly schedule: UTC 00:00 1st (Edge S30), 02:00 1st (G200), all modules ON by default.

---

## Local build (verified on Linux container/VM)

```bash
export VARIANT=edge-s30      # or g200 (ENABLE_NFC=true)
export ENABLE_NFC=false
export SUSFS_VERSION=2.2     # 2.2 = stable, 2.3 = latest SUSFS (requires matching kernel branch)
export RESUKISU_VERSION=pinned # pinned | latest | custom
# export RESUKISU_CUSTOM_REF=<commit/branch/tag>  # only when RESUKISU_VERSION=custom
export KERNEL_URL=https://github.com/paulcbfly/android_kernel_motorola_xpeng.git
export KERNEL_BRANCH=5.4.302-s3rxc32.33-8-25-susfs-modules
./scripts/ci/build_resukisu_boot.sh
```

Artifacts: `.ci-work/<variant>/release/`

- `boot_ksu.img` / `Image`
- `wlan_crc_match_*.zip`
- `AK3-*.zip`

> A full local build downloads clang-r383902b1 (~1.4GB) + GCC 4.9 (~91MB). Ensure >20GB free disk.
> Successful full build takes ~**43 minutes** (16 cores / 7.4G RAM + 9G swap / JOBS=8).

---

## Related docs

- [`docs/AI_HANDOVER.md`](docs/AI_HANDOVER.md) — AI handover notes (English): all build issues, fixes, verification, upgrade paths
- [`docs/AI_HANDOVER_zh.md`](docs/AI_HANDOVER_zh.md) — 中文版
- [`docs/ARCHIVE-2026-09-25-modules-local.md`](docs/ARCHIVE-2026-09-25-modules-local.md) — Archive of this verified build

---

*README updated 2026-09-25. This is a 100% AI-generated project.*
