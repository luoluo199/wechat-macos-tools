# wechat-unsharingtype

解除 macOS 微信的防截图/防录屏保护，让系统截图、屏幕录制、以及 AI Agent 都能正常看到微信窗口。

## 问题

微信 macOS 版对窗口设置了 `NSWindow.sharingType = .none`，导致：

- 系统截图（⌘⇧3/4）截到微信窗口时显示**透明/穿透**
- 第三方截图工具截到**白屏**
- 屏幕录制看不到微信内容
- AI Agent（如 Claude Code）无法通过 ScreenCaptureKit 获取微信窗口画面

即使在 macOS 15+ 上，ScreenCaptureKit 仍然尊重 `sharingType = .none`，无法绕过。

## 原理

通过 DYLD 注入一个动态库到微信进程，使用 Objective-C 运行时 swizzle `NSWindow.setSharingType:` 方法，强制所有窗口的 `sharingType` 为 `readWrite`（值为 2），同时启动定时器每 2 秒修正已有窗口。

**不依赖特定微信版本号**，任何版本通用。

## 环境要求

- macOS（已在 macOS 27 / Darwin 27.0.0 上测试）
- Apple Silicon（arm64）
- Xcode Command Line Tools（需要 `clang`、`codesign`）
- [insert_dylib](https://github.com/tyilo/insert_dylib)（脚本会自动安装）

## 使用方法

### 安装（注入补丁）

```bash
sudo ./inject_v2.sh
```

脚本会自动：
1. 关闭微信
2. 备份原始二进制（`WeChat.backup`）
3. 编译 `unsharingtype.dylib`
4. 注入到微信主二进制
5. 仅重新签名主二进制（不影响其他组件）

### 启动微信

修改签名后，Finder/Dock 双击无法直接启动微信（Gatekeeper 拦截）。提供两种方案：

#### 方案一：启动器 App（推荐）

将修改后的微信移到隐藏位置，创建启动器 App 替代：

```bash
# 移动修改后的微信
sudo mv /Applications/WeChat.app /Applications/.WeChat_Patched.app

# 创建启动器 App
mkdir -p /Applications/WeChat.app/Contents/MacOS
mkdir -p /Applications/WeChat.app/Contents/Resources

# 复制图标
cp /Applications/.WeChat_Patched.app/Contents/Resources/AppIcon.icns \
   /Applications/WeChat.app/Contents/Resources/AppIcon.icns

# 创建启动脚本
cat > /Applications/WeChat.app/Contents/MacOS/run << 'EOF'
#!/bin/bash
open /path/to/打开微信.command
EOF
chmod +x /Applications/WeChat.app/Contents/MacOS/run

# 创建 Info.plist
cat > /Applications/WeChat.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>run</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.wechat-launcher</string>
    <key>CFBundleName</key>
    <string>WeChat</string>
    <key>CFBundleDisplayName</key>
    <string>微信</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
EOF
```

`打开微信.command` 内容：

```bash
#!/bin/bash
/Applications/.WeChat_Patched.app/Contents/MacOS/WeChat &>/dev/null &
disown

osascript -e '
delay 0.5
tell application "Terminal"
    repeat with w in windows
        try
            if name of w contains "打开微信" then
                close w
            end if
        end try
    end repeat
end tell
' &>/dev/null &

exit 0
```

效果：Applications 里只有一个微信图标，点击即可启动（会短暂闪一下终端窗口后自动关闭）。

#### 方案二：命令行启动

```bash
# 安装全局命令（一次性）
sudo cp start_wechat.command /usr/local/bin/wechat

# 之后在任何终端中输入即可启动微信
wechat
```

### 验证效果

注入成功后，微信日志中会显示：

```
[UnSharingType] 正在加载...
[UnSharingType] ✅ hook 成功
[UnSharingType] ✅ 定时修正已启动
```

微信窗口的 `sharingType` 会从 `0`（none）变为 `2`（readWrite）。

### 还原

```bash
sudo ./inject_v2.sh --restore
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `unsharingtype.m` | 核心 dylib 源码，swizzle NSWindow.setSharingType |
| `inject_v2.sh` | 注入/还原脚本 |
| `打开微信.command` | 微信启动脚本（启动器 App 用） |
| `start_wechat.command` | 微信启动脚本（命令行用） |
| `wrapper.m` | 启动器包装器源码（备用方案） |
| `wechat_unshare_daemon.swift` | 守护进程源码（跨进程方案，实测不生效） |
| `capture_v2.swift` | 诊断工具：检查微信窗口的 sharingType 状态 |
| `capture_v4.swift` | 截图工具：用 ScreenCaptureKit 截取微信窗口 |

## 注意事项

- 修改后微信签名会变化，可能影响 iCloud 同步等功能（可随时还原）
- 此工具仅供个人学习研究使用
- 每次微信更新后需要重新注入

## 致谢

- [fzlzjerry/wechat-antirecall](https://github.com/fzlzjerry/wechat-antirecall) — 思路参考
- [privateai0/macos-window-privacy-research](https://github.com/privateai0/macos-window-privacy-research) — macOS 窗口隐私 API 研究
- [tyilo/insert_dylib](https://github.com/tyilo/insert_dylib) — dylib 注入工具
