#!/bin/bash
# 启动修改版微信（绕过 Gatekeeper 检查）
/Applications/WeChat.app/Contents/MacOS/WeChat &>/dev/null &
disown
exit 0
