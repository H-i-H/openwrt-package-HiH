#!/usr/bin/env bash
# scripts/sync.sh —— 一键同步所有上游包到本仓库
# 用法：bash scripts/sync.sh
set -euo pipefail
cd "$(dirname "$0")/.."

LOCK=upstreams.lock
echo "sync $(date '+%F %T')" > $LOCK

# 同步单个软件包仓库（自动识别"仓库根就是包"或"包在子文件夹"两种情况）
sync_pkg() {
  local dest=$1 url=$2
  local tmp; tmp=$(mktemp -d)
  echo "==> [$dest]"
  git clone --depth 1 "$url" "$tmp/r"
  if [ -f "$tmp/r/Makefile" ]; then
    rm -rf "$dest"; mkdir -p "$dest"
    cp -r "$tmp/r"/. "$dest"/
    rm -rf "$dest/.git"
  elif [ -d "$tmp/r/$dest" ]; then
    rm -rf "$dest"; cp -r "$tmp/r/$dest" "$dest"
  else
    echo "!! $dest 结构不认识，请手动检查 $url"; exit 1
  fi
  echo "$dest $url $(git -C "$tmp/r" rev-parse HEAD)" >> $LOCK
  rm -rf "$tmp"
}

# 同步多包仓库（把所有含 Makefile 的子文件夹摊平复制过来）
sync_feed() {
  local url=$1
  local tmp; tmp=$(mktemp -d)
  echo "==> [feed] $url"
  git clone --depth 1 "$url" "$tmp/r"
  for d in "$tmp/r"/*/; do
    [ -f "$d/Makefile" ] || continue
    local pkg; pkg=$(basename "$d")
    rm -rf "$pkg"; cp -r "$d" "$pkg"
  done
  echo "feed $url $(git -C "$tmp/r" rev-parse HEAD)" >> $LOCK
  rm -rf "$tmp"
}

# ---- 单包仓库 ----
sync_pkg luci-theme-7dollar https://github.com/itsmaiGe/luci-theme-7dollar
sync_pkg luci-app-socat     https://github.com/chenmozhijin/luci-app-socat

# ---- 多包仓库 ----
sync_feed https://github.com/sbwml/luci-app-quickfile
sync_feed https://github.com/destan19/OpenAppFilter
sync_feed https://github.com/Openwrt-Passwall/openwrt-passwall
sync_feed https://github.com/Openwrt-Passwall/openwrt-passwall-packages
sync_feed https://github.com/daeuniverse/openwrt-packages

# ---- honk 特例：打包规则要求源码放在 honk/src ----
echo "==> [honk/src]"
tmp=$(mktemp -d)
git clone --depth 1 https://github.com/daeuniverse/honk "$tmp/r"
rm -rf honk/src; mkdir -p honk/src
cp -r "$tmp/r"/. honk/src/
rm -rf honk/src/.git
echo "honk/src https://github.com/daeuniverse/honk $(git -C "$tmp/r" rev-parse HEAD)" >> $LOCK
rm -rf "$tmp"

echo
echo "同步完成！上游版本记录在 $LOCK"