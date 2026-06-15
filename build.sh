#!/bin/bash
#
# Compile script for Perf kernel
# Copyright (C) 2020-2021 Adithya R.

set -euo pipefail

trap 'printf "\nInterrupted.\n"; exit 1' INT

ZIPNAME="Perf-surya-$(date '+%d%m%Y-%H%M').zip"
TC_DIR="$(pwd)/tc"
AK3_DIR="$(pwd)/AnyKernel3"
DEFCONFIG="surya_defconfig"

if git rev-parse --is-inside-work-tree &>/dev/null; then
	SHA=$(git rev-parse --verify HEAD)
	ZIPNAME="${ZIPNAME::-4}-${SHA:0:8}.zip"
fi

if [ ! -d "$TC_DIR" ]; then
	printf "Cloning Clang v19.0.1 based on r536225 to %s...\n" "$TC_DIR"
    mkdir -p "$TC_DIR" && cd "$TC_DIR"
    curl -sSLO "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/192fe0d378bb9cd4d4271de3e87145a1956fef40/clang-r536225.tar.gz"
    tar -xzf clang-r536225.tar.gz
    rm -rf clang-r536225.tar.gz
    cd ..
fi

export PATH="$TC_DIR/bin:$PATH"

if [ ! -d "$AK3_DIR" ]; then
    printf "Cloning AnyKernel3 to %s...\n" "$AK3_DIR"
	git clone --depth=1 -b Perf https://github.com/xvergilantte/AnyKernel3.git "$AK3_DIR"
fi

if [[ ${1:-} == -r || ${1:-} == --regen ]]; then
	make $DEFCONFIG savedefconfig
	cp out/defconfig arch/arm64/configs/$DEFCONFIG
	printf "\nSuccessfully regenerated defconfig at %s\n" $DEFCONFIG
	exit
fi

if [[ ${1:-} == -rf || ${1:-} == --regen-full ]]; then
	make $DEFCONFIG
	cp out/.config arch/arm64/configs/$DEFCONFIG
	printf "\nSuccessfully regenerated full defconfig at %s\n" $DEFCONFIG
	exit
fi

CLEAN="false"
KSU="false"

for arg in "$@"; do
	case $arg in
	-c | --clean)
		CLEAN="true"
		;;
	-s | --su)
		KSU="true"
		;;
	*)
		printf "Unknown argument: %s\n" "$arg"
		exit 1
		;;
	esac
done

if [[ $CLEAN == "true" ]]; then
	printf "Cleaning output directory...\n"
	rm -rf out
fi

printf "Starting compilation...\n"
make $DEFCONFIG

if [[ $KSU == "true" ]]; then
	printf "Building with KernelSU support...\n"
	ZIPNAME="${ZIPNAME/Perf-surya/Perf-KSU}"
	scripts/config --file out/.config -e KSU -e KSU_MANUAL_HOOK
	make olddefconfig &>/dev/null
fi

printf "\n"
SECONDS=0
make -j"$(nproc --all)" \
    O=out \
    ARCH=arm64 \
    CC=clang \
    LD=ld.lld \
    AS=llvm-as \
    AR=llvm-ar \
    NM=llvm-nm \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    STRIP=llvm-strip \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    LLVM=1 \
    LLVM_IAS=1 \
    Image.gz \
    dtb.img \
    dtbo.img \
|& tee build.log || exit ${PIPESTATUS[0]}
BUILD_TIME=$SECONDS

kernel="out/arch/arm64/boot/Image.gz"
dtb="out/arch/arm64/boot/dtb.img"
dtbo="out/arch/arm64/boot/dtbo.img"

if [ ! -f "$kernel" ] || [ ! -f "$dtb" ] || [ ! -f "$dtbo" ]; then
	printf "\nMissing build artifacts, aborting.\n"
	exit 1
fi

printf "\nKernel compiled successfully! Zipping up...\n"
cp "$kernel" "$dtb" "$dtbo" "$AK3_DIR"
cd "$AK3_DIR"
zip -r9 "../$ZIPNAME" ./* -x .git README.md \*placeholder &>/dev/null
rm -rf Image.gz dtb.img dtbo.img
cd ..
printf "\nCompleted in %d minute(s) and %d second(s)!\n" $((BUILD_TIME / 60)) $((BUILD_TIME % 60))
printf "Zip: %s\n" "$ZIPNAME"
