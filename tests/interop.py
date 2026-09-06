"""Independent Python AES-GCM peers exercising the compiled C# TCP implementation.

These are simulated peers, not executions of macOS or Linux clients.
Usage: python tests/interop.py --bridge path/to/OmaSend.Tests.dll
Requires .NET 10 on PATH and cryptography.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import threading
import time
import uuid
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

SECRET = "omasend-test-secret-0123456789-abcdef"
AES = AESGCM(hashlib.sha256(SECRET.encode()).digest())
PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
CHUNK = 1024 * 1024

def seal(message):
    nonce = os.urandom(12)
    return json.dumps(dict(version=1, nonce=base64.b64encode(nonce).decode(), ciphertext=base64.b64encode(AES.encrypt(nonce, json.dumps(message).encode(), b"omasend-v1")).decode())).encode()

def open_message(payload):
    e = json.loads(payload)
    return json.loads(AES.decrypt(base64.b64decode(e["nonce"]), base64.b64decode(e["ciphertext"]), b"omasend-v1"))

def exact(sock, count):
    data = bytearray()
    while len(data) < count:
        part = sock.recv(count - len(data))
        if not part:
            raise EOFError("truncated frame")
        data.extend(part)
    return bytes(data)

def read_frame(sock):
    n, = struct.unpack(">I", exact(sock, 4))
    assert 0 < n <= 20 * CHUNK
    return exact(sock, n)

def write_frame(sock, payload, fragmented=False):
    frame = struct.pack(">I", len(payload)) + payload
    if fragmented:
        for i in range(0, len(frame), 7):
            sock.sendall(frame[i:i + 7])
    else:
        sock.sendall(frame)

def chunk(transfer, offset, data):
    off = struct.pack(">Q", offset)
    nonce = os.urandom(12)
    return off + nonce + AES.encrypt(nonce, data, b"omasend-file-v1" + transfer.encode() + off)

class Peer:
    def __init__(self, identity):
        self.identity = identity
        self.messages = []
        self.files = {}
        self.failures = []
        self.hellos = 0
        self.server = socket.socket()
        self.server.bind(("127.0.0.1", 0))
        self.server.listen()
        self.port = self.server.getsockname()[1]
        threading.Thread(target=self.run, daemon=True).start()

    def message(self, kind, **fields):
        return dict(version=1, type=kind, id=str(uuid.uuid4()), originId=self.identity, originName=self.identity, createdAt=int(time.time() * 1000), port=self.port, **fields)

    def send(self, port, message, reply=False, fragmented=False):
        with socket.create_connection(("127.0.0.1", port), timeout=10) as s:
            write_frame(s, seal(message), fragmented)
            if reply:
                return open_message(read_frame(s))

    def run(self):
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            try:
                with conn:
                    conn.settimeout(20)
                    m = open_message(read_frame(conn))
                    if m["type"] == "hello":
                        self.hellos += 1
                        write_frame(conn, seal(self.message("hello_ack")))
                    elif m["type"] == "file_offer":
                        response = self.message("file_resume", resumeOffset=0)
                        response["id"] = m["id"]
                        write_frame(conn, seal(response))
                        data = bytearray()
                        while len(data) < m["fileSize"]:
                            payload = read_frame(conn)
                            off = struct.pack(">Q", len(data))
                            assert payload[:8] == off
                            data.extend(AES.decrypt(payload[8:20], payload[20:], b"omasend-file-v1" + m["id"].encode() + off))
                        complete = open_message(read_frame(conn))
                        assert complete["fileSHA256"] == hashlib.sha256(data).hexdigest()
                        self.files[m["fileName"]] = bytes(data)
                        done = self.message("file_done"); done["id"] = m["id"]
                        write_frame(conn, seal(done))
                    else:
                        self.messages.append(m)
            except Exception as e:
                self.failures.append(repr(e))

def eventually(predicate, timeout=10):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(.05)
    raise AssertionError("condition did not become true")

def send_file(peer, port, data, name="resume.bin", interrupt=True):
    offer = peer.message("file_offer", fileName=name, fileSize=len(data), fileSHA256=hashlib.sha256(data).hexdigest())
    if interrupt:
        with socket.create_connection(("127.0.0.1", port), timeout=10) as s:
            write_frame(s, seal(offer))
            assert open_message(read_frame(s)).get("resumeOffset", 0) == 0
            write_frame(s, chunk(offer["id"], 0, data[:CHUNK]))
        time.sleep(.2)
    with socket.create_connection(("127.0.0.1", port), timeout=10) as s:
        write_frame(s, seal(offer))
        offset = open_message(read_frame(s)).get("resumeOffset", 0)
        assert offset == (CHUNK if interrupt else 0), offset
        while offset < len(data):
            part = data[offset:offset + CHUNK]
            write_frame(s, chunk(offer["id"], offset, part)); offset += len(part)
        done = peer.message("file_complete", fileSHA256=hashlib.sha256(data).hexdigest()); done["id"] = offer["id"]
        write_frame(s, seal(done))
        assert open_message(read_frame(s))["type"] == "file_done"

def main():
    parser = argparse.ArgumentParser(); parser.add_argument("--bridge", required=True); parser.add_argument("--dotnet", default="dotnet")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="omasend-interop-") as root:
        process = subprocess.Popen([args.dotnet, args.bridge, "--bridge", root], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding="utf-8")
        def command(action, **fields):
            process.stdin.write(json.dumps(dict(action=action, **fields)) + "\n"); process.stdin.flush()
            reply = json.loads(process.stdout.readline()); assert "error" not in reply, reply; return reply
        try:
            port = json.loads(process.stdout.readline())["port"]
            a, b = Peer("Python peer A"), Peer("Python peer B")
            assert a.send(port, a.message("hello"), True, True)["type"] == "hello_ack"
            assert b.send(port, b.message("hello"), True)["type"] == "hello_ack"
            eventually(lambda: len(command("status")["peers"]) == 2)
            print("PASS two independent Python peers authenticated concurrently")
            message = a.message("clipboard", text="Python → Windows 👋", contentType="text/plain")
            a.send(port, message, fragmented=True)
            b.send(port, b.message("clipboard", data=PNG, contentType="image/png"))
            eventually(lambda: len(command("status")["messages"]) == 2)
            command("send", text="Windows → both Python peers 👋")
            command("image", data=PNG)
            eventually(lambda: len(a.messages) == 2 and len(b.messages) == 2)
            assert a.messages[0]["text"] == "Windows → both Python peers 👋"
            assert b.messages[1]["data"] == PNG
            print("PASS bidirectional Unicode text and PNG, fragmented TCP framing, two-peer fanout")
            data = os.urandom(2 * CHUNK + 37)
            send_file(a, port, data)
            assert Path(root, "resume.bin").read_bytes() == data
            print("PASS Python → C# encrypted file resumes after disconnect with SHA-256 verification")
            source = Path(root, "outgoing.bin"); source.write_bytes(data)
            command("file", path=str(source))
            assert a.files["outgoing.bin"] == data and b.files["outgoing.bin"] == data
            print("PASS C# → two Python peers, multi-chunk files and completion acknowledgements")
            # Malformed envelopes cannot kill the listener or authenticate a peer.
            for payload in [b'{"version":1,"nonce":"AA==","ciphertext":"AA=="}', b'{}', b'not json']:
                with socket.create_connection(("127.0.0.1", port), timeout=5) as s:
                    write_frame(s, payload)
            bad = bytearray(seal(a.message("clipboard", text="tampered"))); bad[-10] ^= 1
            with socket.create_connection(("127.0.0.1", port), timeout=5) as s: write_frame(s, bad)
            assert a.send(port, a.message("hello"), True)["type"] == "hello_ack"
            assert not any(m.get("text") == "tampered" for m in command("status")["messages"])
            print("PASS malformed and tampered messages rejected; listener remains healthy")
            command("clear")
            eventually(lambda: a.messages[-1]["type"] == b.messages[-1]["type"] == "history_clear")
            assert not a.failures and not b.failures, (a.failures, b.failures)
            print("PASS history clear broadcast. All remote peers in this test were simulated Python clients.")
        finally:
            if process.poll() is None:
                process.stdin.write('{"action":"quit"}\n'); process.stdin.flush(); process.wait(timeout=10)

if __name__ == "__main__":
    main()
