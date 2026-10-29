/*
 * cgevent_to_hid.dylib — CGEvent → Karabiner VirtualHID 代理
 *
 * 通过 DYLD_INSERT_LIBRARIES 注入到 Claude 进程，
 * 拦截 CGEventPost / CGEventSetIntegerValueField 等调用，
 * 将合成事件转发给 Karabiner VirtualHIDDevice，
 * 使微信无法区分自动化操作和真实硬件输入。
 *
 * 编译:
 *   clang -shared -framework Foundation -framework CoreGraphics \
 *     -arch arm64 -o cgevent_to_hid.dylib cgevent_to_hid.m
 *
 * 使用:
 *   先启动 karabiner_hid_daemon.py (root)，
 *   然后 DYLD_INSERT_LIBRARIES=./cgevent_to_hid.dylib 启动 Claude
 */

// 这个方案太复杂且脆弱，换用 daemon 方案
// 见 karabiner_hid_daemon.py
