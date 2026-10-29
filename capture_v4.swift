// capture_v4.swift — 用 NSApplication 初始化 GUI 环境后截取微信窗口

import Cocoa
import ScreenCaptureKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await run()
            NSApp.terminate(nil)
        }
    }

    func run() async {
        guard #available(macOS 14.0, *) else {
            print("需要 macOS 14.0+")
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

            let wechatWindows = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == "com.tencent.xinWeChat"
                && $0.frame.width > 200 && $0.frame.height > 200
            }

            guard let mainWindow = wechatWindows.first(where: { ($0.title ?? "").contains("微信") && $0.frame.width > 500 })
                  ?? wechatWindows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                print("❌ 未找到微信主窗口")
                return
            }

            print("目标: ID=\(mainWindow.windowID) \"\(mainWindow.title ?? "")\" \(Int(mainWindow.frame.width))x\(Int(mainWindow.frame.height))")

            let filter = SCContentFilter(desktopIndependentWindow: mainWindow)
            let config = SCStreamConfiguration()
            config.width = Int(mainWindow.frame.width) * 2
            config.height = Int(mainWindow.frame.height) * 2
            config.showsCursor = false

            print("截取中...")
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/wechat_window.png")
            let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            print("📄 已保存: \(url.path) (\(image.width)x\(image.height))")

            // 像素分析
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
                print("像素: 有内容=\(colorful)(\(colorful*100/max(total,1))%) 白=\(white)(\(white*100/max(total,1))%) 黑=\(black)(\(black*100/max(total,1))%) 透明=\(transparent)(\(transparent*100/max(total,1))%)")
                if colorful > total / 10 {
                    print("✅ 截图成功，有内容！")
                } else {
                    print("⚠️ 截图基本空白，防截图保护仍然生效")
                }
            }
        } catch {
            print("❌ \(error)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
