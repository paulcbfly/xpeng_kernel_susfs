#!/usr/bin/env bash
# Build xpeng MMI kernel (ReSukiSU), WLAN KSU module, repack boot, pack AnyKernel3.
#
# This script lives in android_kernel_motorola_xpeng_build and clones kernel sources
# from github.com/LuoJuly/android_kernel_motorola_xpeng (not vendored here).
#
# Variants:
#   VARIANT=edge-s30  ENABLE_NFC=false  -> Moto Edge S30 (XT2175-2)
#   VARIANT=g200      ENABLE_NFC=true   -> Moto G200 5G (XT2175-1)
#
# Default kernel branch: 5.4.302-s3rxc32.33-8-25 (kernel version label 5.4.302).
# Pipeline: Image -> WiFi kos (vermagic-matched) -> optional Magisk/KSU wifi zip
#           (fastboot-only fallback) -> boot_ksu.img -> AnyKernel3
#           (Image + vendor .ko via do.modules=1; no KSU wifi zip inside AK3).
set -euo pipefail

BUILD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${BUILD_ROOT}"

VARIANT="${VARIANT:-edge-s30}"
# Allow explicit ENABLE_NFC=true/false; variant only supplies the default.
ENABLE_NFC_ENV="${ENABLE_NFC-}"
ROM_ID="${ROM_ID:-S3RXC32.33-8-25}"
KERNEL_VER_LABEL="${KERNEL_VER_LABEL:-5.4.302}"
DEVICE="${DEVICE:-xpeng}"
TARGET_PRODUCT="${TARGET_PRODUCT:-xpeng_retcn}"
TARGET_BUILD_VARIANT="${TARGET_BUILD_VARIANT:-user}"
CLANG_VERSION="${CLANG_VERSION:-clang-r383902b1}"
CLANG_GIT_URL="${CLANG_GIT_URL:-https://mirrors.bfsu.edu.cn/git/AOSP/platform/prebuilts/clang/host/linux-x86}"
CLANG_GIT_FALLBACK="${CLANG_GIT_FALLBACK:-https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86}"
# AOSP main tip is empty; use Lineage mirror (same as local xpeng-build/setup.sh).
GCC_GIT_URL="${GCC_GIT_URL:-https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git}"
GCC_GIT_BRANCH="${GCC_GIT_BRANCH:-lineage-19.1}"
GCC_GIT_FALLBACK="${GCC_GIT_FALLBACK:-https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9}"
GCC_GIT_FALLBACK_BRANCH="${GCC_GIT_FALLBACK_BRANCH:-master-kernel-build-2021}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-${BUILD_ROOT}/.ci-toolchain}"
XPENG_BUILD_ROOT="${XPENG_BUILD_ROOT:-${BUILD_ROOT}}"
JOBS="${JOBS:-$(nproc)}"
BOOT_OEM_IMG="${BOOT_OEM_IMG:-${BUILD_ROOT}/prebuilt/boot_oem.img}"
# Large OEM boot is kept as a Release asset (not in git) to avoid flaky huge pushes.
BOOT_OEM_RELEASE_REPO="${BOOT_OEM_RELEASE_REPO:-LuoJuly/android_kernel_motorola_xpeng_build}"
# Tag prefix z- keeps this utility release at the bottom of the Releases list.
BOOT_OEM_RELEASE_TAG="${BOOT_OEM_RELEASE_TAG:-z-assets-S3RXC32.33-8-29}"
BOOT_OEM_ASSET_NAME="${BOOT_OEM_ASSET_NAME:-boot_oem.img}"
BUILD_WLAN="${BUILD_WLAN:-true}"
WLAN_TAG="${WLAN_TAG:-MMI-S3RXC32.33-8-29}"

KERNEL_URL="${KERNEL_URL:-https://github.com/paulcbfly/android_kernel_motorola_xpeng.git}"

# ---------------------------------------------------------------------------
# SUSFS version selection.
#   v2.2 (default) -> 5.4.302-s3rxc32.33-8-25-susfs-modules        (stable)
#   v2.3           -> 5.4.302-s3rxc32.33-8-25-susfs-modules-v2.3-astide
# v2.2 is the long-verified stable line. v2.3 is newer (kstat/STATX rework,
# extra hook coverage) and has boot-verified builds too, but if you hit any
# bug you can simply rebuild with SUSFS_VERSION=v2.2 to fall back.
# ---------------------------------------------------------------------------
SUSFS_VERSION="${SUSFS_VERSION:-v2.2}"
case "${SUSFS_VERSION}" in
  v2.2|2.2|susfs2.2|susfs22)
    SUSFS_VERSION="v2.2"
    SUSFS_BRANCH_DEFAULT="5.4.302-s3rxc32.33-8-25-susfs-modules"
    ;;
  v2.3|2.3|susfs2.3|susfs23)
    SUSFS_VERSION="v2.3"
    SUSFS_BRANCH_DEFAULT="5.4.302-s3rxc32.33-8-25-susfs-modules-v2.3-astide"
    ;;
  *)
    echo "[!] Unknown SUSFS_VERSION=${SUSFS_VERSION} (use v2.2 or v2.3)" >&2
    exit 1
    ;;
esac
# An explicit KERNEL_BRANCH always wins over the SUSFS_VERSION default.
# Use an explicit "is it already set?" check rather than ${VAR:-default} so that
# re-running the logic in one shell never leaves a stale branch behind.
if [[ -z "${KERNEL_BRANCH:-}" ]]; then
  KERNEL_BRANCH="${SUSFS_BRANCH_DEFAULT}"
else
  echo "[+] KERNEL_BRANCH explicitly set to ${KERNEL_BRANCH} (overrides SUSFS_VERSION=${SUSFS_VERSION} mapping)"
fi
KERNEL_DIR="${KERNEL_DIR:-${BUILD_ROOT}/.ci-src/android_kernel_motorola_xpeng}"

case "${VARIANT}" in
  edge-s30|edges30|xt2175-2)
    VARIANT=edge-s30
    VARIANT_SLUG="xpeng-EdgeS30"
    DEVICE_TITLE="Moto Edge S30 (XT2175-2)"
    RELEASE_TITLE="xpeng ${KERNEL_VER_LABEL} ReSukiSU Boot/Kernel for Moto Edge S30 (XT2175-2)"
    ENABLE_NFC="${ENABLE_NFC_ENV:-false}"
    ;;
  g200|xt2175-1)
    VARIANT=g200
    VARIANT_SLUG="xpeng-G200"
    DEVICE_TITLE="Moto G200 5G (XT2175-1)"
    RELEASE_TITLE="xpeng ${KERNEL_VER_LABEL} ReSukiSU Boot/Kernel for Moto G200 5G (XT2175-1)"
    ENABLE_NFC="${ENABLE_NFC_ENV:-true}"
    ;;
  *)
    echo "[!] Unknown VARIANT=${VARIANT} (use edge-s30 or g200)" >&2
    exit 1
    ;;
esac

WORK_DIR="${WORK_DIR:-${BUILD_ROOT}/.ci-work/${VARIANT}}"
OUT_DIR="${OUT_DIR:-${BUILD_ROOT}/out/${VARIANT}}"
HOST_BIN_DIR="${BUILD_ROOT}/scripts/ci/host-bin"

mkdir -p "${TOOLCHAIN_DIR}" "${OUT_DIR}" "${WORK_DIR}"
mkdir -p "${WORK_DIR}/boot" "${WORK_DIR}/release" "$(dirname "${KERNEL_DIR}")"

log() { echo "::group::$1"; }
endlog() { echo "::endgroup::"; }
info() { echo "[+] $*"; }
warn() { echo "[!] $*" >&2; }
die() { echo "[!] $*" >&2; exit 1; }

curl_get() {
  curl -L --http1.1 --retry 5 --retry-all-errors --retry-delay 3 "$@"
}

gh_env() {
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf '%s=%s\n' "$1" "$2" >> "${GITHUB_ENV}"
  fi
}

# Build module suffix tag from enabled optional-module toggles.
# e.g. all on -> "-ReKernel-DroidSpaces-BBGuard-BBRv3", all off -> "".
# SUSFS is core (always on) but its *version* is part of the tag so v2.2 and
# v2.3 artifacts never collide / are never mistaken for each other.
build_module_tag() {
  local tag=""
  [[ "${ENABLE_REKERNEL:-true}" == "true" ]] && tag+="-ReKernel"
  [[ "${ENABLE_DROIDSPACES:-true}" == "true" ]] && tag+="-DroidSpaces"
  [[ "${ENABLE_BBGUARD:-true}" == "true" ]] && tag+="-BBGuard"
  [[ "${ENABLE_BBRV3:-true}" == "true" ]] && tag+="-BBRv3"
  printf '%s' "${tag}"
}

# e.g. "SUSFSv2.3" — appended to release/artifact names.
build_susfs_tag() {
  printf 'SUSFS%s' "${SUSFS_VERSION}"
}

# ---------------------------------------------------------------------------
# 1) Fetch kernel sources (git only; not uploaded in this repo)
# ---------------------------------------------------------------------------
fetch_kernel() {
  log "Fetch kernel source (${KERNEL_BRANCH})"

  if [[ -n "${KERNEL_SRC:-}" && -d "${KERNEL_SRC}/.git" ]]; then
    KERNEL_DIR="$(cd "${KERNEL_SRC}" && pwd)"
    info "Using existing KERNEL_SRC=${KERNEL_DIR}"
  elif [[ -d "${KERNEL_DIR}/.git" ]]; then
    info "Updating existing clone at ${KERNEL_DIR}"
    git -C "${KERNEL_DIR}" fetch --tags origin
    git -C "${KERNEL_DIR}" checkout -f "${KERNEL_BRANCH}"
    git -C "${KERNEL_DIR}" reset --hard "origin/${KERNEL_BRANCH}" 2>/dev/null \
      || git -C "${KERNEL_DIR}" reset --hard "${KERNEL_BRANCH}"
    git -C "${KERNEL_DIR}" submodule sync --recursive
    git -C "${KERNEL_DIR}" submodule update --init --recursive
  else
    # Prefer local symlink/tree used by setup.sh to avoid re-cloning on local hosts
    local local_link="${BUILD_ROOT}/kernel/msm-5.4"
    if [[ -d "${local_link}/.git" || -d "${local_link}/KernelSU" ]]; then
      local resolved
      resolved="$(cd "${local_link}" && pwd -P)"
      if [[ -d "${resolved}/.git" ]]; then
        KERNEL_DIR="${resolved}"
        info "Using local kernel tree via kernel/msm-5.4 -> ${KERNEL_DIR}"
      fi
    fi

    if [[ ! -d "${KERNEL_DIR}/.git" ]]; then
      info "git clone --recursive --branch ${KERNEL_BRANCH} ${KERNEL_URL}"
      rm -rf "${KERNEL_DIR}"
      git clone --recursive --branch "${KERNEL_BRANCH}" --single-branch \
        "${KERNEL_URL}" "${KERNEL_DIR}"
    fi
  fi

  [[ -d "${KERNEL_DIR}" ]] || die "kernel dir missing: ${KERNEL_DIR}"
  [[ -f "${KERNEL_DIR}/Makefile" ]] || die "not a kernel tree: ${KERNEL_DIR}"
  info "KERNEL_DIR=${KERNEL_DIR}"
  gh_env KERNEL_DIR "${KERNEL_DIR}"
  export KERNEL_DIR
  endlog
}

# ---------------------------------------------------------------------------
# 2) Update ReSukiSU submodule
# ---------------------------------------------------------------------------
update_resukisu() {
  log "Update ReSukiSU submodule"
  cd "${KERNEL_DIR}"

  if [[ ! -e KernelSU/.git ]]; then
    git submodule update --init --recursive KernelSU
  fi

  # xpeng 5.4.302 only supports SUSFS v2.2. The pinned ReSukiSU commit below is
  # the known-good version that boots with the v2.2.0 kernel-side integration.
  # "latest" / origin/main is NOT supported because it expects SUSFS v2.3+ APIs.
  local resukisu_mode="${RESUKISU_VERSION:-pinned}"
  RE_SUKISU_PIN="${RE_SUKISU_PIN:-59c99fdf1735c37681ff18c7ffd7834741dcccbf}"

  case "${resukisu_mode}" in
    custom)
      local ref="${RESUKISU_CUSTOM_REF:-${RE_SUKISU_PIN}}"
      git -C KernelSU fetch origin "${ref}" --tags --force 2>/dev/null || true
      git -C KernelSU checkout -f "${ref}" 2>/dev/null \
        || git -C KernelSU checkout -f FETCH_HEAD 2>/dev/null || true
      info "ReSukiSU checked out custom ref ${ref}"
      ;;
    latest)
      info "WARN: RESUKISU_VERSION=latest is disabled on xpeng 5.4.302; forcing pinned commit"
      ;&
    pinned|*)
      git -C KernelSU checkout -f "${RE_SUKISU_PIN}" 2>/dev/null \
        || git -C KernelSU checkout -f FETCH_HEAD 2>/dev/null || true
      info "ReSukiSU pinned to ${RE_SUKISU_PIN} (SUSFS v2.2.0 compatible)"
      ;;
  esac

  RESUKISU_VERSION="$(git -C KernelSU describe --tags --always)"
  RESUKISU_SHA="$(git -C KernelSU rev-parse --short=8 HEAD)"
  local ksu_count
  ksu_count="$(git -C KernelSU rev-list --count HEAD)"
  KSU_VERSION="$((30000 + ksu_count + 700))"
  KSU_UAPI_VERSION="$(
    sed -nE 's/.*KERNEL_SU_UAPI_VERSION[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' \
      KernelSU/uapi/supercall.h 2>/dev/null | head -1
  )"
  KSU_UAPI_VERSION="${KSU_UAPI_VERSION:-2}"
  # e.g. v4.1.0-1332-g59c99fdf@ReSukiSU (35046/2)
  RESUKISU_DISPLAY="${RESUKISU_VERSION}@ReSukiSU (${KSU_VERSION}/${KSU_UAPI_VERSION})"

  info "ReSukiSU: ${RESUKISU_DISPLAY}"
  gh_env RESUKISU_VERSION "${RESUKISU_VERSION}"
  gh_env RESUKISU_SHA "${RESUKISU_SHA}"
  gh_env KSU_VERSION "${KSU_VERSION}"
  gh_env KSU_UAPI_VERSION "${KSU_UAPI_VERSION}"
  gh_env RESUKISU_DISPLAY "${RESUKISU_DISPLAY}"
  export RESUKISU_VERSION RESUKISU_SHA KSU_VERSION KSU_UAPI_VERSION RESUKISU_DISPLAY
  printf '%s\n' "${RESUKISU_VERSION}" > "${WORK_DIR}/resukisu_version.txt"
  printf '%s\n' "${RESUKISU_DISPLAY}" > "${WORK_DIR}/resukisu_display.txt"
  printf '%s\n' "${KSU_VERSION}" > "${WORK_DIR}/ksu_version.txt"
  printf '%s\n' "${KSU_UAPI_VERSION}" > "${WORK_DIR}/ksu_uapi_version.txt"
  printf '%s\n' "${ROM_ID}" > "${WORK_DIR}/rom_id.txt"
  cd "${BUILD_ROOT}"
  endlog
}

# ---------------------------------------------------------------------------
# 3) Toolchain (prefer this tree / XPENG_BUILD_ROOT, else download)
# ---------------------------------------------------------------------------
resolve_tool() {
  local name="$1"
  shift
  local cand
  for cand in "$@"; do
    if [[ -n "${cand}" && -x "${cand}" ]]; then
      printf '%s\n' "${cand}"
      return 0
    fi
  done
  die "MISSING tool: ${name}"
}

setup_toolchain() {
  log "Setup toolchain (${CLANG_VERSION})"

  local clang_bin ld_lld llvm_ar llvm_nm make_bin gcc_prefix dtc_bin ufdt_bin

  if [[ -x "${XPENG_BUILD_ROOT}/prebuilts/clang/host/linux-x86/${CLANG_VERSION}/bin/clang" ]]; then
    info "Using toolchains at ${XPENG_BUILD_ROOT}"
    clang_bin="${XPENG_BUILD_ROOT}/prebuilts/clang/host/linux-x86/${CLANG_VERSION}/bin/clang"
    ld_lld="${XPENG_BUILD_ROOT}/prebuilts/clang/host/linux-x86/${CLANG_VERSION}/bin/ld.lld"
    llvm_ar="${XPENG_BUILD_ROOT}/prebuilts/clang/host/linux-x86/${CLANG_VERSION}/bin/llvm-ar"
    llvm_nm="${XPENG_BUILD_ROOT}/prebuilts/clang/host/linux-x86/${CLANG_VERSION}/bin/llvm-nm"
    make_bin="${XPENG_BUILD_ROOT}/prebuilts/build-tools/linux-x86/bin/make"
    gcc_prefix="${XPENG_BUILD_ROOT}/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
    dtc_bin="${XPENG_BUILD_ROOT}/prebuilts/misc/linux-x86/dtc/dtc"
    ufdt_bin="${XPENG_BUILD_ROOT}/prebuilts/misc/linux-x86/libufdt/ufdt_apply_overlay"
  else
    info "Preparing CI toolchains under ${TOOLCHAIN_DIR}"
    local clang_dir="${TOOLCHAIN_DIR}/clang/host/linux-x86"
    if [[ ! -x "${clang_dir}/${CLANG_VERSION}/bin/clang" ]]; then
      mkdir -p "${clang_dir}"
      if [[ ! -d "${clang_dir}/.git" ]]; then
        git clone --filter=blob:none --no-checkout "${CLANG_GIT_URL}" "${clang_dir}" \
          || git clone --filter=blob:none --no-checkout "${CLANG_GIT_FALLBACK}" "${clang_dir}"
      fi
      (
        cd "${clang_dir}"
        git sparse-checkout init --cone
        git sparse-checkout set "${CLANG_VERSION}"
        git checkout 225d2925 2>/dev/null || git checkout main || git checkout master
      )
    fi
    [[ -x "${clang_dir}/${CLANG_VERSION}/bin/clang" ]] || die "clang not found after clone"

    local gcc_dir="${TOOLCHAIN_DIR}/gcc/linux-x86/aarch64/aarch64-linux-android-4.9"
    if [[ ! -x "${gcc_dir}/bin/aarch64-linux-android-gcc" ]]; then
      mkdir -p "$(dirname "${gcc_dir}")"
      # Drop empty/broken clones (AOSP main tip has no binaries).
      if [[ -d "${gcc_dir}" && ! -x "${gcc_dir}/bin/aarch64-linux-android-gcc" ]]; then
        info "Removing incomplete gcc tree at ${gcc_dir}"
        rm -rf "${gcc_dir}"
      fi
      if [[ ! -d "${gcc_dir}/.git" ]]; then
        info "Cloning gcc 4.9 from ${GCC_GIT_URL} (${GCC_GIT_BRANCH})"
        git clone --depth=1 --branch "${GCC_GIT_BRANCH}" "${GCC_GIT_URL}" "${gcc_dir}" \
          || git clone --depth=1 --branch "${GCC_GIT_FALLBACK_BRANCH}" \
               "${GCC_GIT_FALLBACK}" "${gcc_dir}"
      fi
    fi
    [[ -x "${gcc_dir}/bin/aarch64-linux-android-gcc" ]] || die "gcc 4.9 not found after clone"

    clang_bin="${clang_dir}/${CLANG_VERSION}/bin/clang"
    ld_lld="${clang_dir}/${CLANG_VERSION}/bin/ld.lld"
    llvm_ar="${clang_dir}/${CLANG_VERSION}/bin/llvm-ar"
    llvm_nm="${clang_dir}/${CLANG_VERSION}/bin/llvm-nm"
    make_bin="$(resolve_tool make \
      "${HOST_BIN_DIR}/make" \
      "$(command -v make || true)")"
    gcc_prefix="${gcc_dir}/bin/aarch64-linux-android-"
    dtc_bin="$(resolve_tool dtc \
      "${HOST_BIN_DIR}/dtc" \
      "$(command -v dtc || true)")"
    ufdt_bin="$(resolve_tool ufdt_apply_overlay \
      "${HOST_BIN_DIR}/ufdt_apply_overlay")"
  fi

  # Prefer bundled host-bin when present (portable CI binaries)
  [[ -x "${HOST_BIN_DIR}/make" ]] && make_bin="${HOST_BIN_DIR}/make"
  [[ -x "${HOST_BIN_DIR}/dtc" ]] && dtc_bin="${HOST_BIN_DIR}/dtc"
  [[ -x "${HOST_BIN_DIR}/ufdt_apply_overlay" ]] && ufdt_bin="${HOST_BIN_DIR}/ufdt_apply_overlay"

  for t in "${clang_bin}" "${ld_lld}" "${llvm_ar}" "${llvm_nm}" "${make_bin}" \
           "${gcc_prefix}gcc" "${dtc_bin}" "${ufdt_bin}"; do
    [[ -x "${t}" ]] || die "MISSING: ${t}"
  done

  CLANG="${clang_bin}"
  LD_LLD="${ld_lld}"
  LLVM_AR="${llvm_ar}"
  LLVM_NM="${llvm_nm}"
  MAKE="${make_bin}"
  AARCH64_PREFIX="${gcc_prefix}"
  DTC_EXT="${dtc_bin}"
  UFDT_EXT="${ufdt_bin}"
  export CLANG LD_LLD LLVM_AR LLVM_NM MAKE AARCH64_PREFIX DTC_EXT UFDT_EXT
  export PATH="${HOST_BIN_DIR}:$(dirname "${CLANG}"):${PATH}"
  export TARGET_BUILD_VARIANT TARGET_PRODUCT
  # generate_defconfig invokes `${MAKE_PATH}make`
  export MAKE_PATH="${HOST_BIN_DIR}/"

  info "clang: $(${CLANG} --version | head -1)"
  info "make: ${MAKE}"
  info "NFC: ${ENABLE_NFC}"
  endlog
}

# ---------------------------------------------------------------------------
# 3b) ccache-ECS setup (compile cache; big speedup on repeat builds)
#
# Adapted from cctv18/oppo_oplus_realme_sm8850:
#   - uses the ccache-ECS binary (a ccache fork with kernel-specific indexing)
#   - libfakestat.so / libfaketimeMT.so hijack file mtimes and __DATE__/__TIME__
#     so unrelated rebuilds keep hitting the same cache entries
#
# Masquerade mode: a directory of symlinks named `clang`/`clang++` is prepended
# to PATH. ccache inspects argv[0] to find the real compiler, so the kernel's
# own `clang` invocations are cached without touching the Makefile.
#
# Disable with ENABLE_CCACHE=false.
# ---------------------------------------------------------------------------
setup_ccache() {
  ENABLE_CCACHE="${ENABLE_CCACHE:-true}"
  if [[ "${ENABLE_CCACHE}" != "true" ]]; then
    info "ENABLE_CCACHE=false; compile cache disabled"
    return 0
  fi

  log "Setup ccache-ECS"

  local ccache_asset_dir="${BUILD_ROOT}/scripts/ci/ccache-ecs"
  local ccache_bin="${ccache_asset_dir}/ccache-x86-64"
  local fakestat_so="${ccache_asset_dir}/libfakestat.so"
  local faketime_so="${ccache_asset_dir}/libfaketimeMT.so"

  # Fall back to downloading from the upstream reference repo if not vendored.
  if [[ ! -f "${ccache_bin}" ]]; then
    info "ccache binary not vendored; downloading from reference repo"
    mkdir -p "${ccache_asset_dir}"
    local base="https://github.com/cctv18/oppo_oplus_realme_sm8850/raw/refs/heads/main/lib"
    curl_get -L -o "${ccache_bin}"    "${base}/ccache-x86-64"
    curl_get -L -o "${fakestat_so}"   "${base}/libfakestat.so"
    curl_get -L -o "${faketime_so}"   "${base}/libfaketimeMT.so"
  fi
  [[ -f "${ccache_bin}" ]] || die "ccache-ECS binary missing: ${ccache_bin}"
  chmod +x "${ccache_bin}"

  CCACHE_DIR="${CCACHE_DIR:-${HOME}/.ccache_xpeng}"
  CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-3G}"
  mkdir -p "${CCACHE_DIR}"

  # --- timeline pinning -----------------------------------------------------
  # Fixed mtime / __DATE__ so cache keys do not churn between runs.
  #
  # The preload libs are prebuilt upstream and pinned to a specific glibc:
  # libfakestat.so needs GLIBC_2.38 (__isoc23_sscanf), libfaketimeMT.so needs
  # GLIBC_2.34. When the runner image is older than that, loading simply fails
  # and *every* compile dies with a relocation error. Probe each library first
  # and drop the ones that cannot be loaded, so a stale runner degrades to a
  # lower hit rate instead of a hard build failure.
  export FAKESTAT="${FAKESTAT:-2026-01-01 12:00:00}"
  export FAKETIME="${FAKETIME:-@2026-01-01 13:00:00}"

  # ENABLE_FAKETIME=false drops both preload shims and runs plain ccache. Useful
  # for isolating whether a build failure comes from the time hijacking or from
  # ccache itself.
  ENABLE_FAKETIME="${ENABLE_FAKETIME:-true}"

  probe_preload() {
    local so="$1"
    [[ -f "${so}" ]] || return 1
    LD_PRELOAD="${so}" /bin/true >/dev/null 2>&1
  }

  local preload_libs=()
  if [[ "${ENABLE_FAKETIME}" != "true" ]]; then
    info "ENABLE_FAKETIME=false; running ccache without the fake-time shims"
  else
    if probe_preload "${fakestat_so}"; then
      preload_libs+=("${fakestat_so}")
    else
      warn "libfakestat.so cannot be loaded (needs GLIBC_2.38+); mtime pinning disabled"
    fi
    if probe_preload "${faketime_so}"; then
      preload_libs+=("${faketime_so}")
    else
      warn "libfaketimeMT.so cannot be loaded; __DATE__/time() pinning disabled"
    fi

    if ((${#preload_libs[@]} == 0)); then
      warn "no fake-time preload library usable; ccache will run without timeline pinning"
    fi
  fi
  export LD_PRELOAD_TMP="${preload_libs[*]:-}"

  # --- ccache environment ---------------------------------------------------
  export CCACHE_COMPILERCHECK="none"
  # Normalise absolute paths so entries stay valid across different runners and
  # workspace paths (GitHub uses /home/runner/work/... which can shift).
  export CCACHE_BASEDIR="${CCACHE_BASEDIR:-$(dirname "${KERNEL_DIR}")}"
  export CCACHE_NOHASHDIR="true"
  export CCACHE_NOHARDLINK="true"
  export CCACHE_DIR
  export CCACHE_MAXSIZE
  # ccache-ECS-specific switch: enables kernel-aware dependency indexing.
  export CCACHE_IS_KERNEL_COMPILING="true"
  export CCACHE_COMPRESS="true"

  # sloppiness: tolerate mtime/ctime drift, __DATE__/__TIME__ macros and PCH.
  # These are exactly the things the fake-time preload neutralises, so telling
  # ccache to ignore them prevents spurious misses. `pch_defines` must come with
  # `time_macros` per ccache docs.
  local conf="${CCACHE_DIR}/ccache.conf"
  if ! grep -q '^sloppiness' "${conf}" 2>/dev/null; then
    printf '\nsloppiness = file_stat_matches,include_file_ctime,include_file_mtime,pch_defines,file_macro,time_macros\n' >> "${conf}"
  fi

  # --- compiler / linker wrappers -------------------------------------------
  # Mirrors the upstream ccache-ECS scheme (cctv18/oppo_oplus_realme_sm8850):
  # a tiny `cc-wrapper` that preloads the fake-time libs and hands off to ccache,
  # plus an `ld-wrapper` that does the same for the linker. Both are passed to
  # make via CC= / LD= directly.
  #
  # Do NOT route these through PATH or REAL_CC: the kernel composes
  # `CC = scripts/gcc-wrapper.py $(REAL_CC)`, and pointing REAL_CC at a PATH-based
  # masquerade dir makes gcc-wrapper.py re-enter the ccache wrapper recursively.
  local wrap_dir="${WORK_DIR}/ccache-wrap"
  rm -rf "${wrap_dir}"
  mkdir -p "${wrap_dir}"

  local real_clang="${CLANG}"
  local real_ld="${LD_LLD}"

  {
    echo '#!/bin/bash'
    echo "export LD_PRELOAD=\"${LD_PRELOAD_TMP}\""
    echo "export FAKESTAT=\"${FAKESTAT}\""
    echo "export FAKETIME=\"${FAKETIME}\""
    echo "ccache ${real_clang} \"\$@\""
  } > "${wrap_dir}/cc-wrapper"

  {
    echo '#!/bin/bash'
    echo "export LD_PRELOAD=\"${LD_PRELOAD_TMP}\""
    echo "export FAKESTAT=\"${FAKESTAT}\""
    echo "export FAKETIME=\"${FAKETIME}\""
    echo "${real_ld} \"\$@\""
  } > "${wrap_dir}/ld-wrapper"

  chmod +x "${wrap_dir}/cc-wrapper" "${wrap_dir}/ld-wrapper"

  # `ccache` on PATH, exactly as upstream does, so the wrapper's bare `ccache`
  # resolves. Prepending a dir that only holds this one binary keeps it scoped.
  ln -sf "${ccache_bin}" "${wrap_dir}/ccache"
  export PATH="${wrap_dir}:${PATH}"

  CCACHE_CC="${wrap_dir}/cc-wrapper"
  export CCACHE_CC
  export CCACHE_LD="${wrap_dir}/ld-wrapper"

  "${ccache_bin}" -M "${CCACHE_MAXSIZE}" >/dev/null 2>&1 || true
  "${ccache_bin}" -o compression=true >/dev/null 2>&1 || true

  local ccache_ver
  ccache_ver="$("${ccache_bin}" --version 2>/dev/null | head -1 || true)"
  info "ccache-ECS: ${ccache_ver}"
  info "CCACHE_DIR=${CCACHE_DIR} CCACHE_MAXSIZE=${CCACHE_MAXSIZE}"
  info "wrapper dir=${wrap_dir}"
  info "CC=${CCACHE_CC}"
  info "LD=${CCACHE_LD}"
  info "ccache stats (before build):"
  "${ccache_bin}" -s 2>/dev/null || true

  gh_env CCACHE_DIR "${CCACHE_DIR}"
  gh_env CCACHE_MAXSIZE "${CCACHE_MAXSIZE}"
  endlog
}

# ---------------------------------------------------------------------------
# 4) Build kernel Image (Motorola GKI generate_defconfig flow)
# ---------------------------------------------------------------------------
apply_nfc_overlay() {
  local cfg="${KERNEL_DIR}/arch/arm64/configs/vendor/ext_config/moto-lahaina-xpeng.config"
  [[ -f "${cfg}" ]] || die "missing ${cfg}"

  if git -C "${KERNEL_DIR}" show HEAD:"arch/arm64/configs/vendor/ext_config/moto-lahaina-xpeng.config" >/dev/null 2>&1; then
    git -C "${KERNEL_DIR}" checkout HEAD -- "arch/arm64/configs/vendor/ext_config/moto-lahaina-xpeng.config"
  fi

  if [[ "${ENABLE_NFC}" == "true" ]]; then
    info "Enabling CONFIG_NFC_QTI_I2C=m for ${DEVICE_TITLE}"
    if grep -q '^# CONFIG_NFC_QTI_I2C is not set$' "${cfg}"; then
      sed -i 's/^# CONFIG_NFC_QTI_I2C is not set$/CONFIG_NFC_QTI_I2C=m/' "${cfg}"
    elif grep -q '^CONFIG_NFC_QTI_I2C=' "${cfg}"; then
      sed -i 's/^CONFIG_NFC_QTI_I2C=.*/CONFIG_NFC_QTI_I2C=m/' "${cfg}"
    else
      printf '\nCONFIG_NFC_QTI_I2C=m\n' >> "${cfg}"
    fi
  else
    info "Keeping NFC disabled (default) for ${DEVICE_TITLE}"
    if grep -q '^CONFIG_NFC_QTI_I2C=' "${cfg}"; then
      sed -i 's/^CONFIG_NFC_QTI_I2C=.*/# CONFIG_NFC_QTI_I2C is not set/' "${cfg}"
    fi
  fi
  grep -n 'NFC_QTI_I2C' "${cfg}" || true
}

restore_nfc_config() {
  if git -C "${KERNEL_DIR}" show HEAD:"arch/arm64/configs/vendor/ext_config/moto-lahaina-xpeng.config" >/dev/null 2>&1; then
    git -C "${KERNEL_DIR}" checkout HEAD -- \
      "arch/arm64/configs/vendor/ext_config/moto-lahaina-xpeng.config" 2>/dev/null || true
  fi
}

build_kernel() {
  log "Build kernel Image (${VARIANT}, NFC=${ENABLE_NFC})"
  apply_nfc_overlay
  trap restore_nfc_config EXIT

  export ARCH=arm64
  export KBUILD_BUILD_USER=github-actions
  export KBUILD_BUILD_HOST=resukisu-ci
  # Use the kernel source HEAD commit date as the deterministic build timestamp
  # so UTS_VERSION stays stable across rebuilds and matches the patch age.
  export KBUILD_BUILD_TIMESTAMP="$(git -C "${KERNEL_DIR}" log -1 --format=%cd --date=format-local:'%a %b %e %H:%M:%S %Z %Y' 2>/dev/null || date)"
  export TARGET_BUILD_VARIANT TARGET_PRODUCT

  local hostcflags hostldflags
  hostcflags="-I${KERNEL_DIR}/include/uapi -I/usr/include -I/usr/include/x86_64-linux-gnu -I${KERNEL_DIR}/include -L/usr/lib -L/usr/lib/x86_64-linux-gnu -fuse-ld=lld"
  hostldflags="-L/usr/lib -L/usr/lib/x86_64-linux-gnu -fuse-ld=lld"

  # When ccache-ECS is active, CC/LD point at the cc-wrapper/ld-wrapper so every
  # translation unit goes through the cache; otherwise they are the raw tools.
  # CC must be the absolute path to the wrapper (upstream does the same) — the
  # kernel's `CC = scripts/gcc-wrapper.py $(REAL_CC)` indirection would otherwise
  # re-enter the wrapper recursively.
  #
  # HOSTCC/HOSTLD deliberately stay on the REAL clang/ld.lld, exactly as upstream
  # does. Pointing HOSTCC at the wrapper makes ccache recurse into itself while
  # building the host tools (scripts/basic/fixdep etc.), which nests bash until
  # it hits the 1000-level limit and the whole build dies.
  local cc_bin="${CCACHE_CC:-${CLANG}}"
  local ld_bin="${CCACHE_LD:-${LD_LLD}}"
  info "CC=${cc_bin}"
  info "REAL_CC=${CLANG}"

  local common_make=(
    ARCH=arm64
    CROSS_COMPILE="${AARCH64_PREFIX}"
    CC="${cc_bin}"
    REAL_CC="${CLANG}"
    CLANG_TRIPLE=aarch64-linux-gnu-
    AR="${LLVM_AR}"
    LLVM_NM="${LLVM_NM}"
    LD="${ld_bin}"
    NM="${LLVM_NM}"
    DTC_EXT="${DTC_EXT}"
    DTC_OVERLAY_TEST_EXT="${UFDT_EXT}"
    CONFIG_BUILD_ARM64_DT_OVERLAY=y
    HOSTCC="${CLANG}"
    HOSTAR="${LLVM_AR}"
    HOSTLD="${LD_LLD}"
  )

  info "generate_defconfig vendor/lahaina-qgki_defconfig"
  local t_stage
  stage() {
    # Print a progress beacon with elapsed time. GitHub Actions buffers stdout
    # line-by-line, so anything that runs for minutes without emitting a newline
    # shows up as a frozen log -- which is indistinguishable from a hang when
    # you are eyeballing the web UI. Every make invocation below is wrapped so
    # the log always moves.
    local now; now=$(date +%s)
    if [[ -n "${t_stage:-}" ]]; then
      info "[$1] prev stage took $(( now - t_stage ))s"
    fi
    t_stage="$now"
    info "[+] ENTER $1"
  }

  # Run make with line-buffered output plus a background heartbeat, so a long
  # silent phase (syncconfig on a 65k-file tree, ccache cold start, ...) still
  # produces a visible tick every 30s instead of looking like a freeze.
  mk() {
    local label="$1"; shift
    local hb_pid
    (
      local n=0
      while :; do
        sleep 30
        n=$(( n + 30 ))
        echo "[hb] ${label}: still running (${n}s elapsed)"
      done
    ) &
    hb_pid=$!
    local rc=0
    stdbuf -oL -eL "${MAKE}" "$@" || rc=$?
    kill "${hb_pid}" 2>/dev/null || true
    wait "${hb_pid}" 2>/dev/null || true
    return "${rc}"
  }

  rm -rf "${OUT_DIR}"
  mkdir -p "${OUT_DIR}"

  pushd "${KERNEL_DIR}" >/dev/null

  # envsetup uses `ls ... 2>/dev/null` which may return non-zero
  set +e
  # shellcheck disable=SC1091
  source "${KERNEL_DIR}/scripts/gki/envsetup.sh" lahaina
  set -e

  stage "generate_defconfig"
  MAKE_PATH= ARCH=arm64 \
    CROSS_COMPILE="${AARCH64_PREFIX}" \
    CC="${cc_bin}" REAL_CC="${CLANG}" CLANG_TRIPLE=aarch64-linux-gnu- \
    AR="${LLVM_AR}" LLVM_NM="${LLVM_NM}" LD="${ld_bin}" NM="${LLVM_NM}" \
    KERN_OUT="${OUT_DIR}" \
    DTC_EXT="${DTC_EXT}" DTC_OVERLAY_TEST_EXT="${UFDT_EXT}" \
    CONFIG_BUILD_ARM64_DT_OVERLAY=y \
    HOSTCC="${CLANG}" HOSTAR="${LLVM_AR}" HOSTLD="${LD_LLD}" \
    TARGET_BUILD_VARIANT="${TARGET_BUILD_VARIANT}" \
    TARGET_PRODUCT="${TARGET_PRODUCT}" \
    "${KERNEL_DIR}/scripts/gki/generate_defconfig.sh" vendor/lahaina-qgki_defconfig

  info "defconfig (-j${JOBS})"
  mk "defconfig" -j"${JOBS}" -C "${KERNEL_DIR}" O="${OUT_DIR}" \
    "${common_make[@]}" \
    HOSTCFLAGS="${hostcflags}" HOSTLDFLAGS="${hostldflags}" \
    vendor/lahaina-qgki_defconfig

  # Enforce NFC choice on final .config as well
  if [[ "${ENABLE_NFC}" == "true" ]]; then
    "${KERNEL_DIR}/scripts/config" --file "${OUT_DIR}/.config" --module NFC_QTI_I2C || true
  else
    "${KERNEL_DIR}/scripts/config" --file "${OUT_DIR}/.config" --disable NFC_QTI_I2C || true
  fi

  # ---- Optional kernel modules (workflow_dispatch toggles) ----
  # The kernel branch (susfs-modules) ships these ON by default in defconfig;
  # here we turn off the ones the user unchecked before olddefconfig.
  ENABLE_REKERNEL="${ENABLE_REKERNEL:-true}"       # process/app detection (binder+signal hooks)
  ENABLE_DROIDSPACES="${ENABLE_DROIDSPACES:-true}" # IPC/namespaces/netfilter/tmpfs options
  ENABLE_BBGUARD="${ENABLE_BBGUARD:-true}"         # Baseband-guard telephony LSM
  ENABLE_BBRV3="${ENABLE_BBRV3:-true}"             # BBRv3 TCP congestion control (built-in code; toggle = default CC)

  local cfg="${OUT_DIR}/.config"
  local kc="${KERNEL_DIR}/scripts/config"

  if [[ "${ENABLE_REKERNEL}" == "true" ]]; then
    "${kc}" --file "${cfg}" --enable REKERNEL || true
  else
    "${kc}" --file "${cfg}" --disable REKERNEL || true
  fi

  if [[ "${ENABLE_DROIDSPACES}" == "true" ]]; then
    for sym in POSIX_MQUEUE IPC_NS PID_NS USER_NS DEVTMPFS \
               NETFILTER_XT_MATCH_ADDRTYPE IP_NF_TARGET_REJECT NETFILTER_XT_TARGET_LOG \
               NETFILTER_XT_MATCH_RECENT IP_SET IP_SET_HASH_IP IP_SET_HASH_NET NETFILTER_XT_SET \
               TMPFS_POSIX_ACL TMPFS_XATTR; do
      "${kc}" --file "${cfg}" --enable "${sym}" || true
    done
  else
    for sym in POSIX_MQUEUE IPC_NS PID_NS IP_SET IP_SET_HASH_IP IP_SET_HASH_NET \
               NETFILTER_XT_SET TMPFS_POSIX_ACL TMPFS_XATTR; do
      "${kc}" --file "${cfg}" --disable "${sym}" || true
    done
  fi

  if [[ "${ENABLE_BBGUARD}" == "true" ]]; then
    "${kc}" --file "${cfg}" --enable BBG || true
    "${kc}" --file "${cfg}" --set-str CONFIG_LSM "lockdown,yama,loadpin,safesetid,integrity,selinux,smack,tomoyo,apparmor,baseband_guard" || true
  else
    "${kc}" --file "${cfg}" --disable BBG || true
    # Restore MMI-baseline LSM list (no dangling "baseband_guard" in the string).
    "${kc}" --file "${cfg}" --set-str CONFIG_LSM "lockdown,yama,loadpin,safesetid,integrity,selinux,smack,tomoyo,apparmor" || true
  fi

  if [[ "${ENABLE_BBRV3}" == "true" ]]; then
    # BBRv3 code is compiled into tcp_bbr.c; the toggle selects it as default CC + fq pacing.
    "${kc}" --file "${cfg}" --enable TCP_CONG_BBR || true
    "${kc}" --file "${cfg}" --enable DEFAULT_BBR || true
    "${kc}" --file "${cfg}" --set-str DEFAULT_TCP_CONG bbr || true
    "${kc}" --file "${cfg}" --enable NET_SCH_FQ || true
    "${kc}" --file "${cfg}" --enable NET_SCH_DEFAULT || true
    "${kc}" --file "${cfg}" --enable DEFAULT_FQ || true
  else
    # MMI baseline: cubic default, no fq-as-default (built-in BBRv3 code stays unselected).
    "${kc}" --file "${cfg}" --set-str DEFAULT_TCP_CONG cubic || true
    "${kc}" --file "${cfg}" --disable DEFAULT_BBR || true
    "${kc}" --file "${cfg}" --disable NET_SCH_DEFAULT || true
    "${kc}" --file "${cfg}" --disable DEFAULT_FQ || true
  fi

  info "Module switches: ReKernel=${ENABLE_REKERNEL} DroidSpaces=${ENABLE_DROIDSPACES} BBGuard=${ENABLE_BBGUARD} BBRv3=${ENABLE_BBRV3}"

  stage "olddefconfig"
  info "olddefconfig (-j${JOBS})"
  mk "olddefconfig" -j"${JOBS}" -C "${KERNEL_DIR}" O="${OUT_DIR}" \
    "${common_make[@]}" \
    HOSTCFLAGS="${hostcflags}" HOSTLDFLAGS="${hostldflags}" \
    olddefconfig

  stage "headers_install"
  info "headers_install (-j${JOBS})"
  mk "headers_install" -j"${JOBS}" -C "${KERNEL_DIR}" O="${OUT_DIR}" \
    "${common_make[@]}" \
    HOSTCFLAGS="${hostcflags}" HOSTLDFLAGS="${hostldflags}" \
    headers_install

  stage "Image"
  info "Image (-j${JOBS})"
  mk "Image" -j"${JOBS}" -C "${KERNEL_DIR}" O="${OUT_DIR}" \
    "${common_make[@]}" \
    HOSTCFLAGS="${hostcflags}" HOSTLDFLAGS="${hostldflags}"

  popd >/dev/null

  local image="${OUT_DIR}/arch/arm64/boot/Image"
  [[ -f "${image}" ]] || die "Build failed: ${image} not found"
  info "Image size: $(du -h "${image}" | awk '{print $1}')"
  if [[ -f "${OUT_DIR}/.config" ]]; then
    grep -E 'CONFIG_NFC_QTI_I2C' "${OUT_DIR}/.config" || true
  fi
  cp -f "${image}" "${WORK_DIR}/release/Image"

  restore_nfc_config
  git -C "${KERNEL_DIR}" checkout HEAD -- \
    arch/arm64/configs/vendor/lahaina-qgki_defconfig 2>/dev/null || true
  trap - EXIT
  endlog
}

# ---------------------------------------------------------------------------
# Ensure boot_oem.img (local copy, ~/下载, or Release asset download)
# ---------------------------------------------------------------------------
ensure_boot_oem() {
  log "Ensure boot_oem.img"
  if [[ -f "${BOOT_OEM_IMG}" ]]; then
    info "Using existing ${BOOT_OEM_IMG} ($(du -h "${BOOT_OEM_IMG}" | awk '{print $1}'))"
    endlog
    return 0
  fi

  mkdir -p "$(dirname "${BOOT_OEM_IMG}")"

  if [[ -f "${HOME}/下载/boot_oem.img" ]]; then
    info "Copying ${HOME}/下载/boot_oem.img"
    cp -f "${HOME}/下载/boot_oem.img" "${BOOT_OEM_IMG}"
    endlog
    return 0
  fi

  local url="https://github.com/${BOOT_OEM_RELEASE_REPO}/releases/download/${BOOT_OEM_RELEASE_TAG}/${BOOT_OEM_ASSET_NAME}"
  if [[ -n "${GITHUB_PROXY:-}" ]]; then
    url="${GITHUB_PROXY%/}/${url}"
  fi
  info "Downloading ${url}"
  curl_get -o "${BOOT_OEM_IMG}.partial" "${url}"
  mv -f "${BOOT_OEM_IMG}.partial" "${BOOT_OEM_IMG}"
  [[ -f "${BOOT_OEM_IMG}" ]] || die "failed to download boot_oem.img"
  info "Downloaded ${BOOT_OEM_IMG} ($(du -h "${BOOT_OEM_IMG}" | awk '{print $1}'))"
  endlog
}

# ---------------------------------------------------------------------------
# 5-7) magiskboot unpack boot_oem.img -> replace kernel -> repack
# ---------------------------------------------------------------------------
setup_magiskboot() {
  log "Setup magiskboot"
  local magisk_dir="${TOOLCHAIN_DIR}/magisk"
  mkdir -p "${magisk_dir}"
  if [[ ! -x "${magisk_dir}/magiskboot" ]]; then
    for cand in \
      "${HOME}/下载/boot_unpack/tools/magiskboot" \
      "${HOME}/android/android_kernel_motorola_sm7325/.ci-toolchain/magisk/magiskboot"; do
      if [[ -x "${cand}" ]]; then
        cp -f "${cand}" "${magisk_dir}/magiskboot"
        chmod +x "${magisk_dir}/magiskboot"
        break
      fi
    done
  fi
  if [[ ! -x "${magisk_dir}/magiskboot" ]]; then
    local tag apk
    local magisk_api="https://api.github.com/repos/topjohnwu/Magisk/releases/latest"
    local magisk_base="https://github.com/topjohnwu/Magisk/releases/download"
    if [[ -n "${GITHUB_PROXY:-}" ]]; then
      magisk_api="${GITHUB_PROXY%/}/${magisk_api}"
      magisk_base="${GITHUB_PROXY%/}/${magisk_base}"
    fi
    tag="$(curl_get -fsS "${magisk_api}" | python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"])')"
    apk="${magisk_dir}/Magisk-${tag}.apk"
    curl_get -o "${apk}" "${magisk_base}/${tag}/Magisk-${tag}.apk"
    python3 - <<PY
import zipfile
apk="${apk}"
out="${magisk_dir}/magiskboot"
with zipfile.ZipFile(apk) as z:
    for name in ("lib/x86_64/libmagiskboot.so", "lib/x86/libmagiskboot.so"):
        if name in z.namelist():
            with z.open(name) as src, open(out, "wb") as dst:
                dst.write(src.read())
            break
    else:
        raise SystemExit("libmagiskboot.so not found in Magisk apk")
PY
    chmod +x "${magisk_dir}/magiskboot"
  fi
  export MAGISKBOOT="${magisk_dir}/magiskboot"
  info "magiskboot: ${MAGISKBOOT}"
  endlog
}

repack_boot() {
  log "Repack boot.img with custom kernel"
  [[ -f "${BOOT_OEM_IMG}" ]] || die "boot_oem.img not found: ${BOOT_OEM_IMG}"

  local unpack_dir="${WORK_DIR}/boot/unpack"
  rm -rf "${unpack_dir}"
  mkdir -p "${unpack_dir}"
  cp -f "${BOOT_OEM_IMG}" "${unpack_dir}/boot.img"
  pushd "${unpack_dir}" >/dev/null

  "${MAGISKBOOT}" unpack boot.img
  [[ -f kernel ]] || die "magiskboot did not produce 'kernel'"

  cp -f "${WORK_DIR}/release/Image" kernel
  "${MAGISKBOOT}" repack boot.img new-boot.img
  [[ -f new-boot.img ]] || die "magiskboot repack failed"

  RESUKISU_VERSION="${RESUKISU_VERSION:-$(cat "${WORK_DIR}/resukisu_version.txt")}"
  local safe_ver
  safe_ver="$(echo "${RESUKISU_VERSION}" | tr '/:' '--')"

  cp -f new-boot.img "${WORK_DIR}/release/boot_ksu.img"
  cp -f new-boot.img "${WORK_DIR}/release/boot.img"

  # boot_ksu + SUSFS version + enabled modules
  # e.g. boot_ksu-SUSFSv2.3-ReKernel-DroidSpaces-BBGuard-BBRv3.img
  local module_tag susfs_tag
  module_tag="$(build_module_tag)"
  susfs_tag="$(build_susfs_tag)"
  local out_name="boot_ksu${module_tag}-${susfs_tag}.img"
  cp -f new-boot.img "${WORK_DIR}/release/${out_name}"

  popd >/dev/null

  local build_id
  if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
    build_id="r${GITHUB_RUN_NUMBER}"
  else
    build_id="$(date -u +%Y%m%d%H%M%S)"
  fi

  case "${VARIANT}" in
    edge-s30) RELEASE_TAG="MMI-${KERNEL_VER_LABEL}-${ROM_ID}-ReSukiSU-EdgeS30-${susfs_tag}-${build_id}" ;;
    g200)     RELEASE_TAG="MMI-${KERNEL_VER_LABEL}-${ROM_ID}-ReSukiSU-G200-${susfs_tag}-${build_id}" ;;
  esac

  RESUKISU_DISPLAY="${RESUKISU_DISPLAY:-$(cat "${WORK_DIR}/resukisu_display.txt" 2>/dev/null || echo "${RESUKISU_VERSION}@ReSukiSU")}"
  RELEASE_NAME="${RELEASE_TITLE} [${susfs_tag}]"
  BOOT_ARTIFACT="${WORK_DIR}/release/boot_ksu.img"
  export RELEASE_TAG RELEASE_NAME BOOT_ARTIFACT VARIANT_SLUG DEVICE_TITLE KERNEL_VER_LABEL
  export SUSFS_VERSION KERNEL_BRANCH

  gh_env RELEASE_TAG "${RELEASE_TAG}"
  gh_env RELEASE_NAME "${RELEASE_NAME}"
  gh_env BOOT_ARTIFACT "${BOOT_ARTIFACT}"
  gh_env VARIANT_SLUG "${VARIANT_SLUG}"
  gh_env DEVICE_TITLE "${DEVICE_TITLE}"
  gh_env ROM_ID "${ROM_ID}"
  gh_env KERNEL_VER_LABEL "${KERNEL_VER_LABEL}"
  gh_env WORK_DIR "${WORK_DIR}"
  gh_env SUSFS_VERSION "${SUSFS_VERSION}"
  gh_env KERNEL_BRANCH "${KERNEL_BRANCH}"

  info "SUSFS version: ${SUSFS_VERSION} (kernel branch ${KERNEL_BRANCH})"
  info "Output: ${BOOT_ARTIFACT}"
  info "Release tag: ${RELEASE_TAG}"
  endlog
}

build_wlan_and_pack() {
  [[ "${BUILD_WLAN}" == "true" ]] || {
    info "BUILD_WLAN=false; skipping WiFi KSU module"
    return 0
  }
  log "Build WiFi modules (CRC/vermagic-matched) + KSU zip"
  local wlan_script pack_script
  wlan_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build_wlan_modules.sh"
  pack_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pack_wlan_ksu_module.sh"
  [[ -f "${wlan_script}" ]] || die "missing ${wlan_script}"
  [[ -f "${pack_script}" ]] || die "missing ${pack_script}"

  BUILD_ROOT="${BUILD_ROOT}" WORK_DIR="${WORK_DIR}" OUT_DIR="${OUT_DIR}" \
    WLAN_TAG="${WLAN_TAG}" JOBS="${JOBS}" \
    CLANG="${CLANG}" MAKE="${MAKE}" AARCH64_PREFIX="${AARCH64_PREFIX}" \
    CCACHE_CC="${CCACHE_CC:-}" \
    CCACHE_LD="${CCACHE_LD:-}" \
    LD_LLD="${LD_LLD}" LLVM_AR="${LLVM_AR}" LLVM_NM="${LLVM_NM}" \
    DTC_EXT="${DTC_EXT}" UFDT_EXT="${UFDT_EXT}" \
    bash "${wlan_script}"

  WLAN_OUT_DIR="${WLAN_OUT_DIR:-${WORK_DIR}/wlan-kos}"
  if [[ -f "${WORK_DIR}/wlan_out_dir.txt" ]]; then
    WLAN_OUT_DIR="$(cat "${WORK_DIR}/wlan_out_dir.txt")"
  fi

  BUILD_ROOT="${BUILD_ROOT}" WORK_DIR="${WORK_DIR}" \
    WLAN_OUT_DIR="${WLAN_OUT_DIR}" \
    KERNEL_VER_LABEL="${KERNEL_VER_LABEL}" \
    KERNEL_DIR="${KERNEL_DIR}" KERNEL_SRC="${KERNEL_DIR}" \
    bash "${pack_script}"

  export WLAN_OUT_DIR
  if [[ -f "${WORK_DIR}/wlan_ksu_zip.txt" ]]; then
    WLAN_KSU_ZIP="$(cat "${WORK_DIR}/wlan_ksu_zip.txt")"
    export WLAN_KSU_ZIP
    gh_env WLAN_KSU_ZIP "${WLAN_KSU_ZIP}"
  fi
  endlog
}

pack_anykernel3() {
  log "Pack AnyKernel3 zip (kernel + vendor WiFi kos)"
  local pack_script
  pack_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pack_anykernel3.sh"
  [[ -f "${pack_script}" ]] || die "missing ${pack_script}"
  BUILD_ROOT="${BUILD_ROOT}" WORK_DIR="${WORK_DIR}" DEVICE="${DEVICE}" \
    DEVICE_TITLE="${DEVICE_TITLE}" \
    VARIANT_SLUG="${VARIANT_SLUG}" \
    RESUKISU_VERSION="${RESUKISU_VERSION:-}" \
    RESUKISU_DISPLAY="${RESUKISU_DISPLAY:-}" \
    ROM_ID="${ROM_ID}" \
    KERNEL_VER_LABEL="${KERNEL_VER_LABEL}" \
    WLAN_OUT_DIR="${WLAN_OUT_DIR:-${WORK_DIR}/wlan-kos}" \
    GITHUB_PROXY="${GITHUB_PROXY:-}" \
    ENABLE_SUSFS="${ENABLE_SUSFS:-true}" \
    SUSFS_VERSION="${SUSFS_VERSION:-v2.2}" \
    ENABLE_REKERNEL="${ENABLE_REKERNEL:-true}" \
    ENABLE_DROIDSPACES="${ENABLE_DROIDSPACES:-true}" \
    ENABLE_BBGUARD="${ENABLE_BBGUARD:-true}" \
    ENABLE_BBRV3="${ENABLE_BBRV3:-true}" \
    KERNEL_IMAGE="${WORK_DIR}/release/Image" \
    bash "${pack_script}"
  endlog
}

write_release_notes() {
  RESUKISU_VERSION="${RESUKISU_VERSION:-$(cat "${WORK_DIR}/resukisu_version.txt")}"
  RESUKISU_DISPLAY="${RESUKISU_DISPLAY:-$(cat "${WORK_DIR}/resukisu_display.txt" 2>/dev/null || echo "${RESUKISU_VERSION}@ReSukiSU")}"
  AK3_COMMIT="${AK3_COMMIT:-$(cat "${WORK_DIR}/ak3_commit.txt" 2>/dev/null || echo unknown)}"
  local nfc_note="disabled (default)"
  [[ "${ENABLE_NFC}" == "true" ]] && nfc_note="enabled (CONFIG_NFC_QTI_I2C=m)"

  # Module on/off display for the release page
  local mod_rekernel mod_droidspaces mod_bbguard mod_bbrv3
  [[ "${ENABLE_REKERNEL:-true}" == "true" ]]    && mod_rekernel="✅ 勾选 ON"    || mod_rekernel="❌ 未勾选 OFF"
  [[ "${ENABLE_DROIDSPACES:-true}" == "true" ]] && mod_droidspaces="✅ 勾选 ON" || mod_droidspaces="❌ 未勾选 OFF"
  [[ "${ENABLE_BBGUARD:-true}" == "true" ]]     && mod_bbguard="✅ 勾选 ON"     || mod_bbguard="❌ 未勾选 OFF"
  [[ "${ENABLE_BBRV3:-true}" == "true" ]]       && mod_bbrv3="✅ 勾选 ON"       || mod_bbrv3="❌ 未勾选 OFF"

  # SUSFS version label + stability note
  local susfs_label susfs_note
  case "${SUSFS_VERSION:-v2.2}" in
    v2.3)
      susfs_label="v2.3.0"
      susfs_note="较新（kstat/STATX 重构 + 更完整的 hook 覆盖）。本构建已通过编译与开机验证；**如遇到任何 bug，可自行选择 SUSFS_VERSION=v2.2 重新编译回退到稳定版**。"
      ;;
    *)
      susfs_label="v2.2.0"
      susfs_note="长期验证的**稳定**版本，推荐日常使用。"
      ;;
  esac

  cat > "${WORK_DIR}/release/RELEASE_NOTES.md" <<EOF
## SUSFS 版本 (SUSFS version)

本次构建使用 **SUSFS ${susfs_label}**（内核分支 \`${KERNEL_BRANCH}\`）。

${susfs_note}

## 本次构建的模块选择 (Module options in this build)

| 模块 | 状态 |
|---|---|
| **SUSFS** ${susfs_label} (核心文件系统隐藏，恒开) | ✅ 始终开启 |
| **Re:Kernel** v8.5 (进程/应用检测, binder+signal hook) | ${mod_rekernel} |
| **DroidSpaces** (IPC/PID 命名空间, netfilter/IP_SET, tmpfs ACL) | ${mod_droidspaces} |
| **BBGuard** (Baseband-guard 基带防格机 LSM) | ${mod_bbguard} |
| **BBRv3** (TCP 拥塞控制升级 + fq pacing) | ${mod_bbrv3} |

## HOW TO USE

\`\`\`
# Press the volume down and power buttons to enter FASTBOOT mode, then enter the command to enter Fastboot mode.
# 按音量下和开机键进入 FASTBOOT 模式，输入命令，进入 Fastbootd
fastboot reboot fastboot

# Flash boot_ksu.img
# 刷写 boot_ksu.img
fastboot flash boot boot_ksu.img

# If the device fails to boot after flashing, you will need to format the Data.
# 如果刷写后无法开机，则需要格式化 Data
fastboot -w
\`\`\`

### AnyKernel3 (any ROM)

Sideload or flash \`AnyKernel3-*.zip\` in a custom recovery, or use a kernel flasher app.
This replaces the kernel **and** vendor WiFi \`qca_cld3_*.ko\` (\`do.modules=1\`). No KernelSU WiFi module install is needed.

## Notes
- Device: ${DEVICE_TITLE}
- Kernel: **${KERNEL_VER_LABEL}**
- MYUI: 4.0
- Android 12
- ROM: ${ROM_ID}
- SUSFS: ${susfs_label} (kernel branch \`${KERNEL_BRANCH}\`)
- ReSukiSU: ${RESUKISU_DISPLAY}
- NFC: ${nfc_note}
- WiFi: CRC/vermagic-matched \`qca_cld3_*.ko\` (built with this Image)
- AnyKernel3: [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3) \`${AK3_COMMIT}\` (\`do.modules=1\`, pushes kos to \`/vendor/lib/modules/\`)

## Assets
- \`boot_ksu.img\` — OEM boot.img with replaced ReSukiSU kernel
- \`Image\` — raw ARM64 kernel Image
- \`AK3-*.zip\` — flashable zip (kernel + vendor WiFi kos; no KernelSU WiFi module needed)
- \`wlan_crc_match_*-ksu-*.zip\` — optional KernelSU/Magisk overlay **only if** you flash \`boot_ksu.img\` via fastboot (does not replace vendor kos)

## SUSFS 版本回退 (Falling back to SUSFS v2.2)

SUSFS v2.2 与 v2.3 是**两条独立的内核分支**，产物互不兼容，按需选择：

| SUSFS 版本 | 内核分支 | 稳定性 |
|---|---|---|
| **v2.2**（默认） | \`5.4.302-s3rxc32.33-8-25-susfs-modules\` | 长期验证，稳定 |
| **v2.3** | \`5.4.302-s3rxc32.33-8-25-susfs-modules-v2.3-astide\` | 较新；有 bug 可回退 v2.2 |

触发 workflow 时把 \`susfs_version\` 选为 \`v2.2\` 即可回退；本地构建设 \`SUSFS_VERSION=v2.2\`。

> Built automatically from \`android_kernel_motorola_xpeng_build\` (\`5.4.302-s3rxc32.33-8-25-ReSukiSU\`) using kernel sources from [android_kernel_motorola_xpeng @ ${KERNEL_BRANCH}](https://github.com/paulcbfly/android_kernel_motorola_xpeng/tree/${KERNEL_BRANCH}) with ReSukiSU + SUSFS ${SUSFS_VERSION} + live-built WiFi kos + latest AnyKernel3 upstream.
EOF
  gh_env RELEASE_NOTES "${WORK_DIR}/release/RELEASE_NOTES.md"
  info "Release notes written"
}

# ---------------------------------------------------------------------------
# ccache-ECS hit/miss report (best-effort; never fails the build)
# ---------------------------------------------------------------------------
ccache_report() {
  [[ "${ENABLE_CCACHE:-true}" == "true" ]] || return 0
  local ccache_bin="${BUILD_ROOT}/scripts/ci/ccache-ecs/ccache-x86-64"
  [[ -x "${ccache_bin}" ]] || return 0
  log "ccache-ECS statistics"
  "${ccache_bin}" -s 2>/dev/null || true
  # Emit a compact summary into the job summary when running under Actions.
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    local stats
    stats="$("${ccache_bin}" -s 2>/dev/null || true)"
    {
      echo "### ccache-ECS stats"
      echo '```'
      printf '%s\n' "${stats}"
      echo '```'
    } >> "${GITHUB_STEP_SUMMARY}" 2>/dev/null || true
  fi
  endlog
}

main() {
  info "Variant=${VARIANT} Device=${DEVICE_TITLE} NFC=${ENABLE_NFC}"
  info "Kernel branch=${KERNEL_BRANCH} label=${KERNEL_VER_LABEL} ROM_ID=${ROM_ID}"
  info "BUILD_ROOT=${BUILD_ROOT}"
  fetch_kernel
  update_resukisu
  setup_toolchain
  setup_ccache
  if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
    build_kernel
    ccache_report
  else
    [[ -f "${WORK_DIR}/release/Image" || -f "${OUT_DIR}/arch/arm64/boot/Image" ]] \
      || die "SKIP_BUILD=true but Image not found"
    mkdir -p "${WORK_DIR}/release"
    if [[ ! -f "${WORK_DIR}/release/Image" ]]; then
      cp -f "${OUT_DIR}/arch/arm64/boot/Image" "${WORK_DIR}/release/Image"
    fi
    info "Skipping kernel build; using existing Image"
  fi
  # WiFi kos must track this Image's Module.symvers / vermagic
  build_wlan_and_pack
  ccache_report
  ensure_boot_oem
  setup_magiskboot
  repack_boot
  pack_anykernel3
  if [[ -n "${AK3_COMMIT:-}" ]]; then
    printf '%s\n' "${AK3_COMMIT}" > "${WORK_DIR}/ak3_commit.txt"
  fi
  write_release_notes
  info "Done. Artifacts in ${WORK_DIR}/release/"
  ls -lh "${WORK_DIR}/release/"
}

main "$@"
