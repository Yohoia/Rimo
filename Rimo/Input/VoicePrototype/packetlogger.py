"""Inspect one identified remote's incoming BLE notifications in a local .pklg."""
import argparse
from collections import Counter
import os
from pathlib import Path
import struct
import tempfile

from decode import decode


def records(path):
    with path.open("rb") as file:
        size = path.stat().st_size
        head = file.read(12)
        if len(head) != 12:
            raise ValueError("空文件或 PacketLogger 文件头不完整。")
        orders = []
        for order in (">", "<"):
            length, _, micros = struct.unpack(order + "III", head)
            if 9 <= length <= min(65544, size - 4) and micros < 1_000_000:
                orders.append(order)
        if len(orders) != 1:
            raise ValueError("无法识别 PacketLogger 文件头。请使用原始 .pklg 文件。")
        header = struct.Struct(orders[0] + "III")
        while head:
            if len(head) != header.size:
                raise ValueError("末尾记录不完整。请先停止采集再保存。")
            length, seconds, micros = header.unpack(head)
            if not 9 <= length <= 65544 or micros >= 1_000_000:
                raise ValueError("PacketLogger 记录长度或时间戳无效。")
            record = file.read(length - 8)
            if len(record) != length - 8:
                raise ValueError("PacketLogger 记录被截断。")
            yield seconds + micros / 1_000_000, record[0], record[1:]
            head = file.read(12)


def notifications(packets, *, handle, peer, stats):
    active = {handle} if handle is not None else set()
    partial = {}
    for time, kind, packet in packets:
        if kind == 0x01 and len(packet) >= 2 and len(packet) == packet[1] + 2:
            if packet[0] == 0x3E and len(packet) >= 14 and packet[2] in (0x01, 0x0A, 0x29) and packet[3] == 0:
                connected = int.from_bytes(packet[4:6], "little") & 0x0FFF
                partial.pop(connected, None)
                if peer is not None:
                    active.discard(connected)
                    if packet[8:14] == peer:
                        active.add(connected)
                        stats["matching_connections"] += 1
            elif packet[0] == 0x05 and len(packet) >= 6 and packet[2] == 0:
                disconnected = int.from_bytes(packet[3:5], "little") & 0x0FFF
                active.discard(disconnected)
                partial.pop(disconnected, None)
            continue
        if kind != 0x03 or len(packet) < 4:
            continue
        field, length = struct.unpack_from("<HH", packet)
        connection = field & 0x0FFF
        if connection not in active or len(packet) - 4 != length:
            continue
        stats["incoming_acl"] += 1
        boundary = (field >> 12) & 3
        if boundary == 1:
            if connection not in partial:
                continue
            expected, data = partial.pop(connection)
            data += packet[4:]
        else:
            partial.pop(connection, None)
            if length < 4:
                continue
            expected, channel = struct.unpack_from("<HH", packet, 4)
            if channel != 0x0004:
                continue
            data = packet[8:]
        if len(data) < expected:
            partial[connection] = (expected, data)
        elif len(data) == expected and len(data) >= 3 and data[0] == 0x1B:
            attribute = int.from_bytes(data[1:3], "little")
            yield time, attribute, data[3:]


def parse_peer(value):
    try:
        address = bytes.fromhex(value.replace(":", "").replace("-", ""))
        if len(address) == 6:
            return address[::-1]
    except ValueError:
        pass
    raise argparse.ArgumentTypeError("需要 6 字节的蓝牙设备地址。")


def main():
    number = lambda value: int(value, 0)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--handle", type=number, help="已确认属于遥控器的 HCI 连接句柄")
    target.add_argument("--peer", type=parse_peer, help="遥控器地址；采集需包含 LE 连接事件")
    parser.add_argument("--attribute", type=number, help="已确认的音频 ATT 特征句柄")
    parser.add_argument("--wav", type=Path, help="仅在指定音频特征后输出 WAV")
    args = parser.parse_args()
    if args.handle is not None and not 0 <= args.handle <= 0x0EFF:
        parser.error("HCI 连接句柄超出范围。")
    if args.attribute is not None and not 1 <= args.attribute <= 0xFFFF:
        parser.error("ATT 特征句柄超出范围。")
    if args.wav is not None and (args.attribute is None or args.wav.exists()):
        parser.error("输出 WAV 需要指定 --attribute，且输出文件不能已存在。")

    stats, counts, candidates = Counter(), Counter(), Counter()
    selected = []
    try:
        for _, attribute, payload in notifications(records(args.capture), handle=args.handle, peer=args.peer, stats=stats):
            counts[attribute] += 1
            # Known candidate layout only; this is not proof of an audio characteristic.
            if len(payload) < 6 or not 0 < payload[4] <= len(payload) - 5:
                continue
            candidates[attribute] += 1
            if args.wav is not None and attribute == args.attribute:
                selected.append(payload.hex())
        if args.peer is not None and not stats["matching_connections"]:
            raise ValueError("没有与遥控器地址相符的 LE 连接事件，本次采集无法判断语音是否出现。")
        print(f"该连接收到 {stats['incoming_acl']} 个 ACL 包、{sum(counts.values())} 个 ATT 通知。")
        print("ATT 句柄  通知数  符合候选帧布局数")
        for attribute, count in sorted(counts.items()):
            print(f"0x{attribute:04x}    {count:5}    {candidates[attribute]:5}")
        if args.wav is not None:
            if not selected:
                raise ValueError("指定的音频特征没有符合已知布局的帧，未生成 WAV。")
            with tempfile.TemporaryDirectory(prefix="Rimo-pklg-") as directory:
                source = Path(directory) / "frames.txt"
                source.write_text("\n".join(selected))
                libopus = os.environ.get("RIMO_OPUS_LIBRARY", "/opt/homebrew/lib/libopus.dylib")
                decode(source, args.wav, libopus, hid=False)
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
