"""Decode the experimental A2540 frame layout into a local mono WAV."""
import ctypes as c
import os
from pathlib import Path
import sys
import wave

RATE = 48_000


def decode(source: Path, output: Path, libopus: str, *, hid: bool) -> None:
    lib = c.CDLL(libopus)
    lib.opus_decoder_create.argtypes = [c.c_int32, c.c_int, c.POINTER(c.c_int)]
    lib.opus_decoder_create.restype = c.c_void_p
    lib.opus_decoder_destroy.argtypes = [c.c_void_p]
    lib.opus_decoder_destroy.restype = None
    lib.opus_decode.argtypes = [c.c_void_p, c.c_char_p, c.c_int32, c.POINTER(c.c_int16), c.c_int, c.c_int]
    lib.opus_decode.restype = c.c_int
    error = c.c_int()
    decoder = lib.opus_decoder_create(RATE, 1, c.byref(error))
    if not decoder:
        raise ValueError(f"无法初始化 Opus：{error.value}")

    pcm = bytearray()
    buffer = (c.c_int16 * 5760)()
    previous = None
    accepted = rejected = 0
    try:
        for line in source.read_text().splitlines():
            raw = bytes.fromhex(line)
            if hid:
                if raw[:1] != b"\xff":
                    rejected += 1
                    continue
                raw = raw[1:]
            if len(raw) < 6 or not 0 < raw[4] <= len(raw) - 5:
                rejected += 1
                continue
            sequence = int.from_bytes(raw[2:4], "little")
            if sequence == previous:
                continue
            packet = raw[5:5 + raw[4]]
            count = lib.opus_decode(decoder, packet, len(packet), buffer, len(buffer), 0)
            if count <= 0:
                rejected += 1
                continue
            previous = sequence
            accepted += 1
            pcm.extend(c.string_at(buffer, count * 2))
    finally:
        lib.opus_decoder_destroy(decoder)

    if not pcm:
        raise ValueError(f"没有能解码的音频帧（跳过 {rejected} 份报文），未生成 WAV。")
    with wave.open(str(output), "wb") as wav:
        wav.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        wav.writeframes(pcm)
    print(f"解码 {accepted} 帧，跳过 {rejected} 份报文，{len(pcm) / (2 * RATE):.2f} 秒：{output}")


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in ("hid", "payload"):
        sys.exit("Usage: decode.py hid|payload FRAMES.txt OUTPUT.wav")
    try:
        decode(Path(sys.argv[2]), Path(sys.argv[3]), os.environ.get("SOFO_OPUS_LIBRARY", "/opt/homebrew/lib/libopus.dylib"), hid=sys.argv[1] == "hid")
    except (OSError, ValueError) as error:
        sys.exit(str(error))
