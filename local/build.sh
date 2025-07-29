#!/bin/bash
export all_proxy=socks5://192.168.2.150:10810/
# filepath: build_sukisu_ultra.sh

set -e

# ========== 参数解析 ==========
CPU=${1:-sm8650}
FEIL=${2:-oneplus_12}
CPUD=${3:-pineapple}
ANDROID_VERSION=${4:-android14}
KERNEL_VERSION=${5:-6.1}
KPM=${6:-Off}
lz4kd=${7:-Off}
bbr=${8:-Off}
proxy=${9:-On}

echo "参数: CPU=$CPU FEIL=$FEIL CPUD=$CPUD ANDROID_VERSION=$ANDROID_VERSION KERNEL_VERSION=$KERNEL_VERSION KPM=$KPM lz4kd=$lz4kd bbr=$bbr proxy=$proxy"

# ========== 环境变量与ccache ==========
export CCACHE_COMPILERCHECK="%compiler% -dumpmachine; %compiler% -dumpversion"
export CCACHE_NOHASHDIR="true"
export CCACHE_HARDLINK="true"
export CCACHE_MAXSIZE=8G
export CCACHE_DIR="$HOME/.ccache_${FEIL}"
mkdir -p "$CCACHE_DIR"

if command -v ccache >/dev/null 2>&1; then
  ccache -M $CCACHE_MAXSIZE
  ccache -z
  ccache -s
else
  echo "⚠️ 未找到ccache命令，建议安装以加速编译"
fi

# ========== 配置Git ==========
git config --global user.name "build"
git config --global user.email "2210077278@qq.com"

# ========== 安装依赖 ==========
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y python3 git curl ccache libelf-dev \
  build-essential flex bison libssl-dev libncurses-dev liblz4-tool zlib1g-dev \
  libxml2-utils rsync unzip

# ========== 下载repo工具 ==========
if ! command -v repo >/dev/null 2>&1; then
  curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo > ~/repo
  chmod a+x ~/repo
  sudo mv ~/repo /usr/local/bin/repo
fi

# ========== 克隆内核源码 ==========
rm -rf kernel_workspace && mkdir -p kernel_workspace && cd kernel_workspace
repo init -u https://github.com/Xiaomichael/kernel_manifest.git -b refs/heads/oneplus/${CPU} -m ${FEIL}.xml --depth=1
repo sync -c -j$(nproc --all) --no-tags --no-clone-bundle --force-sync

# 下载内核设置工具
curl -L -o kernel_setup.bin https://github.com/Xiaomichael/OnePlus-Actions/raw/Build/script/kernel_setup.bin
chmod +x kernel_setup.bin
./kernel_setup.bin

# ========== 配置SukiSU Ultra ==========
mkdir -p kernel_platform
cd kernel_platform
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/susfs-main/kernel/setup.sh" | bash -s susfs-main

cd KernelSU
curl -L -o sukisu_setup.bin https://github.com/Xiaomichael/OnePlus-Actions/raw/Build/script/sukisu_setup.bin
chmod +x sukisu_setup.bin
if [ ! -f "kernel/Makefile" ]; then
  echo "❌ 错误：缺少kernel/Makefile"
  ls -la
  exit 1
fi
./sukisu_setup.bin
cd ../..

# ========== SUSFS补丁 ==========
cd kernel_workspace
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-${ANDROID_VERSION}-${KERNEL_VERSION}
git clone https://github.com/Xiaomichael/kernel_patches.git
git clone https://github.com/ShirkNeko/SukiSU_patch.git

cd kernel_platform
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch ./common/
cp ../kernel_patches/next/syscall_hooks.patch ./common/
cp ../susfs4ksu/kernel_patches/fs/* ./common/fs/
cp ../susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/

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

cd ./common
patch -p1 < 50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch || true
cp ../../kernel_patches/69_hide_stuff.patch ./
patch -p1 -F 3 < 69_hide_stuff.patch
patch -p1 -F 3 < syscall_hooks.patch

if [ "$lz4kd" = "Off" ] && [ "$KERNEL_VERSION" = "6.1" ]; then
  git apply -p1 < 001-lz4.patch || true
  patch -p1 < 002-zstd.patch || true
fi

if [ "$lz4kd" = "On" ]; then
  cp ../../SukiSU_patch/other/zram/zram_patch/${KERNEL_VERSION}/lz4kd.patch ./
  patch -p1 -F 3 < lz4kd.patch || true
  cp ../../SukiSU_patch/other/zram/zram_patch/${KERNEL_VERSION}/lz4k_oplus.patch ./
  patch -p1 -F 3 < lz4k_oplus.patch || true
fi
cd ../..

# ========== 配置内核选项 ==========
DEFCONFIG=kernel_workspace/kernel_platform/common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU=y" >> $DEFCONFIG
[ "$KPM" = "On" ] && echo "CONFIG_KPM=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_SUS_SU=n" >> $DEFCONFIG
echo "CONFIG_KSU_MANUAL_HOOK=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_SUS_PATH=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_SUS_MOUNT=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_SUS_KSTAT=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_SUS_OVERLAYFS=n" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_TRY_UMOUNT=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_SPOOF_UNAME=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_ENABLE_LOG=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y" >> $DEFCONFIG
echo "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y" >> $DEFCONFIG

if [ "$bbr" = "On" ]; then
  echo "CONFIG_TCP_CONG_ADVANCED=y" >> $DEFCONFIG
  echo "CONFIG_TCP_CONG_BBR=y" >> $DEFCONFIG
  echo "CONFIG_NET_SCH_FQ=y" >> $DEFCONFIG
  echo "CONFIG_TCP_CONG_BIC=n" >> $DEFCONFIG
  echo "CONFIG_TCP_CONG_WESTWOOD=n" >> $DEFCONFIG
  echo "CONFIG_TCP_CONG_HTCP=n" >> $DEFCONFIG
fi

if [ "$lz4kd" = "On" ]; then
  echo "CONFIG_CRYPTO_LZ4KD=y" >> $DEFCONFIG
  echo "CONFIG_CRYPTO_LZ4K_OPLUS=y" >> $DEFCONFIG
  echo "CONFIG_ZRAM_WRITEBACK=y" >> $DEFCONFIG
fi

if [ "$KERNEL_VERSION" = "6.1" ]; then
  echo "CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y" >> $DEFCONFIG
fi

if [ "$proxy" = "On" ]; then
  cat <<EOP >> $DEFCONFIG
CONFIG_BPF_STREAM_PARSER=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_NETFILTER_XT_SET=y
CONFIG_IP_SET=y
CONFIG_IP_SET_MAX=65534
CONFIG_IP_SET_BITMAP_IP=y
CONFIG_IP_SET_BITMAP_IPMAC=y
CONFIG_IP_SET_BITMAP_PORT=y
CONFIG_IP_SET_HASH_IP=y
CONFIG_IP_SET_HASH_IPMARK=y
CONFIG_IP_SET_HASH_IPPORT=y
CONFIG_IP_SET_HASH_IPPORTIP=y
CONFIG_IP_SET_HASH_IPPORTNET=y
CONFIG_IP_SET_HASH_IPMAC=y
CONFIG_IP_SET_HASH_MAC=y
CONFIG_IP_SET_HASH_NETPORTNET=y
CONFIG_IP_SET_HASH_NET=y
CONFIG_IP_SET_HASH_NETNET=y
CONFIG_IP_SET_HASH_NETPORT=y
CONFIG_IP_SET_HASH_NETIFACE=y
CONFIG_IP_SET_LIST_SET=y
CONFIG_IP6_NF_NAT=y
CONFIG_IP6_NF_TARGET_MASQUERADE=y
EOP
fi

if [ "$KERNEL_VERSION" = "5.10" ] || [ "$KERNEL_VERSION" = "5.15" ]; then
  sed -i 's/^CONFIG_LTO=n/CONFIG_LTO=y/' "$DEFCONFIG"
  sed -i 's/^CONFIG_LTO_CLANG_FULL=y/CONFIG_LTO_CLANG_THIN=y/' "$DEFCONFIG"
  sed -i 's/^CONFIG_LTO_CLANG_NONE=y/CONFIG_LTO_CLANG_THIN=y/' "$DEFCONFIG"
  grep -q '^CONFIG_LTO_CLANG_THIN=y' "$DEFCONFIG" || echo 'CONFIG_LTO_CLANG_THIN=y' >> "$DEFCONFIG"
fi

sed -i 's/check_defconfig//' kernel_workspace/kernel_platform/common/build.config.gki

# ========== 编译内核 ==========
cd kernel_workspace/kernel_platform/common
if [ "$KERNEL_VERSION" = "6.1" ]; then
  export KBUILD_BUILD_TIMESTAMP="Thu May 29 07:25:40 UTC 2025"
  export KBUILD_BUILD_VERSION=1
  export PATH="$PWD/../prebuilts/clang/host/linux-x86/clang-r487747c/bin:$PATH"
  export PATH="/usr/lib/ccache:$PATH"
  sudo apt install -y libelf-dev
  make -j$(nproc --all) LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC="ccache clang" RUSTC=../../prebuilts/rust/linux-x86/1.73.0b/bin/rustc PAHOLE=../../prebuilts/kernel-build-tools/linux-x86/bin/pahole LD=ld.lld HOSTLD=ld.lld O=out KCFLAGS+=-O2 gki_defconfig all
elif [ "$KERNEL_VERSION" = "5.15" ]; then
  export PATH="$PWD/../prebuilts/clang/host/linux-x86/clang-r450784e/bin:$PATH"
  export PATH="/usr/lib/ccache:$PATH"
  sudo apt install -y libelf-dev
  make -j$(nproc --all) LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC="ccache clang" RUSTC=../../prebuilts/rust/linux-x86/1.73.0b/bin/rustc PAHOLE=../../prebuilts/kernel-build-tools/linux-x86/bin/pahole LD=ld.lld HOSTLD=ld.lld O=out gki_defconfig all
elif [ "$KERNEL_VERSION" = "5.10" ]; then
  export PATH="$PWD/../prebuilts-master/clang/host/linux-x86/clang-r416183b/bin:$PATH"
  export PATH="/usr/lib/ccache:$PATH"
  sudo apt install -y libelf-dev
  make -j$(nproc --all) LLVM_IAS=1 LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC="ccache clang" RUSTC=../../prebuilts/rust/linux-x86/1.73.0b/bin/rustc PAHOLE=../../prebuilts/kernel-build-tools/linux-x86/bin/pahole LD=ld.lld HOSTLD=ld.lld O=out gki_defconfig all
fi

ccache -s

# ========== 打包 AnyKernel3 ==========
cd "$OLDPWD"
AK3_DIR="AnyKernel3"
if [ -d "$AK3_DIR" ]; then
  rm -rf "$AK3_DIR"
fi
git clone --depth=1 https://github.com/Xiaomichael/AnyKernel3 "$AK3_DIR"
rm -rf "$AK3_DIR/.git"

IMAGE_PATH=$(find kernel_workspace/kernel_platform/common/out/ -name "Image" | head -n 1)
if [ -n "$IMAGE_PATH" ] && [ -f "$IMAGE_PATH" ]; then
  cp "$IMAGE_PATH" "$AK3_DIR/Image"
  echo "✅ 已复制 Image 到 AnyKernel3 目录"
else
  echo "❌ 未找到 Image 文件，打包失败"
fi

# ========== KPM 修补镜像 ==========
if [ "$KPM" = "On" ]; then
  echo "🧩 正在修补 KPM 镜像 ..."
  cd kernel_workspace/kernel_platform/out/
  curl -LO https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/0.12.0/patch_linux
  chmod +x patch_linux
  ./patch_linux
  rm -f Image
  mv oImage Image
  cp Image "$OLDPWD/$AK3_DIR/Image"
  cd "$OLDPWD"
  echo "✅ KPM 修补完成"
fi

echo "✅ 内核编译完成，产物请在 out/ 目录查找，AnyKernel3 打包目录为 $AK3_DIR"

# 用法示例：
# bash build_sukisu_ultra.sh sm8650 oneplus_12 pineapple android14 6.1 Off Off Off On