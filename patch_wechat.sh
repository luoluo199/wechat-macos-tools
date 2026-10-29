#!/bin/bash
# patch_wechat.sh — 编译并更新微信补丁 (防截屏 + 防检测自动化)
set -e

WECHAT_APP="/Applications/.WeChat_Patched.app"
WECHAT_BIN="$WECHAT_APP/Contents/MacOS/WeChat"
DYLIB_DEST="$WECHAT_APP/Contents/MacOS/unsharingtype.dylib"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "===== 微信补丁更新 ====="

# 关闭微信
echo "🔄 关闭微信..."
pkill -x WeChat 2>/dev/null || true
sleep 2

# 编译合并 dylib (unsharingtype + antirobot)
echo "🔨 编译 dylib (防截屏 + 防自动化检测)..."
clang -shared -framework Foundation -framework AppKit -framework CoreGraphics \
    -arch arm64 \
    -Wno-deprecated-declarations \
    -o /tmp/unsharingtype.dylib \
    "$SCRIPT_DIR/unsharingtype.m" \
    "$SCRIPT_DIR/antirobot.m"
echo "   ✅ 编译完成"

# 替换 dylib
echo "📦 更新 dylib..."
cp /tmp/unsharingtype.dylib "$DYLIB_DEST"
codesign --force --sign - "$DYLIB_DEST"
echo "   ✅ 已更新"

# dylib 已经注入过了，不需要再次 insert_dylib
# 只需要重签主二进制
echo "✍️  重签主二进制..."
codesign --force --sign - "$WECHAT_BIN"

echo ""
echo "===== 完成 ====="
echo "✅ 补丁已更新。请手动启动微信测试。"
echo "   防截屏: unsharingtype (强制 sharingType=readWrite)"
echo "   防检测: antirobot (CGEvent 来源伪装)"
