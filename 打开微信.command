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
