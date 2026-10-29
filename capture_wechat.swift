// capture_wechat.swift
// 使用 ScreenCaptureKit 截取微信窗口（绕过 sharingType = .none 限制）
// macOS 15+ ScreenCaptureKit 不再尊重窗口隐私设置

import Cocoa
import ScreenCaptureKit

@available(macOS 12.3, *)
func captureWeChat() async throws {
    // 获取所有可共享内容
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

    // 查找微信窗口
    let wechatWindows = content.windows.filter { window in
        window.owningApplication?.bundleIdentifier == "com.tencent.xinWeChat"
    }

    if wechatWindows.isEmpty {
        print("❌ 未找到微信窗口，请确保微信已打开")
        // 列出所有窗口帮助调试
        print("\n当前所有窗口：")
        for w in content.windows.prefix(20) {
            print("  - [\(w.owningApplication?.bundleIdentifier ?? "unknown")] \(w.title ?? "(无标题)") (\(Int(w.frame.width))x\(Int(w.frame.height)))")
        }
        return
    }

    print("找到 \(wechatWindows.count) 个微信窗口：")
    for (i, w) in wechatWindows.enumerated() {
        print("  [\(i)] \(w.title ?? "(无标题)") - \(Int(w.frame.width))x\(Int(w.frame.height))")
    }

    // 选择最大的窗口（通常是主窗口）
    guard let targetWindow = wechatWindows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
        return
    }

    print("\n正在截取: \(targetWindow.title ?? "(无标题)") (\(Int(targetWindow.frame.width))x\(Int(targetWindow.frame.height)))")

    // 配置截图
    let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
    let config = SCStreamConfiguration()
    config.width = Int(targetWindow.frame.width) * 2  // Retina
    config.height = Int(targetWindow.frame.height) * 2
    config.scalesToFit = false
    config.showsCursor = false

    // 截图
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

    // 保存到桌面
    let desktopURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/wechat_capture.png")
    let dest = CGImageDestinationCreateWithURL(desktopURL as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)

    // 检查图片是否全白/全黑/全透明
    let dataProvider = image.dataProvider!
    let data = dataProvider.data! as Data
    let totalPixels = image.width * image.height
    var nonEmptyPixels = 0
    let bytesPerPixel = image.bitsPerPixel / 8

    for i in stride(from: 0, to: min(data.count, totalPixels * bytesPerPixel), by: bytesPerPixel * 100) {
        // 采样检查
        if bytesPerPixel >= 4 {
            let r = data[i], g = data[i+1], b = data[i+2], a = data[i+3]
            if a > 0 && !(r == 255 && g == 255 && b == 255) && !(r == 0 && g == 0 && b == 0) {
                nonEmptyPixels += 1
            }
        }
    }

    if nonEmptyPixels == 0 {
        print("⚠️  截图看起来是空白的（全白/全黑/全透明），微信可能仍在阻止截图")
    } else {
        print("✅ 截图成功！")
    }
    print("📄 已保存到: \(desktopURL.path)")
}

// 主入口
if #available(macOS 12.3, *) {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            try await captureWeChat()
        } catch {
            print("❌ 错误: \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
} else {
    print("需要 macOS 12.3 或更高版本")
}
