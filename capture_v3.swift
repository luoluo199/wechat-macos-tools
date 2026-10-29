// capture_v3.swift — 直接用 ScreenCaptureKit 截取微信主窗口

import Cocoa
import ScreenCaptureKit

@available(macOS 14.0, *)
func captureWeChatWindow() async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

    // 找微信主窗口 (最大的那个有标题的)
    let wechatWindows = content.windows.filter {
        $0.owningApplication?.bundleIdentifier == "com.tencent.xinWeChat"
        && $0.frame.width > 200 && $0.frame.height > 200
    }

    guard let mainWindow = wechatWindows.first(where: { ($0.title ?? "").contains("微信") && $0.frame.width > 500 })
          ?? wechatWindows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
        print("❌ 未找到微信主窗口")
        return
    }

    print("目标窗口: ID=\(mainWindow.windowID) \"\(mainWindow.title ?? "")\" \(Int(mainWindow.frame.width))x\(Int(mainWindow.frame.height))")

    // 截取单个窗口
    let filter = SCContentFilter(desktopIndependentWindow: mainWindow)
    let config = SCStreamConfiguration()
    config.width = Int(mainWindow.frame.width) * 2
    config.height = Int(mainWindow.frame.height) * 2
    config.scalesToFit = false
    config.showsCursor = false
    config.captureResolution = .best

    print("正在截取...")
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

    // 保存
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/wechat_window.png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)

    print("📄 已保存: \(url.path) (\(image.width)x\(image.height))")

    // 检查内容
    if let dp = image.dataProvider, let data = dp.data as Data? {
        let bpp = image.bitsPerPixel / 8
        var colorful = 0, transparent = 0, white = 0, black = 0, total = 0
        let step = max(bpp, data.count / (bpp * 1000)) / bpp * bpp

        for i in stride(from: 0, to: data.count - bpp, by: step) {
            total += 1
            if bpp >= 4 {
                let b = data[i], g = data[i+1], r = data[i+2], a = data[i+3]
                if a < 10 { transparent += 1 }
                else if r > 245 && g > 245 && b > 245 { white += 1 }
                else if r < 10 && g < 10 && b < 10 { black += 1 }
                else { colorful += 1 }
            }
        }
        print("\n像素分析 (采样\(total)点):")
        print("  有内容: \(colorful) (\(colorful * 100 / max(total,1))%)")
        print("  白色: \(white) (\(white * 100 / max(total,1))%)")
        print("  黑色: \(black) (\(black * 100 / max(total,1))%)")
        print("  透明: \(transparent) (\(transparent * 100 / max(total,1))%)")

        if colorful > total / 10 {
            print("\n✅ 截图有内容！请检查桌面上的 wechat_window.png")
        } else {
            print("\n⚠️ 截图基本是空白的，微信的防截图保护在此系统版本上仍然生效")
        }
    }
}

if #available(macOS 14.0, *) {
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            try await captureWeChatWindow()
        } catch {
            print("❌ 错误: \(error)")
        }
        sem.signal()
    }
    sem.wait()
}
