#!/bin/bash
# inject.sh — 编译 dylib 并注入到微信二进制中
# 用法: ./inject.sh [--restore]

set -e

WECHAT_APP="/Applications/WeChat.app"
WECHAT_BIN="$WECHAT_APP/Contents/MacOS/WeChat"
DYLIB_SRC="$(dirname "$0")/unsharingtype.m"
DYLIB_NAME="unsharingtype.dylib"
DYLIB_DEST="$WECHAT_APP/Contents/MacOS/$DYLIB_NAME"
BACKUP_BIN="$WECHAT_BIN.backup"

# 还原模式
if [ "$1" = "--restore" ]; then
    if [ -f "$BACKUP_BIN" ]; then
        echo "正在还原微信原始二进制..."
        sudo cp "$BACKUP_BIN" "$WECHAT_BIN"
        sudo rm -f "$DYLIB_DEST"
        sudo codesign --force --deep --sign - "$WECHAT_APP"
        echo "✅ 已还原。请重启微信。"
    else
        echo "❌ 未找到备份文件: $BACKUP_BIN"
    fi
    exit 0
fi

echo "===== 微信防截图解除工具 ====="
echo ""

# 检查微信是否存在
if [ ! -f "$WECHAT_BIN" ]; then
    echo "❌ 未找到微信: $WECHAT_BIN"
    exit 1
fi

# 检查 insert_dylib 工具
if ! command -v insert_dylib &>/dev/null; then
    echo "📦 正在安装 insert_dylib..."
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    curl -sL https://github.com/tyilo/insert_dylib/archive/refs/heads/master.zip -o insert_dylib.zip
    unzip -q insert_dylib.zip
    cd insert_dylib-master
    xcodebuild -quiet 2>/dev/null || clang -o insert_dylib insert_dylib/main.c -framework Foundation
    sudo cp insert_dylib /usr/local/bin/ 2>/dev/null || sudo cp build/Release/insert_dylib /usr/local/bin/
    cd /
    rm -rf "$TEMP_DIR"
    echo "✅ insert_dylib 已安装"
fi

# 关闭微信
echo "🔄 关闭微信..."
pkill -x WeChat 2>/dev/null || true
sleep 2

# 备份
if [ ! -f "$BACKUP_BIN" ]; then
    echo "📋 备份原始二进制..."
    sudo cp "$WECHAT_BIN" "$BACKUP_BIN"
    echo "   备份: $BACKUP_BIN"
fi

# 编译 dylib
echo "🔨 编译 dylib..."
clang -shared -framework Foundation -framework AppKit \
    -arch arm64 \
    -o /tmp/$DYLIB_NAME \
    "$DYLIB_SRC"
echo "   编译完成"

# 复制 dylib 到微信目录
echo "📦 安装 dylib..."
sudo cp /tmp/$DYLIB_NAME "$DYLIB_DEST"

# 检查是否已经注入过
if otool -L "$WECHAT_BIN" | grep -q "$DYLIB_NAME"; then
    echo "   dylib 已存在于加载列表中，跳过注入"
else
    echo "💉 注入 dylib..."
    sudo insert_dylib --inplace --all-yes \
        "@executable_path/$DYLIB_NAME" \
        "$WECHAT_BIN"
fi

# 重新签名
echo "✍️  重新签名..."
sudo codesign --force --deep --sign - "$WECHAT_APP"

echo ""
echo "===== 完成 ====="
echo "✅ 已注入防截图解除补丁"
echo "📌 请手动打开微信"
echo "📌 还原命令: $0 --restore"
echo ""
