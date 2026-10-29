#!/bin/bash
# inject_v2.sh — 改进版注入，只修改主二进制签名，不破坏其他组件
# 用法: ./inject_v2.sh [--restore]

set -e

WECHAT_APP="/Applications/WeChat.app"
WECHAT_BIN="$WECHAT_APP/Contents/MacOS/WeChat"
DYLIB_NAME="unsharingtype.dylib"
DYLIB_SRC="$(dirname "$0")/unsharingtype.m"
DYLIB_DEST="$WECHAT_APP/Contents/MacOS/$DYLIB_NAME"
BACKUP_BIN="$WECHAT_BIN.backup"

# 还原模式
if [ "$1" = "--restore" ]; then
    if [ -f "$BACKUP_BIN" ]; then
        echo "正在还原..."
        cp "$BACKUP_BIN" "$WECHAT_BIN"
        rm -f "$DYLIB_DEST"
        echo "✅ 已还原。请重启微信。"
    else
        echo "❌ 未找到备份: $BACKUP_BIN"
    fi
    exit 0
fi

echo "===== 微信防截图解除工具 v2 ====="
echo ""

# 检查
[ ! -f "$WECHAT_BIN" ] && echo "❌ 未找到微信" && exit 1

# 关闭微信
echo "🔄 关闭微信..."
pkill -x WeChat 2>/dev/null || true
sleep 2

# 备份主二进制
if [ ! -f "$BACKUP_BIN" ]; then
    echo "📋 备份主二进制..."
    cp "$WECHAT_BIN" "$BACKUP_BIN"
fi

# 编译 dylib (使用硬编码值 2 避免废弃警告)
echo "🔨 编译 dylib..."
cat > /tmp/unsharingtype_v2.m << 'OBJC_EOF'
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static void (*orig_setSharingType)(id self, SEL _cmd, NSWindowSharingType type);

static void hook_setSharingType(id self, SEL _cmd, NSWindowSharingType type) {
    // 强制设为 2 (readWrite)，避免使用已废弃的常量名
    orig_setSharingType(self, _cmd, (NSWindowSharingType)2);
}

static void fixAllWindows(void) {
    for (NSWindow *window in [NSApp windows]) {
        if (window.sharingType != (NSWindowSharingType)2) {
            window.sharingType = (NSWindowSharingType)2;
        }
    }
}

__attribute__((constructor))
static void initialize(void) {
    NSLog(@"[UnSharingType] 正在加载...");
    Method method = class_getInstanceMethod([NSWindow class], @selector(setSharingType:));
    if (method) {
        orig_setSharingType = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)hook_setSharingType);
        NSLog(@"[UnSharingType] ✅ hook 成功");
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        fixAllWindows();
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
            fixAllWindows();
        }];
        NSLog(@"[UnSharingType] ✅ 定时修正已启动");
    });
}
OBJC_EOF

clang -shared -framework Foundation -framework AppKit \
    -arch arm64 \
    -Wno-deprecated-declarations \
    -o /tmp/$DYLIB_NAME \
    /tmp/unsharingtype_v2.m
echo "   ✅ 编译完成"

# 复制 dylib
echo "📦 安装 dylib..."
cp /tmp/$DYLIB_NAME "$DYLIB_DEST"

# 签名 dylib (ad-hoc)
codesign --force --sign - "$DYLIB_DEST"

# 注入
if otool -L "$WECHAT_BIN" | grep -q "$DYLIB_NAME"; then
    echo "   dylib 已在加载列表中"
else
    echo "💉 注入 dylib..."
    insert_dylib --inplace --all-yes \
        "@executable_path/$DYLIB_NAME" \
        "$WECHAT_BIN"
fi

# 只签名主二进制（不用 --deep）
echo "✍️  签名主二进制（保留其他组件原始签名）..."
codesign --force --sign - "$WECHAT_BIN"

echo ""
echo "===== 完成 ====="
echo "✅ 已注入。请手动打开微信测试。"
echo "📌 还原: sudo $(realpath "$0") --restore"
