#!/usr/bin/env bash
# 组装并签名 apk 软件源（本地试签和 CI 发布共用这份）
# 用法: APK_SIGN_KEY=私钥路径 ./scripts/repo.sh
# 产物: repo/<版本>/<架构>/packages.adb + *.apk，以及 repo/hih.pem
set -euo pipefail
RELEASE=${RELEASE:-25.12.6}
KEY=${APK_SIGN_KEY:?请设置环境变量 APK_SIGN_KEY 指向签名私钥}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

# apk 工具用 SDK 自带的（编过包就一定有）
APK=${APK_TOOL:-$(find "$HOME/sdk" -maxdepth 5 -path '*/staging_dir/host/bin/apk' | head -1)}
[ -n "$APK" ] || { echo "找不到 apk 工具，请先跑一次 scripts/build.sh"; exit 1; }

rm -rf "$ROOT/repo"
for dir in "$ROOT"/dist/*/; do
  ARCH=$(basename "$dir")
  OUT="$ROOT/repo/$RELEASE/$ARCH"; mkdir -p "$OUT"
  cp "$dir"/*.apk "$OUT/"
  # --allow-untrusted: 收进来的 .apk 本身未单独签名（与官方做法一致）
  # --sign: 给索引签名，设备端凭公钥信任整套源
  (cd "$OUT" && "$APK" mkndx --root . --keys-dir . \
      --sign "$KEY" --allow-untrusted --output packages.adb ./*.apk)
done
cp "$ROOT/hih.pem" "$ROOT/repo/hih.pem"
echo "==> 软件源组装完毕:"
find "$ROOT/repo" -type f | sort
