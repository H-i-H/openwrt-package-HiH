#!/usr/bin/env bash
# 统一编译脚本：本地与 GitHub Actions 共用，保证两边行为一致
# 用法: ./scripts/build.sh <SDK-target> [编译目标...]
#   例: ./scripts/build.sh x86/64
#       ./scripts/build.sh rockchip/armv8 xray-core
set -euo pipefail
TARGET=${1:?用法: $0 <target> [编译目标...]}; shift || true
RELEASE=${RELEASE:-25.12.6}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

# 没点名包就读晋级清单
if (($#)); then PKGS=("$@"); else
  mapfile -t PKGS < <(sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' "$ROOT/build/packages.list" | grep -v '^$')
fi

SDKDIR="$HOME/sdk/${TARGET//\//-}-sdk"    # x86/64 → ~/sdk/x86-64-sdk
mkdir -p "$HOME/sdk"

# 没有 SDK 就自动下载
if [ ! -f "$SDKDIR/feeds.conf.default" ]; then
  BASE="https://downloads.openwrt.org/releases/$RELEASE/targets/$TARGET"
  SDK=$(curl -fsSL "$BASE/" | grep -oE 'openwrt-sdk-[^"<>]*\.tar\.zst' | head -n1)
  [ -n "$SDK" ] || { echo "在 $BASE 找不到 SDK"; exit 1; }
  wget -c -q --show-progress -P "$HOME/sdk" "$BASE/$SDK"
  rm -rf "$SDKDIR"; mkdir -p "$SDKDIR"
  tar xf "$HOME/sdk/$SDK" --strip-components=1 -C "$SDKDIR"
fi

cd "$SDKDIR"
cp feeds.conf.default feeds.conf
echo "src-link HiH $ROOT" >> feeds.conf
./scripts/feeds update -a
./scripts/feeds install -f -p HiH -a

# 已知修复: Go 1.27（把 NOTES.md 第 2 条的踩坑固化成代码）
sed -i 's/GO_DEFAULT_VERSION:=1.26/GO_DEFAULT_VERSION:=1.27/' \
  feeds/packages/lang/golang/golang-values.mk
./scripts/feeds install -f golang1.27

make defconfig
make package/golang1.27/compile V=s -j"$(nproc)"   # Go 工具链

# ---- vmlinux-btf 特例：honk/dae 的依赖链会拽出它，必须带参数编译 ----
BTF_VER=${BTF_VER:-6.12.112}
BTF_TAG=${BTF_TAG:-openwrt-25.12.6-6.12.112-20261122}
T=${TARGET//\//-}                       # x86/64 → x86-64
BTF_TAR="25.12.6-vmlinux-${T}-${BTF_VER}.tar.xz"
if [ ! -f "dl/$BTF_TAR" ]; then
  wget -c -q --show-progress -P dl \
    "https://github.com/daeuniverse/openwrt-packages/releases/download/${BTF_TAG}/${BTF_TAR}" \
    || echo "警告: BTF 下载失败，可手动把 $BTF_TAR 放进 $(pwd)/dl/ 再重跑"
fi
BLOB=""
if [ -f "dl/$BTF_TAR" ]; then
  rm -rf tmp-btf && mkdir tmp-btf
  tar xf "dl/$BTF_TAR" -C tmp-btf
  for f in $(find tmp-btf -type f); do
    [ "$(od -An -tx1 -N2 "$f" | tr -d ' \n')" = "9feb" ] && { BLOB="$PWD/$f"; break; }
  done
fi

for p in "${PKGS[@]}"; do
  echo "==> 编译 $p"
  if [ -n "$BLOB" ]; then
    make "package/$p/compile" V=s -j"$(nproc)" \
      VMLINUX_BTF_SRC="$BLOB" VMLINUX_BTF_VERSION="$BTF_VER"
  else
    make "package/$p/compile" V=s -j"$(nproc)"
  fi
done

# 收集产物：本 feed 的包 + 内核模块 → dist/<架构>/
ARCH=$(find bin/packages -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | head -1)
DEST="$ROOT/dist/$ARCH"; mkdir -p "$DEST"
find "bin/packages/$ARCH/HiH" -name '*.apk' -exec cp {} "$DEST/" \;
find bin/targets -name 'kmod-oaf-*.apk' -exec cp {} "$DEST/" \;   # 只收本仓库的内核模块
echo "==> 产物收集完毕: $DEST"
ls "$DEST"
