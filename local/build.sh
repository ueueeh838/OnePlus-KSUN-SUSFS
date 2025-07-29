#!/bin/bash
export all_proxy=socks5://192.168.2.150:10810/

# ========== 参数设置 ==========
CPU=${1:-sm8650}
FEIL=${2:-oneplus_12}
CPUD=${3:-pineapple}
ANDROID_VERSION=${4:-android14}
KERNEL_VERSION=${5:-6.1}
KPM=${6:-Off}
lz4kd=${7:-Off}
bbr=${8:-Off}
proxy=${9:-On}

# ========== 环境变量配置 ==========
export CCACHE_COMPILERCHECK="%compiler% -dumpmachine; %compiler% -dumpversion"
export CCACHE_NOHASHDIR="true"
export CCACHE_HARDLINK="true"
export CCACHE_MAXSIZE=8G
export CCACHE_DIR="$HOME/.ccache_${FEIL}"

# ========== 工作目录设置 ==========
WORK_DIR="$HOME/kernel_build"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ========== 初始化步骤 ==========
echo "🚀 初始化构建环境..."

# 配置Git
git config --global user.name "build"
git config --global user.email "2210077278@qq.com"

# 安装依赖
echo "📦 安装必要依赖..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git curl ccache python3 \
    build-essential flex bison libssl-dev \
    libncurses-dev liblz4-tool zlib1g-dev \
    libxml2-utils rsync unzip libelf-dev \
    python3-pip

# 初始化ccache
if command -v ccache >/dev/null 2>&1; then
    mkdir -p "$CCACHE_DIR"
    ccache -M "$CCACHE_MAXSIZE"
    ccache -z
    echo "💾 ccache 已初始化"
else
    echo "⚠️ 未找到ccache，建议安装以加速编译"
fi

# 安装repo工具
if ! command -v repo >/dev/null 2>&1; then
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo > ~/repo
    chmod a+x ~/repo
    sudo mv ~/repo /usr/local/bin/repo
fi

# ========== 克隆源码 ==========
echo "⬇️ 克隆内核源码..."
rm -rf kernel_workspace
mkdir -p kernel_workspace
cd kernel_workspace
repo init -u https://github.com/Xiaomichael/kernel_manifest.git \
    -b refs/heads/oneplus/${CPU} -m ${FEIL}.xml --depth=1
repo sync -c -j$(nproc --all) --no-tags --no-clone-bundle --force-sync

# ========== 配置内核 ==========
echo "⚙️ 配置内核..."
curl -L -o kernel_setup.bin https://github.com/Xiaomichael/OnePlus-Actions/raw/Build/script/kernel_setup.bin
chmod +x kernel_setup.bin
./kernel_setup.bin

# 配置SukiSU Ultra
mkdir -p kernel_platform
cd kernel_platform
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/susfs-main/kernel/setup.sh" | bash -s susfs-main

cd KernelSU
curl -L -o sukisu_setup.bin https://github.com/Xiaomichael/OnePlus-Actions/raw/Build/script/sukisu_setup.bin
chmod +x sukisu_setup.bin
[ -f "kernel/Makefile" ] || { echo "❌ 错误：缺少kernel/Makefile"; exit 1; }
./sukisu_setup.bin
cd ../..

# ========== SUSFS补丁 ==========
cd kernel_workspace
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-${ANDROID_VERSION}-${KERNEL_VERSION}
git clone https://github.com/Xiaomichael/kernel_patches.git
git clone https://github.com/ShirkNeko/SukiSU_patch.git

# 应用补丁
cd kernel_platform
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch ./common/
cp ../kernel_patches/next/syscall_hooks.patch ./common/
cp -r ../susfs4ksu/kernel_patches/fs/* ./common/fs/
cp -r ../susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/

# lz4kd相关补丁
if [ "$lz4kd" = "Off" ] && [ "$KERNEL_VERSION" = "6.1" ]; then
    cp ../kernel_patches/zram/001-lz4.patch ./common/
    cp ../kernel_patches/zram/lz4armv8.S ./common/lib
    cp ../kernel_patches/zram/002-zstd.patch ./common/
fi

if [ "$lz4kd" = "On" ]; then
    cp -r ../SukiSU_patch/other/zram/lz4k/include/linux/* ./common/include/linux
    cp -r ../SukiSU_patch/other/zram/lz4k/lib/* ./common/lib
    cp -r ../SukiSU_patch/other/zram/lz4k/crypto/* ./common/crypto
    cp -r ../SukiSU_patch/other/zram/lz4k_oplus ./common/lib/
fi

# ========== 配置内核选项 ==========
DEFCONFIG=kernel_workspace/kernel_platform/common/arch/arm64/configs/gki_defconfig

# 基础配置
{
    echo "CONFIG_KSU=y"
    [ "$KPM" = "On" ] && echo "CONFIG_KPM=y"
    echo "CONFIG_KSU_SUSFS_SUS_SU=n"
    echo "CONFIG_KSU_MANUAL_HOOK=y"
    echo "CONFIG_KSU_SUSFS=y"
    # ...其他SUSFS配置...
} >> "$DEFCONFIG"

# BBR配置
if [ "$bbr" = "On" ]; then
    {
        echo "CONFIG_TCP_CONG_ADVANCED=y"
        echo "CONFIG_TCP_CONG_BBR=y"
        echo "CONFIG_NET_SCH_FQ=y"
        echo "CONFIG_TCP_CONG_BIC=n"
        echo "CONFIG_TCP_CONG_WESTWOOD=n"
        echo "CONFIG_TCP_CONG_HTCP=n"
    } >> "$DEFCONFIG"
fi

# LZ4KD配置
if [ "$lz4kd" = "On" ]; then
    {
        echo "CONFIG_CRYPTO_LZ4KD=y"
        echo "CONFIG_CRYPTO_LZ4K_OPLUS=y"
        echo "CONFIG_ZRAM_WRITEBACK=y"
    } >> "$DEFCONFIG"
fi

# ========== 编译内核 ==========
echo "🔨 开始编译内核..."
cd kernel_workspace/kernel_platform/common

case "$KERNEL_VERSION" in
    "6.1")
        export PATH="$PWD/../prebuilts/clang/host/linux-x86/clang-r487747c/bin:$PATH"
        make -j$(nproc --all) LLVM=1 ARCH=arm64 \
            CROSS_COMPILE=aarch64-linux-gnu- \
            CC="ccache clang" \
            RUSTC=../../prebuilts/rust/linux-x86/1.73.0b/bin/rustc \
            PAHOLE=../../prebuilts/kernel-build-tools/linux-x86/bin/pahole \
            LD=ld.lld HOSTLD=ld.lld O=out KCFLAGS+=-O2 \
            gki_defconfig all
        ;;
    "5.15")
        export PATH="$PWD/../prebuilts/clang/host/linux-x86/clang-r450784e/bin:$PATH"
        make -j$(nproc --all) LLVM=1 ARCH=arm64 \
            CROSS_COMPILE=aarch64-linux-gnu- \
            CC="ccache clang" \
            RUSTC=../../prebuilts/rust/linux-x86/1.73.0b/bin/rustc \
            PAHOLE=../../prebuilts/kernel-build-tools/linux-x86/bin/pahole \
            LD=ld.lld HOSTLD=ld.lld O=out \
            gki_defconfig all
        ;;
    "5.10")
        export PATH="$PWD/../prebuilts-master/clang/host/linux-x86/clang-r416183b/bin:$PATH"
        make -j$(nproc --all) LLVM_IAS=1 LLVM=1 ARCH=arm64 \
            CROSS_COMPILE=aarch64-linux-gnu- \
            CC="ccache clang" \
            RUSTC=../../prebuilts/rust/linux-x86/1.73.0b/bin/rustc \
            PAHOLE=../../prebuilts/kernel-build-tools/linux-x86/bin/pahole \
            LD=ld.lld HOSTLD=ld.lld O=out \
            gki_defconfig all
        ;;
esac

# 显示ccache统计
ccache -s

# ========== 打包内核 ==========
echo "📦 打包内核..."
cd "$WORK_DIR"
rm -rf AnyKernel3
git clone --depth=1 https://github.com/Xiaomichael/AnyKernel3

# 拷贝编译产物
IMAGE_PATH=$(find kernel_workspace/kernel_platform/common/out/ -name "Image" | head -n 1)
if [ -n "$IMAGE_PATH" ] && [ -f "$IMAGE_PATH" ]; then
    cp "$IMAGE_PATH" AnyKernel3/Image
    echo "✅ 已复制 Image 到 AnyKernel3"
else
    echo "❌ 未找到 Image 文件"
    exit 1
fi

# KPM修补
if [ "$KPM" = "On" ]; then
    echo "🧩 正在修补KPM..."
    cd kernel_workspace/kernel_platform/out/
    curl -LO https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/0.12.0/patch_linux
    chmod +x patch_linux
    ./patch_linux
    mv oImage Image
    cp Image "$WORK_DIR/AnyKernel3/"
    cd "$WORK_DIR"
fi

# 查找模块
if [ "$lz4kd" = "On" ]; then
    echo "🔍 查找内核模块..."
    find . -name "zram.ko"
    find . -name "crypto_zstdn.ko"
fi

# 打包ZIP
cd AnyKernel3
zip -r9 "../SukiSU_Ultra_${FEIL}.zip" ./*
cd ..

echo "✅ 编译完成！"
echo "📦 内核包: $WORK_DIR/SukiSU_Ultra_${FEIL}.zip"
echo "💾 ccache统计:"
ccache -s

# 用法示例：
# chmod +x build_kernel.sh
# ./build_kernel.sh sm8650 oneplus_12 pineapple android14 6.1 Off Off Off On