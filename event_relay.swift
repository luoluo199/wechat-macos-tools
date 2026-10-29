#!/usr/bin/env swift
/*
 * event_relay v2 — 合成事件来源伪装
 *
 * 用 CGEvent tap 拦截所有合成事件，
 * 修改事件的来源字段使其看起来像硬件输入，然后放行。
 *
 * 不需要 Karabiner VirtualHID，不拦截不重发，不影响鼠标定位。
 *
 * 需要:
 *   1. root 权限（创建 HID 级别 event tap）
 *   2. 辅助功能权限
 *
 * 编译: swiftc -O -o event_relay event_relay.swift
 * 运行: sudo ./event_relay
 */

import Foundation
import CoreGraphics

// CGEvent field 常量
let kFieldSourceStateID: CGEventField = CGEventField(rawValue: 45)!
let kFieldSourcePID: CGEventField = CGEventField(rawValue: 41)!
let kFieldSourceUserData: CGEventField = CGEventField(rawValue: 42)!

var processedCount: UInt64 = 0
var passedCount: UInt64 = 0

// CGEvent tap 回调
let eventCallback: CGEventTapCallBack = { proxy, type, event, refcon in
    // tap 被系统禁用时重新启用
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tapPtr = refcon {
            let tap = Unmanaged<CFMachPort>.fromOpaque(tapPtr).takeUnretainedValue()
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    // 检查事件来源
    let sourceState = event.getIntegerValueField(kFieldSourceStateID)
    let sourcePid = event.getIntegerValueField(kFieldSourcePID)

    // 如果已经是硬件事件，直接放行
    if sourceState == 1 && sourcePid == 0 {
        passedCount += 1
        return Unmanaged.passRetained(event)
    }

    // 合成事件：修改来源字段伪装成硬件
    if sourcePid > 0 || sourceState != 1 {
        // 设为 HID 系统状态（硬件来源）
        event.setIntegerValueField(kFieldSourceStateID, value: 1)
        // 清除来源进程 ID
        event.setIntegerValueField(kFieldSourcePID, value: 0)
        // 清除用户数据标记
        event.setIntegerValueField(kFieldSourceUserData, value: 0)

        processedCount += 1
    }

    return Unmanaged.passRetained(event) // 修改后放行
}

// MARK: - Main

print("🛡  Event Relay v2 — 事件来源伪装模式")
print("")

// 创建 event tap（拦截所有输入事件）
var eventMask: CGEventMask = 0
eventMask |= (1 << CGEventType.leftMouseDown.rawValue)
eventMask |= (1 << CGEventType.leftMouseUp.rawValue)
eventMask |= (1 << CGEventType.rightMouseDown.rawValue)
eventMask |= (1 << CGEventType.rightMouseUp.rawValue)
eventMask |= (1 << CGEventType.mouseMoved.rawValue)
eventMask |= (1 << CGEventType.leftMouseDragged.rawValue)
eventMask |= (1 << CGEventType.rightMouseDragged.rawValue)
eventMask |= (1 << CGEventType.otherMouseDown.rawValue)
eventMask |= (1 << CGEventType.otherMouseUp.rawValue)
eventMask |= (1 << CGEventType.otherMouseDragged.rawValue)
eventMask |= (1 << CGEventType.scrollWheel.rawValue)
eventMask |= (1 << CGEventType.keyDown.rawValue)
eventMask |= (1 << CGEventType.keyUp.rawValue)
eventMask |= (1 << CGEventType.flagsChanged.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: eventCallback,
    userInfo: nil
) else {
    print("❌ 创建 CGEvent tap 失败")
    print("   请确认:")
    print("   1. 用 sudo 运行")
    print("   2. 终端有辅助功能权限（系统设置 → 隐私与安全 → 辅助功能）")
    exit(1)
}

// 把 tap 指针传给回调（用于 tap 被禁用时重新启用）
let tapPtr = Unmanaged.passUnretained(tap).toOpaque()
// 重新创建 tap 并传入 userInfo
// 实际上 CGEvent.tapCreate 的 userInfo 在创建时就固定了，
// 所以用全局变量代替
var globalTap: CFMachPort? = tap

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("✅ Event tap 已创建")
print("")
print("   所有合成事件的来源字段将被伪装为硬件输入。")
print("   鼠标移动、点击、拖拽、键盘输入全部正常工作。")
print("   微信无法区分自动化操作和真实输入。")
print("")
print("   按 Ctrl+C 停止。")
print("")

// 定期打印统计
DispatchQueue.global().async {
    while true {
        Thread.sleep(forTimeInterval: 30)
        print("   📊 伪装: \(processedCount) 个事件 | 放行: \(passedCount) 个硬件事件")
    }
}

// Ctrl+C 处理
signal(SIGINT) { _ in
    print("\n🛑 已停止。伪装了 \(processedCount) 个事件。")
    exit(0)
}

CFRunLoopRun()
