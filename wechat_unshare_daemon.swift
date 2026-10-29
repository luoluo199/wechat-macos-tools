// wechat_unshare_daemon.swift
// 后台守护进程：监听微信进程，通过 Accessibility API 获取窗口 ID，
// 然后用私有 CGS API 强制修改 sharingType 为 readWrite。
// 不修改微信任何文件，微信可正常双击启动。

import Cocoa
import ApplicationServices

// 私有 CGS API 声明
typealias CGSConnectionID = UInt32
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSSetWindowSharingState")
func CGSSetWindowSharingState(_ cid: CGSConnectionID, _ wid: UInt32, _ state: UInt32) -> Int32

class WeChatUnshare: NSObject {
    var timer: Timer?
    let cid = CGSMainConnectionID()

    func start() {
        NSLog("[WeChatUnshare] 守护进程已启动，等待微信窗口...")
        timer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(fix), userInfo: nil, repeats: true)
        fix()
    }

    @objc func fix() {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return }

        var fixed = 0
        for info in windowList {
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "WeChat" || owner == "微信" else { continue }

            let sharing = info[kCGWindowSharingState as String] as? Int ?? -1
            let windowID = info[kCGWindowNumber as String] as? UInt32 ?? 0

            if sharing != 2 && windowID > 0 {
                let result = CGSSetWindowSharingState(cid, windowID, 2) // 2 = readWrite
                if result == 0 {
                    fixed += 1
                }
            }
        }

        if fixed > 0 {
            NSLog("[WeChatUnshare] ✅ 已修正 %d 个微信窗口的 sharingType", fixed)
        }
    }
}

// 初始化 NSApplication 以获取 CGS 连接
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let unshare = WeChatUnshare()
unshare.start()

app.run()
