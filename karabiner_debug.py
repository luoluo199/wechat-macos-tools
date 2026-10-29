#!/usr/bin/env python3
"""调试 Karabiner VirtualHIDDevice 连接"""

import socket
import struct
import time

SOCKET_PATH = "/Library/Application Support/org.pqrs/tmp/rootonly/karabiner_virtual_hid_device_service.sock"

def recv_exact(sock, n):
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("closed")
        buf.extend(chunk)
    return bytes(buf)

def read_frame(sock):
    header = recv_exact(sock, 4)
    body_size = struct.unpack(">I", header)[0]
    body = recv_exact(sock, body_size)
    return header + body

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(SOCKET_PATH)
sock.settimeout(5)
print("connected")

# 发心跳
sock.sendall(struct.pack(">I", 1) + bytes([0]))
print("heartbeat sent")

# 读一下有没有初始帧
try:
    raw = read_frame(sock)
    print(f"initial frame ({len(raw)} bytes): {raw.hex()}")
except socket.timeout:
    print("no initial frame (timeout)")

# 尝试不同的 protocol version
for ver in [7, 6, 5, 4, 3, 2, 1, 8, 9, 10]:
    # keyboard init: protocol_version(2 LE) + req_type(1) + params(24)
    params = struct.pack("<QQQ", 0x16c0, 0x27db, 33)  # vendor, product, country
    payload = struct.pack("<H", ver) + bytes([0]) + params  # req_type 0 = kb_init

    rid = ver  # use version as request id for easy identification
    body = bytes([4]) + struct.pack(">Q", rid) + payload  # type=4 (request)
    frame = struct.pack(">I", len(body)) + body

    sock.sendall(frame)
    print(f"\nsent kb_init with protocol_version={ver}, rid={rid}")

    try:
        raw = read_frame(sock)
        print(f"  response ({len(raw)} bytes): {raw.hex()}")
        # parse
        body_size = struct.unpack(">I", raw[:4])[0]
        body = raw[4:]
        msg_type = body[0]
        print(f"  msg_type={msg_type}", end="")
        if msg_type in (4, 5):
            resp_rid = struct.unpack(">Q", body[1:9])[0]
            resp_payload = body[9:]
            print(f", rid={resp_rid}, payload({len(resp_payload)})={resp_payload.hex()}")
            # parse pairs
            for i in range(0, len(resp_payload) - 1, 2):
                print(f"    type={resp_payload[i]} value={resp_payload[i+1]}")
        else:
            print(f", body={body[1:].hex()}")
    except socket.timeout:
        print("  no response (timeout)")

    # 也读取可能的服务端推送
    try:
        while True:
            raw = read_frame(sock)
            body = raw[4:]
            msg_type = body[0]
            print(f"  extra frame: msg_type={msg_type}, ({len(raw)} bytes): {raw.hex()}")
            if msg_type == 4:  # server request, need to respond
                resp_rid = struct.unpack(">Q", body[1:9])[0]
                resp_body = bytes([5]) + struct.pack(">Q", resp_rid)
                sock.sendall(struct.pack(">I", len(resp_body)) + resp_body)
                resp_payload = body[9:]
                print(f"    payload: {resp_payload.hex()}")
                for i in range(0, len(resp_payload) - 1, 2):
                    print(f"    type={resp_payload[i]} value={resp_payload[i+1]}")
    except socket.timeout:
        pass

    time.sleep(0.5)

sock.close()
print("\ndone")
