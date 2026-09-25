# AI Handover — xpeng_kernel_susfs

> This document is AI-written to let the **next AI (or human maintainer) take over without rediscovering everything**:
> SUSFS + ReSukiSU + optional module kernel builds, kernel porting and compile pitfalls, fixes, GitHub Actions flow,
> verification methods, and version archive.
>
> **Corresponds to verified build: 2026-09-25 all-modules local build**, flashed and successfully booted on Edge S30.

---

## 0. One-liner

Motorola **xpeng** (Edge S30 / G200, **5.4 kernel**) build script repo with
**SUSFS v2.2.0** + **ReSukiSU (pinned 59c99fdf)** and optional
**Re:Kernel + Baseband-guard + BBRv3 + DroidSpaces**, built and released via GitHub Actions.

---

## 1. Repository topology (two repos, both required)

| Repository | Role | Branch |
|------------|------|--------|
| `paulcbfly/xpeng_kernel_susfs` | **Build repo**: scripts + GitHub Actions workflow | `5.4.302-s3rxc32.33-8-25-ReSukiSU` |
| `paulcbfly/android_kernel_motorola_xpeng` | Kernel source + all adaptation commits | `5.4.302-s3rxc32.33-8-25-susfs-modules` |

- The build repo does **not** contain kernel sources; the workflow clones the kernel repo at build time.
- Kernel branch `5.4.302-s3rxc32.33-8-25-susfs-modules`:
  - Base = upstream `5.4.302-s3rxc32.33-8-25`
  - + SUSFS commit `b3ecce7eb`
  - + 4-module port commit `8972cd10c` (Re:Kernel / DroidSpaces / BBGuard / BBRv3)
  - + fq default qdisc commit `b565fa013`
- Submodule: `KernelSU` → ReSukiSU @ `59c99fdf` (pinned for SUSFS v2.2.0 compatibility)

### Key build-repo modifications

- `.github/workflows/build-resukisu-edge-s30.yml` (Edge S30), `build-resukisu-g200.yml` (G200)
  - `KERNEL_URL` → `https://github.com/paulcbfly/android_kernel_motorola_xpeng.git`
  - `KERNEL_BRANCH` → `5.4.302-s3rxc32.33-8-25-susfs-modules`
  - `UPDATE_RESUKISU` → `${{ inputs.update_resukisu || 'false' }}` (default no update)
  - 4 module inputs: `enable_rekernel` / `enable_droidspaces` / `enable_bbguard` / `enable_bbrv3` (default true)
  - **No `enable_susfs` toggle**: SUSFS is baseline, always ON
  - **Fixed `|| 'true'` bug**: old `inputs.x || 'true'` silently forced modules ON; now uses `inputs.enable_x`
- `scripts/ci/build_resukisu_boot.sh`
  - `KERNEL_URL` / `KERNEL_BRANCH` defaults as above
  - `build_module_tag()` generates artifact suffix from enabled modules
  - `build_kernel()` adjusts `.config` via `scripts/config` based on `ENABLE_*` env vars after defconfig and before olddefconfig
- `scripts/ci/pack_anykernel3.sh`
  - Renames zip to `AK3-xpeng-EdgeS30-<module-suffix>-<build>.zip`
  - Release notes list each module as ✅/❌

---

## 2. Build issues and fixes (by severity)

### Issue #1 (fatal, abandoned): old `-modules-nosec` branch boot-loops

**Symptom**: `-modules-nosec` compiled successfully but failed to boot.

**Root cause**: Its BBRv3 TCP changes were incompatible with the xpeng 5.4.302 baseline, breaking network init during boot.

**Action**:
- Delete `-modules-nosec` branch, **never reuse**.
- Restart from stable `5.4.302-s3rxc32.33-8-25-susfs` and strictly port from **LuoJuly/android_kernel_motorola_sm7325 `lineage-23.2-SUSFS`**.

---

### Issue #2 (critical): differences between LuoJuly sm7325 and xpeng MMI tree

sm7325 is a lineage kernel; xpeng is MMI. Do not blindly `git apply`.

| sm7325 original | xpeng reality | Adjustment |
|---|---|---|
| defconfig target = `lineage_xpeng.config` | MMI uses `ext_config/moto-lahaina-xpeng.config` fragment | Rewrite to that fragment |
| `CONFIG_DEFAULT_QDISC="fq"` | only `CONFIG_DEFAULT_NET_SCH` exists | use `NET_SCH_DEFAULT=y` + `DEFAULT_FQ=y` |
| `NETFILTER_XT_TARGET_REJECT` | only `IP_NF_TARGET_REJECT` exists | use `IP_NF_TARGET_REJECT=y` |
| CONFIG_LSM includes `bpf` | no `security/bpf` in tree | remove `bpf` from LSM string |
| `CONFIG_TCP_ECN=y` | no such symbol in 5.4 mainline | skip |
| `TCP_CONG_BRUTAL` | no source in either tree | skip |

**Porting method**:
- Use `git apply --include=...` for clean file additions
- Manually edit `defconfig`, `.gitmodules`, `drivers/Kconfig`, `drivers/Makefile`, `security/Kconfig`, `security/Makefile`
- Re:Kernel final version lives in `drivers/rekernel/`; remove stale `drivers/net/rekernel/` references

---

### Issue #3 (local build blocker): missing `python` command breaks WLAN build

**Symptom**:

```
/bin/sh: 1: python: not found
.../qcacld-3.0/.wlan/Kbuild:36: .../configs/default_defconfig: No such file or directory
```

**Root cause**: `qcacld-3.0/.wlan/Kbuild` line 33 calls `python -c "import os.path; print(os.path.relpath(...))"`.
Ubuntu 22.04 has only `python3`. Empty output corrupts `WLAN_ROOT`, so `configs/default_defconfig` is not found.

**Fix**:

```bash
ln -sf /usr/bin/python3 /usr/local/bin/python
```

GitHub Actions' ubuntu-22.04 runner provides `python`, so CI does not hit this.

---

### Issue #4 (config merge): DroidSpaces vs SYSVIPC FCM conflict

**Symptom**: Some DroidSpaces configs want `CONFIG_SYSVIPC=y`, but xpeng baseline keeps it off.

**Root cause**: FCM v7 requires certain IPC configs to stay default-off; DroidSpaces KABI patch moves `sysv` fields into KABI reserved slots for compatibility.

**Action**:
- Apply KABI patch (LuoJuly commit `f05b8df8`)
- Keep `CONFIG_SYSVIPC` default-off
- Enable `IPC_NS`, `PID_NS`, `POSIX_MQUEUE` etc. for DroidSpaces

---

### Issue #5 (BBGuard LSM): `CONFIG_LSM` string format and validation

**Symptom**: With BBGuard enabled, kernel LSM registration fails or `CONFIG_LSM` is overwritten incorrectly.

**Root cause**: `CONFIG_LSM` is a double-quoted string like `"lockdown,yama,baseband_guard"`. Direct `--set-str` can fail with spaces or special characters.

**Action**:
- In `build_kernel()`, read current `CONFIG_LSM` and append `baseband_guard`
- Preserve existing LSMs (`lockdown,yama,selinux`)
- Do not overwrite with a fixed string

---

## 3. GitHub Actions build flow

### Trigger

```bash
gh workflow run build-resukisu-edge-s30.yml --ref 5.4.302-s3rxc32.33-8-25-ReSukiSU
gh workflow run build-resukisu-g200.yml --ref 5.4.302-s3rxc32.33-8-25-ReSukiSU
gh run list --workflow build-resukisu-edge-s30.yml --limit 3
gh run view <RUN_ID> --log-failed     # failed logs
```

- Monthly schedule: UTC 00:00 1st (Edge S30), 02:00 1st (G200), all modules ON by default
- Web trigger: Actions → Run workflow → check/uncheck modules

### Workflow internals (40-60 min)

1. `actions/checkout` build repo `5.4.302-s3rxc32.33-8-25-ReSukiSU`
2. Cache/download toolchain: `clang-r383902b1` (AOSP) + GCC 4.9 (Lineage 19.1) + magiskboot
3. `build_resukisu_boot.sh`:
   - `fetch_kernel`: clone kernel fork `5.4.302-s3rxc32.33-8-25-susfs-modules` (--recursive)
   - `update_resukisu`: pin KernelSU submodule to `59c99fdf` (default)
   - `setup_toolchain`, `build_kernel` (generate_defconfig → **module toggles** → olddefconfig → Image)
   - `build_wlan_modules` (WiFi kos)
   - `repack_boot` (magiskboot packs boot_ksu.img)
   - `pack_anykernel3` (Image + WiFi kos, AK3 naming)
4. Upload artifact + create GitHub Release (body lists module toggle states)

### Artifact naming

```
AK3-xpeng-EdgeS30-ReKernel-DroidSpaces-BBGuard-BBRv3-r{N}.zip
boot_ksu.img
Image
wlan_crc_match_5.4.302-ksu-g<sha>_.zip
```

---

## 4. Module toggle implementation

In `build_kernel()`, after `make vendor/lahaina-qgki_defconfig` and before `olddefconfig`:

```bash
sha="${KERNEL_DIR}/scripts/config"
"$sha" --file "${OUT_DIR}/.config" --enable/--disable/--set-str <CONFIG> ...
```

| Env var | OFF action |
|---|---|
| `ENABLE_REKERNEL=false` | `--disable REKERNEL` |
| `ENABLE_BBGUARD=false` | `--disable BBG`; remove `baseband_guard` from `CONFIG_LSM` |
| `ENABLE_BBRV3=false` | `--disable TCP_CONG_BBR DEFAULT_BBR`; `--set-str DEFAULT_TCP_CONG cubic` |
| `ENABLE_DROIDSPACES=false` | `--disable POSIX_MQUEUE IPC_NS PID_NS DEVTMPFS NETFILTER_XT_SET IP_SET` etc. |

> SUSFS is baseline and always ON; there is no `ENABLE_SUSFS` toggle.

---

## 5. Local reproduction (verified)

### Environment

- Host: Ubuntu 22.04 (or equivalent Linux container/VM)
- 16 cores / 7.4G RAM + 9G swap
- Build repo path: `/root/xpeng-build`
- Kernel source path: `/root/kernel-src`

### Steps

```bash
# 1. Ensure python symlink exists
ln -sf /usr/bin/python3 /usr/local/bin/python

# 2. Build
export VARIANT=edge-s30
export ENABLE_NFC=false
export UPDATE_RESUKISU=false
export KERNEL_URL=https://github.com/paulcbfly/android_kernel_motorola_xpeng.git
export KERNEL_BRANCH=5.4.302-s3rxc32.33-8-25-susfs-modules
./scripts/ci/build_resukisu_boot.sh
```

### Time baseline

| Stage | Time |
|---|---|
| First toolchain download | ~6.5 min |
| Kernel Image build | ~17 min |
| WLAN 3-chip modules | ~19.5 min |
| repack + AnyKernel3 | ~20 sec |
| **Full successful build** | **~43.5 min** |

### Artifacts

`.ci-work/<variant>/release/`:

- `boot_ksu.img` / `Image`
- `wlan_crc_match_*.zip`
- `AK3-*.zip`

---

## 6. Pitfall quick-reference

| Symptom | Cause | Fix |
|---|---|---|
| Boot loop after flash | Old `-modules-nosec` branch BBRv3 incompatible | Use new `susfs-modules` branch |
| WLAN build `python: not found` | Build environment lacks `python` command | `ln -sf /usr/bin/python3 /usr/local/bin/python` |
| `CONFIG_LSM` contains `bpf` error | xpeng tree has no `security/bpf` | Remove `bpf` from LSM string |
| `DEFAULT_QDISC="fq"` not found | xpeng uses `DEFAULT_NET_SCH` | `NET_SCH_DEFAULT=y` + `DEFAULT_FQ=y` |
| `NETFILTER_XT_TARGET_REJECT` not found | xpeng uses `IP_NF_TARGET_REJECT` | Use `IP_NF_TARGET_REJECT=y` |
| `drivers/net/rekernel/Kconfig` missing | Stale netlink version reference | Remove from `drivers/net/Kconfig` + `Makefile` |

---

## 7. Future upgrade paths

### Upgrade SUSFS v2.3.0 / latest ReSukiSU

1. Kernel side: replace `fs/susfs.c`, `include/linux/susfs.h`, `include/linux/susfs_def.h` with `cctv18/susfs4oki` (v2.3.0);
   **note AS_FLAGS moved from `inode->i_state` → `inode->i_mapping->flags`**, so update all set_bit/test_bit in hook files;
   v2.3.0 adds `fs/super.c` hook, needs manual 5.4 port.
2. Release `UPDATE_RESUKISU` lock (set schedule/default to true).
3. Verify locally before pushing.

### Add new modules

- Reference LuoJuly sm7325 lineage branch commits
- Watch xpeng vs sm7325 differences: defconfig path, Kconfig symbols, LSM string
- Add a separate toggle for each new module, default OFF, enable by default only after stable verification

---

## 8. Version archive

Archive of this verified build:

- [`docs/ARCHIVE-2026-09-25-modules-local.md`](ARCHIVE-2026-09-25-modules-local.md)

---

*Document generated 2026-09-25. Author: AI assistant (100% AI-generated project).*
