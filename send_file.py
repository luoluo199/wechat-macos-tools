#!/usr/bin/env python3
"""
通过剪贴板+AX API 向微信发送文件，不使用接管模式。

用法:
    python3 send_file.py /path/to/file.jpg
    python3 send_file.py /path/to/file1.jpg /path/to/file2.png

原理:
    1. 用 NSPasteboard 把文件写入剪贴板（作为 NSURL 文件引用）
    2. 通过 System Events 聚焦微信
    3. 通过 System Events 发送 Cmd+V 粘贴
    4. 通过 System Events 发送回车发送

全程走辅助功能通道，不产生全局鼠标事件，不触发微信的接管检测。
"""

import subprocess
import sys
import time
import os


def copy_files_to_clipboard(file_paths):
    """用 NSPasteboard API 把文件写入剪贴板"""
    url_lines = "\n".join(
        f'set f{i} to current application\'s NSURL\'s fileURLWithPath:"{os.path.abspath(p)}"'
        for i, p in enumerate(file_paths)
    )
    file_refs = ", ".join(f"f{i}" for i in range(len(file_paths)))

    script = f'''
    use framework "AppKit"
    set pb to current application's NSPasteboard's generalPasteboard()
    pb's clearContents()
    {url_lines}
    pb's writeObjects:{{{file_refs}}}
    '''
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"❌ 剪贴板设置失败: {result.stderr}")
        return False
    print(f"✅ 已复制 {len(file_paths)} 个文件到剪贴板")
    return True


def paste_and_send():
    """通过 System Events 在微信中粘贴并发送"""
    script = '''
    tell application "System Events"
        tell process "WeChat"
            set frontmost to true
        end tell
        delay 0.5
        keystroke "v" using command down
        delay 1.0
        tell process "WeChat"
            key code 36
        end tell
    end tell
    '''
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"❌ 粘贴/发送失败: {result.stderr}")
        return False
    print("✅ 已粘贴并发送")
    return True


def main():
    if len(sys.argv) < 2:
        print("用法: python3 send_file.py <文件路径> [文件路径2] ...")
        print("")
        print("示例:")
        print("  python3 send_file.py ~/Desktop/photo.jpg")
        print("  python3 send_file.py file1.png file2.png")
        sys.exit(1)

    file_paths = sys.argv[1:]

    # 检查文件存在
    for p in file_paths:
        abs_p = os.path.abspath(p)
        if not os.path.exists(abs_p):
            print(f"❌ 文件不存在: {abs_p}")
            sys.exit(1)

    print(f"📎 发送 {len(file_paths)} 个文件到微信当前聊天")

    if not copy_files_to_clipboard(file_paths):
        sys.exit(1)

    time.sleep(0.3)
    if not paste_and_send():
        sys.exit(1)

    print("✅ 完成")


if __name__ == "__main__":
    main()
