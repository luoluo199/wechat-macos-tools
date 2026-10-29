// capture_cg.swift
// 使用 CGWindowListCopyWindowInfo 查找微信窗口并截图

import Cocoa

func main() {
    // 用 CGWindowList 获取所有窗口（比 ScreenCaptureKit 更底层）
    guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
        print("❌ 无法获取窗口列表")
        return
    }

    // 查找微信窗口
    let wechatWindows = windowList.filter { info in
        let owner = info[kCGWindowOwnerName as String] as? String ?? ""
        return owner == "WeChat" || owner == "微信"
    }

    if wechatWindows.isEmpty {
        print("❌ CGWindowList 中未找到微信窗口")
        print("\n所有窗口 (前30个)：")
        for info in windowList.prefix(30) {
            let owner = info[kCGWindowOwnerName as String] as? String ?? "unknown"
            let name = info[kCGWindowName as String] as? String ?? "(无标题)"
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            let bounds = info[kCGWindowBounds as String] as? [String: Any]
            let w = bounds?["Width"] as? Int ?? 0
            let h = bounds?["Height"] as? Int ?? 0
            let sharing = info[kCGWindowSharingState as String] as? Int ?? -1
            let pid = info[kCGWindowOwnerPID as String] as? Int ?? 0
            print("  [\(pid)] \(owner) - \"\(name)\" layer=\(layer) \(w)x\(h) sharing=\(sharing)")
        }
        return
    }

    print("找到 \(wechatWindows.count) 个微信窗口：")
    for (i, info) in wechatWindows.enumerated() {
        let name = info[kCGWindowName as String] as? String ?? "(无标题)"
        let bounds = info[kCGWindowBounds as String] as? [String: Any]
        let w = bounds?["Width"] as? Int ?? 0
        let h = bounds?["Height"] as? Int ?? 0
        let layer = info[kCGWindowLayer as String] as? Int ?? -1
        let sharing = info[kCGWindowSharingState as String] as? Int ?? -1
        let windowID = info[kCGWindowNumber as String] as? Int ?? 0
        let alpha = info[kCGWindowAlpha as String] as? Double ?? -1
        let onscreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
        print("  [\(i)] ID=\(windowID) \"\(name)\" \(w)x\(h) layer=\(layer) sharing=\(sharing) alpha=\(alpha) onscreen=\(onscreen)")
    }

    // 尝试截取最大的窗口
    let mainWindow = wechatWindows
        .filter { info in
            let bounds = info[kCGWindowBounds as String] as? [String: Any]
            let w = bounds?["Width"] as? Double ?? 0
            let h = bounds?["Height"] as? Double ?? 0
            return w > 100 && h > 100
        }
        .max { a, b in
            let ba = a[kCGWindowBounds as String] as? [String: Any]
            let bb = b[kCGWindowBounds as String] as? [String: Any]
            let sa = (ba?["Width"] as? Double ?? 0) * (ba?["Height"] as? Double ?? 0)
            let sb = (bb?["Width"] as? Double ?? 0) * (bb?["Height"] as? Double ?? 0)
            return sa < sb
        }

    guard let target = mainWindow,
          let windowID = target[kCGWindowNumber as String] as? CGWindowID else {
        print("❌ 无合适的微信窗口可截取")
        return
    }

    let sharing = target[kCGWindowSharingState as String] as? Int ?? -1
    print("\n目标窗口 sharing state = \(sharing)")
    print("  (0=None/不可截, 1=ReadOnly, 2=ReadWrite)")

    // 方法1: 使用 CGWindowListCreateImage 截取单个窗口
    print("\n尝试方法1: CGWindowListCreateImage (单窗口)...")
    if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming]) {
        let url1 = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/wechat_cg_single.png")
        let dest1 = CGImageDestinationCreateWithURL(url1 as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest1, image, nil)
        CGImageDestinationFinalize(dest1)
        print("  ✅ 已保存: \(url1.path) (\(image.width)x\(image.height))")

        // 检查是否空白
        checkImageContent(image, label: "方法1")
    } else {
        print("  ❌ CGWindowListCreateImage 返回 nil")
    }

    // 方法2: 使用 CGWindowListCreateImage 截取屏幕上该区域（包含所有层）
    print("\n尝试方法2: CGWindowListCreateImage (区域截取，含所有窗口)...")
    if let bounds = target[kCGWindowBounds as String] as? [String: Any],
       let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
       let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double {
        let rect = CGRect(x: x, y: y, width: w, height: h)
        if let image = CGWindowListCreateImage(rect, .optionOnScreenBelowWindow, windowID, [.bestResolution]) {
            let url2 = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/wechat_cg_region.png")
            let dest2 = CGImageDestinationCreateWithURL(url2 as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(dest2, image, nil)
            CGImageDestinationFinalize(dest2)
            print("  ✅ 已保存: \(url2.path) (\(image.width)x\(image.height))")
            checkImageContent(image, label: "方法2")
        }
    }
}

func checkImageContent(_ image: CGImage, label: String) {
    guard let dataProvider = image.dataProvider, let data = dataProvider.data as Data? else { return }
    let bytesPerPixel = image.bitsPerPixel / 8
    var hasContent = false
    let step = max(1, data.count / (bytesPerPixel * 500)) * bytesPerPixel

    for i in stride(from: 0, to: min(data.count - bytesPerPixel, data.count), by: step) {
        if bytesPerPixel >= 3 {
            let r = data[i], g = data[i+1], b = data[i+2]
            let a: UInt8 = bytesPerPixel >= 4 ? data[i+3] : 255
            if a > 10 && !(r > 245 && g > 245 && b > 245) && !(r < 10 && g < 10 && b < 10) {
                hasContent = true
                break
            }
        }
    }
    print("  \(label) 内容检测: \(hasContent ? "✅ 有内容" : "⚠️ 空白/黑/白")")
}

main()
