// capture_v2.swift
// 1. 用 CGWindowListCopyWindowInfo 检查微信窗口 sharingState
// 2. 用 ScreenCaptureKit 列出可见窗口（看微信是否被排除）
// 3. 尝试用全屏截图截取微信区域

import Cocoa
import ScreenCaptureKit

// ===== Part 1: CGWindowList 检查 =====
func checkCGWindows() {
    print("===== CGWindowListCopyWindowInfo =====")
    guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
        print("❌ 无法获取窗口列表")
        return
    }

    let wechatWindows = windowList.filter { info in
        let pid = info[kCGWindowOwnerPID as String] as? Int ?? 0
        let owner = info[kCGWindowOwnerName as String] as? String ?? ""
        return owner == "WeChat" || owner == "微信"
    }

    if wechatWindows.isEmpty {
        print("❌ CGWindowList 中无微信窗口")
        // 用 PID 再查一次
        let wechatPids = getPids(name: "WeChat")
        print("微信 PID: \(wechatPids)")
        let byPid = windowList.filter { info in
            let pid = info[kCGWindowOwnerPID as String] as? Int ?? 0
            return wechatPids.contains(pid)
        }
        if !byPid.isEmpty {
            print("通过 PID 找到 \(byPid.count) 个窗口：")
            for info in byPid {
                printWindowInfo(info)
            }
        }
    } else {
        print("找到 \(wechatWindows.count) 个微信窗口：")
        for info in wechatWindows {
            printWindowInfo(info)
        }
    }
}

func getPids(name: String) -> [Int] {
    let apps = NSWorkspace.shared.runningApplications.filter {
        $0.localizedName == name || $0.bundleIdentifier == "com.tencent.xinWeChat"
    }
    return apps.map { Int($0.processIdentifier) }
}

func printWindowInfo(_ info: [String: Any]) {
    let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
    let name = info[kCGWindowName as String] as? String ?? "(无标题)"
    let layer = info[kCGWindowLayer as String] as? Int ?? -1
    let bounds = info[kCGWindowBounds as String] as? [String: Any]
    let w = bounds?["Width"] as? Double ?? 0
    let h = bounds?["Height"] as? Double ?? 0
    let sharing = info[kCGWindowSharingState as String] as? Int ?? -1
    let pid = info[kCGWindowOwnerPID as String] as? Int ?? 0
    let windowID = info[kCGWindowNumber as String] as? Int ?? 0
    let alpha = info[kCGWindowAlpha as String] as? Double ?? -1
    let onscreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
    print("  ID=\(windowID) PID=\(pid) \"\(name)\" \(Int(w))x\(Int(h)) layer=\(layer) sharing=\(sharing) alpha=\(alpha) onscreen=\(onscreen)")
}

// ===== Part 2: ScreenCaptureKit 检查 =====
@available(macOS 12.3, *)
func checkSCK() async {
    print("\n===== ScreenCaptureKit =====")
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        let wechatWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == "com.tencent.xinWeChat"
        }

        let wechatApps = content.applications.filter {
            $0.bundleIdentifier == "com.tencent.xinWeChat"
        }

        print("SCK 应用列表中微信: \(wechatApps.count) 个")
        for app in wechatApps {
            print("  \(app.applicationName) [\(app.bundleIdentifier)]")
        }

        print("SCK 窗口列表中微信: \(wechatWindows.count) 个")
        for w in wechatWindows {
            print("  ID=\(w.windowID) \"\(w.title ?? "(无标题)")\" \(Int(w.frame.width))x\(Int(w.frame.height)) layer=\(w.windowLayer)")
        }

        if wechatWindows.isEmpty && !wechatApps.isEmpty {
            print("\n⚠️ SCK 能看到微信应用，但看不到任何窗口")
            print("→ 微信窗口被完全排除在 ScreenCaptureKit 之外")
        }

        // 尝试全屏截图
        print("\n尝试全屏截图（包含所有内容）...")
        if let display = content.displays.first {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(display.width) * 2
            config.height = Int(display.height) * 2

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/wechat_fullscreen.png")
            let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            print("✅ 全屏截图已保存: \(url.path)")
        }

    } catch {
        print("❌ SCK 错误: \(error)")
    }
}

// ===== Main =====
checkCGWindows()

if #available(macOS 12.3, *) {
    let sem = DispatchSemaphore(value: 0)
    Task {
        await checkSCK()
        sem.signal()
    }
    sem.wait()
}
