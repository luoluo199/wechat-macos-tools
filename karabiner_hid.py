#!/usr/bin/env python3
"""
Karabiner VirtualHIDDevice 客户端
通过 Karabiner 的虚拟 HID 设备发送键盘和鼠标事件，
使事件在 macOS HID 子系统层面与真实硬件输入无法区分。

需要 root 权限运行。需要 Karabiner-Elements 已安装并运行。

用法:
    sudo python3 karabiner_hid.py                # 运行测试
    sudo python3 karabiner_hid.py type "Hello"    # 打字
    sudo python3 karabiner_hid.py click           # 左键点击（当前鼠标位置）
"""

import socket
import struct
import threading
import time
import sys

SOCKET_PATH = "/Library/Application Support/org.pqrs/tmp/rootonly/karabiner_virtual_hid_device_service.sock"

# ── 传输层 ──

MSG_HEARTBEAT = 0
MSG_REQUEST = 4
MSG_RESPONSE = 5


def _recv_exact(sock, n):
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("Socket closed")
        buf.extend(chunk)
    return bytes(buf)


def make_heartbeat():
    return struct.pack(">I", 1) + bytes([MSG_HEARTBEAT])


def make_request(request_id, payload):
    body_size = 1 + 8 + len(payload)
    return struct.pack(">I", body_size) + bytes([MSG_REQUEST]) + struct.pack(">Q", request_id) + payload


def make_response(request_id, payload=b""):
    body_size = 1 + 8 + len(payload)
    return struct.pack(">I", body_size) + bytes([MSG_RESPONSE]) + struct.pack(">Q", request_id) + payload


def read_frame(sock):
    header = _recv_exact(sock, 4)
    body_size = struct.unpack(">I", header)[0]
    body = _recv_exact(sock, body_size)
    msg_type = body[0]
    if msg_type in (MSG_REQUEST, MSG_RESPONSE):
        request_id = struct.unpack(">Q", body[1:9])[0]
        return msg_type, request_id, body[9:]
    return msg_type, None, body[1:]


# ── 应用层 ──

PROTOCOL_VERSION = 7

REQ_KB_INIT = 0
REQ_KB_TERMINATE = 1
REQ_POINTING_INIT = 3
REQ_POINTING_TERMINATE = 4
REQ_POST_KEYBOARD = 6
REQ_POST_CONSUMER = 7
REQ_POST_POINTING = 11

RESP_KB_READY = 4
RESP_POINTING_READY = 5

# Modifier flags
MOD_L_CTRL = 0x01
MOD_L_SHIFT = 0x02
MOD_L_OPT = 0x04
MOD_L_CMD = 0x08
MOD_R_CTRL = 0x10
MOD_R_SHIFT = 0x20
MOD_R_OPT = 0x40
MOD_R_CMD = 0x80

# HID usage codes (USB HID Keyboard/Keypad page)
HID_KEYS = {
    'a': 0x04, 'b': 0x05, 'c': 0x06, 'd': 0x07, 'e': 0x08, 'f': 0x09,
    'g': 0x0a, 'h': 0x0b, 'i': 0x0c, 'j': 0x0d, 'k': 0x0e, 'l': 0x0f,
    'm': 0x10, 'n': 0x11, 'o': 0x12, 'p': 0x13, 'q': 0x14, 'r': 0x15,
    's': 0x16, 't': 0x17, 'u': 0x18, 'v': 0x19, 'w': 0x1a, 'x': 0x1b,
    'y': 0x1c, 'z': 0x1d,
    '1': 0x1e, '2': 0x1f, '3': 0x20, '4': 0x21, '5': 0x22, '6': 0x23,
    '7': 0x24, '8': 0x25, '9': 0x26, '0': 0x27,
    '\n': 0x28, '\r': 0x28,  # Return
    '\x1b': 0x29,  # Escape
    '\b': 0x2a,    # Backspace
    '\t': 0x2b,    # Tab
    ' ': 0x2c,     # Space
    '-': 0x2d, '=': 0x2e, '[': 0x2f, ']': 0x30, '\\': 0x31,
    ';': 0x33, "'": 0x34, '`': 0x35, ',': 0x36, '.': 0x37, '/': 0x38,
}

# 需要 Shift 的字符 → (对应的基础字符)
SHIFT_KEYS = {
    'A': 'a', 'B': 'b', 'C': 'c', 'D': 'd', 'E': 'e', 'F': 'f',
    'G': 'g', 'H': 'h', 'I': 'i', 'J': 'j', 'K': 'k', 'L': 'l',
    'M': 'm', 'N': 'n', 'O': 'o', 'P': 'p', 'Q': 'q', 'R': 'r',
    'S': 's', 'T': 't', 'U': 'u', 'V': 'v', 'W': 'w', 'X': 'x',
    'Y': 'y', 'Z': 'z',
    '!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6',
    '&': '7', '*': '8', '(': '9', ')': '0',
    '_': '-', '+': '=', '{': '[', '}': ']', '|': '\\',
    ':': ';', '"': "'", '~': '`', '<': ',', '>': '.', '?': '/',
}


def _app_payload(req_type, data=b""):
    return struct.pack("<H", PROTOCOL_VERSION) + bytes([req_type]) + data


def _kb_params(vendor_id=0x16c0, product_id=0x27db, country_code=33):
    return struct.pack("<QQQ", vendor_id, product_id, country_code)


def _kb_report(modifiers=0, keys=None):
    keys = keys or []
    arr = [0] * 32
    for i, k in enumerate(keys[:32]):
        arr[i] = k
    return bytes([1, modifiers, 0]) + struct.pack("<32H", *arr)


def _pointing_report(buttons=0, x=0, y=0, vwheel=0, hwheel=0):
    return struct.pack("<I", buttons) + struct.pack("bbbb", x, y, vwheel, hwheel)


def _parse_response(payload):
    result = {}
    for i in range(0, len(payload) - 1, 2):
        result[payload[i]] = bool(payload[i + 1])
    return result


# ── 客户端 ──

class KarabinerHID:
    def __init__(self):
        self.sock = None
        self._rid = 1
        self._lock = threading.Lock()
        self._running = False
        self._pending = {}
        self.keyboard_ready = False
        self.pointing_ready = False

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(SOCKET_PATH)
        self._running = True
        threading.Thread(target=self._reader, daemon=True).start()
        threading.Thread(target=self._heartbeat, daemon=True).start()

    def _next_rid(self):
        with self._lock:
            r = self._rid
            self._rid += 1
            return r

    def _send_req(self, payload, wait=True, timeout=5.0):
        rid = self._next_rid()
        if wait:
            evt = threading.Event()
            self._pending[rid] = {"event": evt, "result": None}
        self.sock.sendall(make_request(rid, payload))
        if wait:
            evt.wait(timeout)
            return self._pending.pop(rid, {}).get("result", {})

    def _reader(self):
        while self._running:
            try:
                msg_type, rid, payload = read_frame(self.sock)
            except Exception:
                break
            if msg_type == MSG_HEARTBEAT:
                continue
            elif msg_type == MSG_RESPONSE:
                parsed = _parse_response(payload)
                self._update(parsed)
                if rid in self._pending:
                    self._pending[rid]["result"] = parsed
                    self._pending[rid]["event"].set()
            elif msg_type == MSG_REQUEST:
                parsed = _parse_response(payload)
                self._update(parsed)
                try:
                    self.sock.sendall(make_response(rid))
                except Exception:
                    break

    def _update(self, parsed):
        if RESP_KB_READY in parsed:
            self.keyboard_ready = parsed[RESP_KB_READY]
        if RESP_POINTING_READY in parsed:
            self.pointing_ready = parsed[RESP_POINTING_READY]

    def _heartbeat(self):
        while self._running:
            try:
                self.sock.sendall(make_heartbeat())
            except Exception:
                break
            time.sleep(5)

    def init_keyboard(self, country_code=33):
        resp = self._send_req(_app_payload(REQ_KB_INIT, _kb_params(country_code=country_code)))
        deadline = time.time() + 10
        while not self.keyboard_ready and time.time() < deadline:
            time.sleep(0.1)
        if not self.keyboard_ready:
            raise RuntimeError("Virtual keyboard failed to initialize")
        return resp

    def init_pointing(self):
        resp = self._send_req(_app_payload(REQ_POINTING_INIT))
        deadline = time.time() + 10
        while not self.pointing_ready and time.time() < deadline:
            time.sleep(0.1)
        if not self.pointing_ready:
            raise RuntimeError("Virtual pointing device failed to initialize")
        return resp

    def key_down(self, modifiers=0, keys=None):
        report = _kb_report(modifiers, keys)
        self._send_req(_app_payload(REQ_POST_KEYBOARD, report), wait=False)

    def key_up(self):
        report = _kb_report()
        self._send_req(_app_payload(REQ_POST_KEYBOARD, report), wait=False)

    def key_press(self, modifiers=0, keys=None, duration=0.02):
        self.key_down(modifiers, keys)
        time.sleep(duration)
        self.key_up()

    def type_char(self, ch, delay=0.03):
        if ch in SHIFT_KEYS:
            base = SHIFT_KEYS[ch]
            code = HID_KEYS.get(base)
            if code:
                self.key_press(MOD_L_SHIFT, [code])
        elif ch in HID_KEYS:
            self.key_press(0, [HID_KEYS[ch]])
        else:
            # 不支持的字符跳过
            return
        time.sleep(delay)

    def type_string(self, text, delay=0.03):
        for ch in text:
            self.type_char(ch, delay)

    def mouse_move(self, dx, dy, steps=None):
        """相对移动鼠标。dx/dy 可以是任意整数，会自动分多次发送。"""
        if steps is None:
            steps = max(abs(dx), abs(dy)) // 80 + 1
        sx = dx / steps
        sy = dy / steps
        for i in range(steps):
            x = int(round(sx * (i + 1))) - int(round(sx * i))
            y = int(round(sy * (i + 1))) - int(round(sy * i))
            x = max(-128, min(127, x))
            y = max(-128, min(127, y))
            report = _pointing_report(x=x, y=y)
            self._send_req(_app_payload(REQ_POST_POINTING, report), wait=False)
            time.sleep(0.005)

    def click(self, button=1, duration=0.05):
        btn_mask = 1 << (button - 1)
        report = _pointing_report(buttons=btn_mask)
        self._send_req(_app_payload(REQ_POST_POINTING, report), wait=False)
        time.sleep(duration)
        report = _pointing_report(buttons=0)
        self._send_req(_app_payload(REQ_POST_POINTING, report), wait=False)

    def scroll(self, dy, dx=0):
        dy = max(-128, min(127, dy))
        dx = max(-128, min(127, dx))
        report = _pointing_report(vwheel=dy, hwheel=dx)
        self._send_req(_app_payload(REQ_POST_POINTING, report), wait=False)

    def cmd_v(self):
        """Cmd+V 粘贴"""
        self.key_press(MOD_L_CMD, [HID_KEYS['v']])

    def cmd_c(self):
        """Cmd+C 复制"""
        self.key_press(MOD_L_CMD, [HID_KEYS['c']])

    def cmd_a(self):
        """Cmd+A 全选"""
        self.key_press(MOD_L_CMD, [HID_KEYS['a']])

    def enter(self):
        """回车"""
        self.key_press(0, [HID_KEYS['\n']])

    def close(self):
        self._running = False
        try:
            self._send_req(_app_payload(REQ_KB_TERMINATE), wait=False)
            self._send_req(_app_payload(REQ_POINTING_TERMINATE), wait=False)
        except Exception:
            pass
        if self.sock:
            self.sock.close()


def main():
    hid = KarabinerHID()
    print(f"连接 {SOCKET_PATH} ...")
    hid.connect()
    print("已连接")

    print("初始化虚拟键盘...")
    hid.init_keyboard()
    print("✅ 虚拟键盘就绪")

    print("初始化虚拟鼠标...")
    hid.init_pointing()
    print("✅ 虚拟鼠标就绪")

    if len(sys.argv) >= 3 and sys.argv[1] == "type":
        text = sys.argv[2]
        print(f"输入: {text}")
        time.sleep(1)  # 给用户时间聚焦目标窗口
        hid.type_string(text)
        print("✅ 完成")
    elif len(sys.argv) >= 2 and sys.argv[1] == "click":
        print("左键点击")
        hid.click()
        print("✅ 完成")
    else:
        # 默认测试：等 2 秒后打字
        print("2 秒后将输入测试文字，请聚焦到文本编辑器...")
        time.sleep(2)
        hid.type_string("Hello from Karabiner VirtualHID!")
        hid.enter()
        print("✅ 测试完成")

    hid.close()


if __name__ == "__main__":
    main()
