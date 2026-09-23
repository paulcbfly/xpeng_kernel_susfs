# xpeng_kernel_susfs

Build scripts for Motorola **xpeng** (Moto G200 5G / Edge S30) kernel + WLAN, plus **ReSukiSU + SUSFS** boot / AnyKernel3 GitHub Actions.

> Fork of [`LuoJuly/android_kernel_motorola_xpeng_build`](https://github.com/LuoJuly/android_kernel_motorola_xpeng_build) with **SUSFS (v2.2.0)** support added to the kernel, adapted from [LuoJuly/android_kernel_motorola_sm7325 commit 2fa1be6](https://github.com/LuoJuly/android_kernel_motorola_sm7325/commit/2fa1be6d5a63d3958ab2babd56b61f561f74095b) for the MMI 5.4.302 tree.

## Active CI branch: `5.4.302-s3rxc32.33-8-25-ReSukiSU`

| Item | Value |
|------|-------|
| Kernel source | [`android_kernel_motorola_xpeng` @ `5.4.302-s3rxc32.33-8-25-susfs`](https://github.com/paulcbfly/android_kernel_motorola_xpeng/tree/5.4.302-s3rxc32.33-8-25-susfs) |
| Kernel version label | **5.4.302** |
| ROM id | `S3RXC32.33-8-25` |
| SUSFS | **v2.2.0** (all features: SUS_PATH / SUS_MOUNT / SUS_KSTAT / SPOOF_UNAME / HIDE_KSU_SUSFS_SYMBOLS / SPOOF_CMDLINE_OR_BOOTCONFIG / OPEN_REDIRECT / SUS_MAP / AVC-log-spoofing) |
| ReSukiSU | latest `main` (submodule, updated each CI run) |
| Legacy scripts branch | `S3RXC32.33-8-29-ReSukiSU` (8-29 kernel **5.4.210**, live WiFi pack) |

Kernel sources are **not** in this repo. They are fetched by git from `paulcbfly/android_kernel_motorola_xpeng` (branch `5.4.302-s3rxc32.33-8-25-susfs`), which carries the SUSFS integration commits on top of upstream `5.4.302-s3rxc32.33-8-25`.

## Layout

| Path | Role |
|------|------|
| `build-kernel.sh` / `build-wlan.sh` / `build-all.sh` | Local MMI-style builds |
| `setup.sh` | Fetch/link kernel, clang, gcc, Lineage host tools, WLAN trees |
| `scripts/ci/build_resukisu_boot.sh` | Clone kernel → ReSukiSU → Image → **WiFi kos** → boot → AnyKernel3 |
| `scripts/ci/build_wlan_modules.sh` | Build vermagic-matched `qca_cld3_*.ko` against current `O=` |
| `scripts/ci/pack_wlan_ksu_module.sh` | Optional Magisk/KernelSU WiFi zip (fastboot-only fallback) |
| `scripts/ci/pack_anykernel3.sh` | Pack AnyKernel3 (**Image + vendor WiFi kos**, `do.modules=1`) |
| `scripts/ci/wlan-ksu-module-template/` | Magisk module scripts (`service.sh` late-insmod) |
| `.github/workflows/` | Monthly Actions for Edge S30 + G200 |

## Pipeline (each variant)

1. Clone/update kernel `5.4.302-s3rxc32.33-8-25` (+ ReSukiSU submodule)
2. Build `Image` (NFC off for Edge S30, on for G200)
3. Build WiFi modules against that Image (`qca_cld3_{wlan,qca6750,qca6390}.ko`)
4. Pack standalone `wlan_crc_match_5.4.302-ksu-g*.zip` (optional; not used by AnyKernel3)
5. Repack `boot_ksu.img`
6. Pack `AnyKernel3-*-5.4.302-*.zip` containing **kernel + vendor WiFi kos** (`do.modules=1`, `do.systemless=0`)
7. Publish Release assets

## ReSukiSU monthly CI

| Workflow | Device | NFC | Schedule (UTC) |
|----------|--------|-----|----------------|
| `build-resukisu-edge-s30.yml` | Moto Edge S30 (XT2175-2) | off | 1st of month 00:00 |
| `build-resukisu-g200.yml` | Moto G200 5G (XT2175-1) | on | 1st of month 02:00 |

### Local build

```bash
export XPENG_BUILD_ROOT=$PWD
export KERNEL_SRC=~/android/mmi-8-25-upstreaming   # optional local tree on 5.4.302 branch

./scripts/ci/run_local_both.sh

# or one variant
VARIANT=edge-s30 ./scripts/ci/build_resukisu_boot.sh
VARIANT=g200 ./scripts/ci/build_resukisu_boot.sh
```

Artifacts: `.ci-work/<variant>/release/`

- `boot_ksu.img` / `Image`
- `wlan_crc_match_5.4.302-ksu-g*.zip` (optional fastboot fallback)
- `AnyKernel3-*-5.4.302-*.zip` (kernel + `modules/vendor/lib/modules/qca_cld3_*.ko`)

## HOW TO USE

```
fastboot reboot fastboot
fastboot flash boot boot_ksu.img
# If needed:
fastboot -w
```

AnyKernel3: flash in recovery / Kernel Flasher. It installs the kernel and pushes WiFi `.ko` to `/vendor/lib/modules/` (`do.modules=1`). **Do not** install the KernelSU WiFi module after flashing AnyKernel3.

Standalone WiFi zip: only needed if you flashed `boot_ksu.img` via fastboot (that path does not replace vendor kos). Install via KernelSU Manager after first boot, then reboot.
