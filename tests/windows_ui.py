"""Run against an isolated, already running Windows UI (see docs/DEVELOPMENT.md).
Uses real Windows clipboard APIs and two explicitly simulated Python peers.
"""
import argparse
import base64
import os
from pathlib import Path
import subprocess
import time
from interop import Peer, PNG, send_file, eventually

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=53319)
    p.add_argument("--helper", required=True)
    p.add_argument("--downloads", required=True)
    p.add_argument("--dotnet", default="dotnet")
    p.add_argument("--keep-peers", action="store_true")
    args = p.parse_args()
    def clip(*commands):
        return subprocess.check_output([args.dotnet, args.helper, *commands], text=True, encoding="utf-8").strip()
    a, b = Peer("Python test peer A"), Peer("Python test peer B")
    for peer in (a, b):
        assert peer.send(args.port, peer.message("hello"), True)["type"] == "hello_ack"
    a.send(args.port, a.message("clipboard", text="Incoming Unicode test 👋", contentType="text/plain"))
    eventually(lambda: clip("read") == "Incoming Unicode test 👋")
    time.sleep(1)
    assert not a.messages and not b.messages, "incoming clipboard echoed"
    clip("text", "Shared from the real Windows clipboard")
    eventually(lambda: len(a.messages) == len(b.messages) == 1)
    assert all(peer.messages[0]["text"] == "Shared from the real Windows clipboard" for peer in (a, b))
    print("PASS real UI auto-copy, native clipboard polling, two-peer fanout, no incoming echo")
    b.send(args.port, b.message("clipboard", contentType="image/png", data=PNG))
    eventually(lambda: clip("read") == "IMAGE")
    time.sleep(1)
    assert len(a.messages) == len(b.messages) == 1, "incoming image echoed"
    print("PASS real UI PNG auto-copy without echo")
    data = os.urandom(1024 * 1024 + 97)
    send_file(a, args.port, data, "windows-ui-received.bin")
    target = Path(args.downloads, "windows-ui-received.bin")
    eventually(lambda: clip("read") == str(target))
    assert target.read_bytes() == data
    assert "ZoneId=3" in Path(str(target) + ":Zone.Identifier").read_text()
    print("PASS real UI file resume, Windows file clipboard, Mark of the Web retained")
    source = Path(args.downloads, "windows-ui-outgoing.txt")
    source.write_text("OmaSend real Windows file clipboard test", encoding="utf-8")
    clip("file", str(source))
    eventually(lambda: source.name in a.files and source.name in b.files)
    assert a.files[source.name] == b.files[source.name] == source.read_bytes()
    print("PASS real Windows file copy delivered to both Python peers")
    # Screenshot sample content is delivered through the actual encrypted transport.
    a.send(args.port, a.message("history_clear"))
    time.sleep(.3)
    for text in ("One clipboard across your computers", "Text, images, and files. Encrypted.", "https://github.com/Aayush9029/OmaSend"):
        a.send(args.port, a.message("clipboard", text=text, contentType="text/plain"))
    icon = Path(__file__).resolve().parents[1] / "assets" / "AppIcon.png"
    b.send(args.port, b.message("clipboard", contentType="image/png", data=base64.b64encode(icon.read_bytes()).decode()))
    print("PASS screenshot sample populated through encrypted TCP. Peers are simulated, Windows app is real.", flush=True)
    if args.keep_peers:
        end = time.monotonic() + 1800
        while time.monotonic() < end:
            for peer in (a, b): peer.send(args.port, peer.message("hello"), True)
            time.sleep(5)

if __name__ == "__main__": main()
