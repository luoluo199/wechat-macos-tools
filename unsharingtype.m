// unsharingtype.m
// 注入到微信进程后，强制所有窗口 sharingType = readWrite（可截图/可录屏）
// 原理：swizzle NSWindow 的 setSharingType: 使其永远设为 readWrite，
//       同时用定时器定期修正已有窗口。

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

// 原始方法指针
static void (*orig_setSharingType)(id self, SEL _cmd, NSWindowSharingType type);

// 替换方法：无论传入什么值都设为 readWrite
static void hook_setSharingType(id self, SEL _cmd, NSWindowSharingType type) {
    orig_setSharingType(self, _cmd, NSWindowSharingReadWrite);
}

// 定时修正所有窗口
static void fixAllWindows(void) {
    for (NSWindow *window in [NSApp windows]) {
        if (window.sharingType != NSWindowSharingReadWrite) {
            window.sharingType = NSWindowSharingReadWrite;
        }
    }
}

__attribute__((constructor))
static void initialize(void) {
    NSLog(@"[UnSharingType] 加载中...");

    // Swizzle -[NSWindow setSharingType:]
    Method method = class_getInstanceMethod([NSWindow class], @selector(setSharingType:));
    if (method) {
        orig_setSharingType = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)hook_setSharingType);
        NSLog(@"[UnSharingType] ✅ 已 hook setSharingType:");
    } else {
        NSLog(@"[UnSharingType] ❌ 未找到 setSharingType: 方法");
    }

    // 延迟启动定时器（等 NSApp 初始化完成）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // 立即修正一次
        fixAllWindows();

        // 每 2 秒检查修正
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
            fixAllWindows();
        }];

        NSLog(@"[UnSharingType] ✅ 定时修正已启动");
    });
}
