# wechat-macos-tools

macOS 微信自动化工具集：解决 AI Agent（Claude、GPT 等）操作微信时遇到的截屏透明和强制退出登录问题。

## 问题

在 macOS 上用 AI Agent 操作微信会遇到两个问题：

1. **截屏透明**：微信设置 `NSWindow.sharingType = .none`，系统截图、ScreenCaptureKit、AI Agent 全部截到透明/白屏
2. **强制退出登录**：微信检测到自动化操作（模拟鼠标键盘、拖拽文件等）后，强制用户下线

## 解决方案

### 1. 防截屏透明 — unsharingtype.dylib

通过 DYLD 注入动态库到微信进程，swizzle `NSWindow.setSharingType:` 强制所有窗口为 `readWrite`。

**安装：**

```bash
# 需要 insert_dylib（脚本会自动安装）和 Xcode Command Line Tools
sudo ./inject_v2.sh
```

脚本会自动：备份原始二进制 → 编译 dylib → 注入 → 重签名。

**启动微信：**

修改签名后 Finder 双击无法启动（Gatekeeper 拦截），需要用命令行：

```bash
/Applications/.WeChat_Patched.app/Contents/MacOS/WeChat &>/dev/null & disown
```

或使用提供的启动器（见 README 底部「启动器 App」部分）。

### 2. 防退出登录 — 后台操作方式

**核心发现：** 微信检测的是「接管模式」（全屏控制、CGEvent 模拟鼠标键盘），不是所有自动化。通过辅助功能 API（AX API / System Events）的后台操作不会触发检测。

| 操作 | 安全方式 | 危险方式 |
|---|---|---|
| 看消息 | AX API 截图 / app_screenshot | — |
| 打字发文字 | System Events keystroke | — |
| 发文件/图片 | **send_file.py**（见下） | ❌ 接管模式拖拽、文件选择器 |
| 点击界面 | AX API app_click | ❌ 接管模式 CGEvent 点击 |

### 3. 后台发文件 — send_file.py

通过剪贴板 + System Events 发送文件，绕过接管模式：

```bash
# 发送单个文件
python3 send_file.py /path/to/photo.jpg

# 发送多个文件
python3 send_file.py file1.png file2.pdf file3.mp4
```

**原理：**
1. 用 NSPasteboard 把文件写入剪贴板（NSURL 文件引用格式）
2. 通过 System Events 聚焦微信窗口
3. 发送 Cmd+V 粘贴
4. 发送回车发送

**注意：**
- 运行前确保微信已打开且已选中目标聊天窗口
- 脚本会把微信切到前台，剪贴板会被覆盖
- 不要在正在其他应用打字时运行

### 4. Karabiner VirtualHID 客户端 — karabiner_hid.py（实验性）

通过 Karabiner-Elements 的 VirtualHIDDevice 发送硬件级键盘/鼠标事件，macOS HID 子系统层面与真实硬件输入无法区分。

```bash
# 需要 root 权限和 Karabiner-Elements 已安装
sudo python3 karabiner_hid.py              # 测试
sudo python3 karabiner_hid.py type "Hello" # 打字
sudo python3 karabiner_hid.py click        # 点击
```

**验证结果：** 键盘输入通过 VirtualHID 发送不会被微信检测。但鼠标操作（尤其是拖拽）仍可能触发检测，因为微信可能做行为模式分析。

### 5. CGEvent 中继 — event_relay.swift（实验性）

拦截合成事件并修改来源字段或通过 VirtualHID 重发。

```bash
swiftc -O -o event_relay event_relay.swift
sudo ./event_relay
```

**验证结果：** 修改 CGEvent 来源字段对微信检测无效，可能是只读字段或微信用了其他检测方式。仅供参考。

## 实测结论（2026-10-28）

在 macOS 27.0.1 + 微信 4.1.15 上测试：

- ✅ 后台方式（AX API / System Events）操作微信：发了几十条文字，**从未被踢**
- ✅ send_file.py 发送图片：成功，**未被踢**
- ✅ Karabiner VirtualHID 键盘输入：成功，**未被踢**
- ❌ 接管模式操作微信：5 次全部被踢，其中 4 次涉及文件操作
- ❌ fishhook CGEventGetIntegerValueField：无效
- ❌ CGEvent tap 修改来源字段：无效

## 尝试过但无效的方案

| 方案 | 原理 | 结果 |
|---|---|---|
| antirobot.m (fishhook) | 在微信进程内 hook CGEventGetIntegerValueField 返回硬件来源 | ❌ 微信仍检测到 |
| event_relay v2 (字段修改) | CGEvent tap 修改事件的 sourceStateID/sourcePID 字段 | ❌ 字段可能只读 |
| event_relay v1 (VirtualHID 重发) | 拦截合成事件 + Karabiner VirtualHID 重发 | ❌ 鼠标定位错乱 |
| 升级微信 4.2.0 用 AX API | 期望新版暴露 AX 输入控件 | ❌ AX 树仍不暴露 |

## 环境要求

- macOS（已在 macOS 27 / Apple Silicon 上测试）
- Xcode Command Line Tools（`clang`、`codesign`、`swiftc`）
- [insert_dylib](https://github.com/tyilo/insert_dylib)（inject 脚本会自动安装）
- Python 3（send_file.py）
- Karabiner-Elements（仅 karabiner_hid.py 需要）

## 文件说明

| 文件 | 说明 |
|---|---|
| `unsharingtype.m` | 防截屏 dylib 源码，swizzle NSWindow.setSharingType |
| `send_file.py` | 后台发文件脚本（剪贴板 + System Events） |
| `karabiner_hid.py` | Karabiner VirtualHIDDevice 客户端 |
| `karabiner_debug.py` | Karabiner 连接调试工具 |
| `event_relay.swift` | CGEvent 中继（实验性） |
| `antirobot.m` | CGEvent fishhook（实验性，无效） |
| `inject_v2.sh` | 微信注入/还原脚本 |
| `inject.sh` | 微信注入脚本（旧版，用 --deep 签名） |
| `patch_wechat.sh` | dylib 更新脚本 |
| `capture_v4.swift` | ScreenCaptureKit 截图工具 |
| `capture_v2.swift` | 微信窗口 sharingType 诊断工具 |
| `打开微信.command` | 微信启动脚本（启动器 App 用） |
| `start_wechat.command` | 微信启动脚本（命令行用） |

## 启动器 App

修改签名后的微信无法通过 Finder 双击启动。可以创建一个启动器 App 替代：

```bash
# 移动修改后的微信
sudo mv /Applications/WeChat.app /Applications/.WeChat_Patched.app

# 创建启动器
mkdir -p /Applications/WeChat.app/Contents/{MacOS,Resources}
cp /Applications/.WeChat_Patched.app/Contents/Resources/AppIcon.icns \
   /Applications/WeChat.app/Contents/Resources/

cat > /Applications/WeChat.app/Contents/MacOS/run << 'EOF'
#!/bin/bash
/Applications/.WeChat_Patched.app/Contents/MacOS/WeChat &>/dev/null &
disown
EOF
chmod +x /Applications/WeChat.app/Contents/MacOS/run

cat > /Applications/WeChat.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>run</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.local.wechat-launcher</string>
    <key>CFBundleName</key><string>WeChat</string>
    <key>CFBundleDisplayName</key><string>微信</string>
    <key>CFBundlePackageType</key><string>APPL</string>
</dict>
</plist>
EOF
```

## 还原

```bash
sudo ./inject_v2.sh --restore
```

## 注意事项

- 修改签名后可能影响 iCloud 同步、Handoff 接力等功能（可随时还原）
- 每次微信更新后需要重新注入
- 此工具仅供个人学习研究使用

## 致谢

- [tyilo/insert_dylib](https://github.com/tyilo/insert_dylib) — dylib 注入工具
- [pqrs-org/Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) — 虚拟 HID 设备驱动
