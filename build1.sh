#!/bin/bash
export all_proxy=socks5://192.168.2.25:10810
set -e # Exit immediately if a command exits with a non-zero status.

# =================================================================
#                 USER CONFIGURATION
# =================================================================
# Set your desired build options here. These correspond to the
# 'inputs' in the original GitHub Actions workflow.
# -----------------------------------------------------------------

# CPU (sm8650, sm8550, sm8450, sm8475, sm7675, sm7550, sm6375)
CPU='sm8650'

# Phone Model (e.g., oneplus_12, oneplus_11, etc.)
FEIL='oneplus_12'

# Processor Codename (pineapple, kalama, waipio, crow, blair)
CPUD='pineapple'

# Kernel Android Version (android14, android13, android12)
ANDROID_VERSION='android14'

# Kernel Version (6.1, 5.15, 5.10)
KERNEL_VERSION='6.1'

# Enable KPM (On, Off)
KPM='Off'

# Enable lz4kd (On, Off). If 'Off' and KERNEL_VERSION is 6.1, lz4+zstd will be used.
LZ4KD='Off'

# Enable BBR TCP algorithm (On, Off)
BBR='Off'

# Add proxy performance optimization (On, Off)
PROXY='On'

# =================================----------------================
#                 SCRIPT START
# =================================================================
# Do not edit below this line unless you know what you are doing.

# --- Environment Setup ---
WORKSPACE_DIR="$PWD/workspace"
CCACHE_DIR="$HOME/.ccache_local_build_${FEIL}"
export CCACHE_DIR
export CCACHE_COMPILERCHECK="%compiler% -dumpmachine; %compiler% -dumpversion"
export CCACHE_NOHASHDIR="true"
export CCACHE_HARDLINK="true"
export CCACHE_MAXSIZE="15G" # Increased for local builds

# --- Function to log messages ---
log() {
    echo "================================================================"
    echo ">> $1"
    echo "================================================================"
}

# --- Create workspace ---
mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

log "⚙️ Setting up Environment"
echo "🔧 Setting up device-specific cache directory..."
mkdir -p "$CCACHE_DIR"
echo "✅ Cache directory is set to: $CCACHE_DIR"

log "🔐 Configuring Git"
git config --global user.name "local-builder"
git config --global user.email "builder@localhost"
echo "✅ Git configured"

log "💾 Initializing ccache"
if command -v ccache >/dev/null 2>&1; then
    ccache -M "$CCACHE_MAXSIZE"
    ccache -z
else
    log "⚠️ ccache command not found. Please install it."
    exit 1
fi
echo "✅ ccache setup complete"

log "📥 Installing Repo Tool"
if [ ! -f "/usr/local/bin/repo" ]; then
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo > ~/repo
    chmod a+x ~/repo
    sudo mv ~/repo /usr/local/bin/repo
    echo "✅ repo tool installed"
else
    echo "✅ repo tool already installed"
fi

log "⬇️ Cloning Kernel Source"
rm -rf kernel_workspace && mkdir -p kernel_workspace && cd kernel_workspace
repo init -u https://github.com/Xiaomichael/kernel_manifest.git -b refs/heads/oneplus/"$CPU" -m "${FEIL}".xml --depth=1
log "🔄 Syncing repositories (using $(nproc --all) threads)..."
repo sync -c -j$(nproc --all) --no-tags --no-clone-bundle --force-sync

rm kernel_platform/common/android/abi_gki_protected_exports_* || echo "No protected exports!"
rm kernel_platform/msm-kernel/android/abi_gki_protected_exports_* || echo "No protected exports!"

log "✏️ Modifying version string..."
sed -i 's/ -dirty//g' kernel_platform/common/scripts/setlocalversion
sed -i 's/ -dirty//g' kernel_platform/msm-kernel/scripts/setlocalversion
sed -i 's/ -dirty//g' kernel_platform/external/dtc/scripts/setlocalversion
sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' kernel_platform/common/scripts/setlocalversion
sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' kernel_platform/msm-kernel/scripts/setlocalversion
sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' kernel_platform/external/dtc/scripts/setlocalversion
sed -i '$s|echo "\$res"|echo "-oki-xiaoxiaow"|' kernel_platform/common/scripts/setlocalversion
sed -i '$s|echo "\$res"|echo "-oki-xiaoxiaow"|' kernel_platform/msm-kernel/scripts/setlocalversion
sed -i '$s|echo "\$res"|echo "-oki-xiaoxiaow"|' kernel_platform/external/dtc/scripts/setlocalversion
echo "✅ Kernel source ready"
cd .. # Back to workspace root

log "⚡ Setting up SukiSU Ultra"
mkdir -p kernel_workspace/kernel_platform
cd kernel_workspace/kernel_platform
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/susfs-main/kernel/setup.sh" | bash -s susfs-main
cd ./KernelSU
curl -L -o setup.bin https://github.com/Xiaomichael/OnePlus-Actions/raw/Build/script/setup.bin
chmod +x setup.bin
if [ ! -f "kernel/Makefile" ]; then
    echo "❌ ERROR: kernel/Makefile is missing!"
    exit 1
fi
./setup.bin
cd ../.. # Back to workspace root
echo "✅ SukiSU Ultra configured"

log "🔧 Setting up SUSFS and Applying Patches"
cd $WORKSPACE_DIR/kernel_workspace
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-"$ANDROID_VERSION"-"$KERNEL_VERSION"
git clone https://github.com/Xiaomichael/kernel_patches.git
git clone https://github.com/ShirkNeko/SukiSU_patch.git
git clone https://github.com/Lama3L9R/sukisu-quick-setup.git

cd $WORKSPACE_DIR/kernel_workspace/kernel_platform
log "📝 Copying patch files..."
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-"$ANDROID_VERSION"-"$KERNEL_VERSION".patch ./common/
cp ../kernel_patches/next/syscall_hooks.patch ./common/
cp ../susfs4ksu/kernel_patches/fs/* ./common/fs/
cp ../susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/

if [ "$LZ4KD" = "Off" ] && [ "$KERNEL_VERSION" = "6.1" ]; then
    cp ../kernel_patches/zram/001-lz4.patch ./common/
    cp ../kernel_patches/zram/lz4armv8.S ./common/lib
    cp ../kernel_patches/zram/002-zstd.patch ./common/
fi

if [ "$LZ4KD" == "On" ]; then
    cp -r ../SukiSU_patch/other/zram/lz4k/include/linux/* ./common/include/linux
    cp -r ../SukiSU_patch/other/zram/lz4k/lib/* ./common/lib
    cp -r ../SukiSU_patch/other/zram/lz4k/crypto/* ./common/crypto
    cp -r ../SukiSU_patch/other/zram/lz4k_oplus ./common/lib/
fi

log "🔧 Applying patches..."
cd ./common
patch -p1 < 50_add_susfs_in_gki-"$ANDROID_VERSION"-"$KERNEL_VERSION".patch || true
cp ../../kernel_patches/69_hide_stuff.patch ./
patch -p1 -F 3 < 69_hide_stuff.patch || true
patch -p1 -F 3 < syscall_hooks.patch || true

if [ "$LZ4KD" = "Off" ] && [ "$KERNEL_VERSION" = "6.1" ]; then
    log "📦 Applying lz4+zstd patches..."
    patch -p1 < 001-lz4.patch || true
    patch -p1 < 002-zstd.patch || true
fi

if [ "$LZ4KD" == "On" ]; then
    log "🚀 Applying lz4kd patches..."
    cp "../../SukiSU_patch/other/zram/zram_patch/${KERNEL_VERSION}/lz4kd.patch" ./
    patch -p1 -F 3 < lz4kd.patch || true
    cp "../../SukiSU_patch/other/zram/zram_patch/${KERNEL_VERSION}/lz4k_oplus.patch" ./
    patch -p1 -F 3 < lz4k_oplus.patch || true
fi
cd ../.. # Back to workspace root
echo "✅ Patches applied"

log "⚙️ Configuring Kernel Options"
cd $WORKSPACE_DIR/kernel_workspace/kernel_platform
DEFCONFIG_PATH="./common/arch/arm64/configs/gki_defconfig"

# Add KSU & SUSFS configurations
{
    echo "CONFIG_KSU=y"
    if [ "$KPM" == "On" ]; then echo "CONFIG_KPM=y"; fi
    echo "CONFIG_KSU_SUSFS_SUS_SU=n"
    echo "CONFIG_KSU_MANUAL_HOOK=y"
    echo "CONFIG_KSU_SUSFS=y"
    echo "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y"
    echo "CONFIG_KSU_SUSFS_SUS_PATH=y"
    echo "CONFIG_KSU_SUSFS_SUS_MOUNT=y"
    echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y"
    echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y"
    echo "CONFIG_KSU_SUSFS_SUS_KSTAT=y"
    echo "CONFIG_KSU_SUSFS_SUS_OVERLAYFS=n"
    echo "CONFIG_KSU_SUSFS_TRY_UMOUNT=y"
    echo "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y"
    echo "CONFIG_KSU_SUSFS_SPOOF_UNAME=y"
    echo "CONFIG_KSU_SUSFS_ENABLE_LOG=y"
    echo "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y"
    echo "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y"
    echo "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y"
} >> "$DEFCONFIG_PATH"

if [ "$BBR" == "On" ]; then
    log "🌐 Enabling BBR network algorithm..."
    {
        echo "CONFIG_TCP_CONG_ADVANCED=y"
        echo "CONFIG_TCP_CONG_BBR=y"
        echo "CONFIG_NET_SCH_FQ=y"
        echo "CONFIG_TCP_CONG_BIC=n"
        echo "CONFIG_TCP_CONG_WESTWOOD=n"
        echo "CONFIG_TCP_CONG_HTCP=n"
    } >> "$DEFCONFIG_PATH"
fi

if [ "$LZ4KD" == "On" ]; then
    log "📦 Enabling lz4kd compression..."
    {
        echo "CONFIG_CRYPTO_LZ4KD=y"
        echo "CONFIG_CRYPTO_LZ4K_OPLUS=y"
        echo "CONFIG_ZRAM_WRITEBACK=y"
    } >> "$DEFCONFIG_PATH"
fi

if [ "$PROXY" == "On" ]; then
    log "🔌 Enabling proxy features..."
    {
        echo "CONFIG_BPF_STREAM_PARSER=y"
        echo "CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y"
        echo "CONFIG_NETFILTER_XT_SET=y"
        echo "CONFIG_IP_SET=y"
        echo "CONFIG_IP_SET_MAX=65534"
        echo "CONFIG_IP_SET_BITMAP_IP=y"
        echo "CONFIG_IP_SET_BITMAP_IPMAC=y"
        echo "CONFIG_IP_SET_BITMAP_PORT=y"
        echo "CONFIG_IP_SET_HASH_IP=y"
        echo "CONFIG_IP_SET_HASH_IPMARK=y"
        echo "CONFIG_IP_SET_HASH_IPPORT=y"
        echo "CONFIG_IP_SET_HASH_IPPORTIP=y"
        echo "CONFIG_IP_SET_HASH_IPPORTNET=y"
        echo "CONFIG_IP_SET_HASH_IPMAC=y"
        echo "CONFIG_IP_SET_HASH_MAC=y"
        echo "CONFIG_IP_SET_HASH_NETPORTNET=y"
        echo "CONFIG_IP_SET_HASH_NET=y"
        echo "CONFIG_IP_SET_HASH_NETNET=y"
        echo "CONFIG_IP_SET_HASH_NETPORT=y"
        echo "CONFIG_IP_SET_HASH_NETIFACE=y"
        echo "CONFIG_IP_SET_LIST_SET=y"
        echo "CONFIG_IP6_NF_NAT=y"
        echo "CONFIG_IP6_NF_TARGET_MASQUERADE=y"
    } >> "$DEFCONFIG_PATH"
fi

if [ "$KERNEL_VERSION" == "6.1" ]; then
    log "📦 Adding O2 optimization for 6.1 kernel"
    echo "CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y" >> "$DEFCONFIG_PATH"
fi

if [ "$KERNEL_VERSION" = "5.10" ] || [ "$KERNEL_VERSION" = "5.15" ]; then
    log "📦 Configuring LTO for 5.10/5.15 kernels..."
    sed -i 's/^CONFIG_LTO=n/CONFIG_LTO=y/' "$DEFCONFIG_PATH"
    sed -i 's/^CONFIG_LTO_CLANG_FULL=y/CONFIG_LTO_CLANG_THIN=y/' "$DEFCONFIG_PATH"
    sed -i 's/^CONFIG_LTO_CLANG_NONE=y/CONFIG_LTO_CLANG_THIN=y/' "$DEFCONFIG_PATH"
    grep -q '^CONFIG_LTO_CLANG_THIN=y' "$DEFCONFIG_PATH" || echo 'CONFIG_LTO_CLANG_THIN=y' >> "$DEFCONFIG_PATH"
fi

sed -i 's/check_defconfig//' ./common/build.config.gki
echo "✅ Kernel configuration updated"

log "🔨 Building Kernel"
cd common
export KBUILD_BUILD_TIMESTAMP="Wed May 29 07:25:40 UTC 2025"
export KBUILD_BUILD_VERSION=1
export PATH="/usr/lib/ccache:$PATH"

if [ "$KERNEL_VERSION" == "6.1" ]; then
    export PATH="$WORKSPACE_DIR/kernel_workspace/kernel_platform/prebuilts/clang/host/linux-x86/clang-r487747c/bin:$PATH"
    make -j$(nproc --all) LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC="ccache clang" RUSTC=../../prebuilts/rust/linux-x86/1.73.0b/bin/rustc PAHOLE=../../prebuilts/kernel-build-tools/linux-x86/bin/pahole LD=ld.lld HOSTLD=ld.lld O=out KCFLAGS+=-O2 gki_defconfig all
elif [ "$KERNEL_VERSION" == "5.15" ]; then
    export PATH="$WORKSPACE_DIR/kernel_workspace/kernel_platform/prebuilts/clang/host/linux-x86/clang-r450784e/bin:$PATH"
    make -j$(nproc --all) LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC="ccache clang" RUSTC=../../prebuilts/rust/linux-x86/1.73.0b/bin/rustc PAHOLE=../../prebuilts/kernel-build-tools/linux-x86/bin/pahole LD=ld.lld HOSTLD=ld.lld O=out gki_defconfig all
elif [ "$KERNEL_VERSION" == "5.10" ]; then
    export PATH="$WORKSPACE_DIR/kernel_workspace/kernel_platform/prebuilts-master/clang/host/linux-x86/clang-r416183b/bin:$PATH"
    make -j$(nproc --all) LLVM_IAS=1 LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC="ccache clang" RUSTC=../../prebuilts/rust/linux-x86/1.73.0b/bin/rustc PAHOLE=../../prebuilts/kernel-build-tools/linux-x86/bin/pahole LD=ld.lld HOSTLD=ld.lld O=out gki_defconfig all
fi
cd ../../.. # Back to workspace root
ccache -s
echo "✅ Kernel build complete"

log "📦 Packaging Kernel"
git clone https://github.com/Xiaomichael/AnyKernel3 --depth=1
IMAGE_PATH=$(find "$WORKSPACE_DIR/kernel_workspace/kernel_platform/common/out/" -name "Image" | head -n 1)

if [ -f "$IMAGE_PATH" ]; then
    cp "$IMAGE_PATH" ./AnyKernel3/Image
else
    echo "❌ ERROR: Could not find compiled kernel Image!"
    exit 1
fi

if [ "$KPM" == 'On' ]; then
    log "🧩 Patching Kernel Image with KPM"
    cd kernel_workspace/kernel_platform/out/msm-kernel-"$CPUD"-gki/dist
    curl -LO https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/0.12.0/patch_linux
    chmod +x patch_linux
    ./patch_linux
    rm -f Image
    mv oImage Image
    cp Image "$WORKSPACE_DIR/AnyKernel3/Image"
    cd ../../../../../ # Back to workspace root
    echo "✅ KPM patch applied"
fi

log "🧠 Setting Artifact Name"
if [ "$LZ4KD" = "On" ]; then
    ARTIFACT_NAME="AnyKernel3_SukiSU_Ultra_lz4kd_${FEIL}"
elif [ "$KERNEL_VERSION" = "6.1" ]; then
    ARTIFACT_NAME="AnyKernel3_SukiSU_Ultra_lz4_zstd_${FEIL}"
else
    ARTIFACT_NAME="AnyKernel3_SukiSU_Ultra_${FEIL}"
fi
echo "Artifact name: ${ARTIFACT_NAME}"

log "📤 Saving Artifacts"
mkdir -p "$WORKSPACE_DIR/artifacts"
cd AnyKernel3
zip -r9 "../artifacts/${ARTIFACT_NAME}.zip" ./*
cd ..
if [ "$LZ4KD" == 'On' ]; then
    ZRAM_KO_PATH=$(find "$WORKSPACE_DIR/kernel_workspace/kernel_platform/common/out/" -name "zram.ko" | head -n 1)
    if [ -f "$ZRAM_KO_PATH" ]; then
        cp "$ZRAM_KO_PATH" "$WORKSPACE_DIR/artifacts/zram.ko"
        echo "✅ zram.ko saved to artifacts."
    else
        echo "⚠️ zram.ko not found!"
    fi
fi
echo "✅ All artifacts saved in: $WORKSPACE_DIR/artifacts"

log "🎉 Build process finished successfully!"
