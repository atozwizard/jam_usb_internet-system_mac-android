#!/usr/bin/env python3
"""SOCKS5 proxy that opens outbound TCP connections from an Android phone over ADB.

Each SOCKS CONNECT request starts:

    adb shell -T -x nc HOST PORT

The Mac app connects to localhost; the phone performs the actual outbound
connection over cellular data. This is slower than native tethering but avoids
macOS RNDIS driver support.
"""

from __future__ import annotations

import argparse
import ipaddress
import select
import signal
import socket
import socketserver
import subprocess
import sys
import threading
import time
from typing import Optional


def log(message: str) -> None:
    timestamp = time.strftime("%H:%M:%S")
    print(f"[{timestamp}] {message}", flush=True)


def recv_exact(sock: socket.socket, size: int) -> bytes:
    chunks = []
    remaining = size
    while remaining:
        chunk = sock.recv(remaining)
        if not chunk:
            raise ConnectionError("client disconnected")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def parse_socks_request(sock: socket.socket) -> tuple[str, int]:
    header = recv_exact(sock, 4)
    version, command, _reserved, atyp = header
    if version != 5:
        raise ValueError("unsupported SOCKS version")
    if command != 1:
        raise ValueError("only CONNECT is supported")

    if atyp == 1:
        host = socket.inet_ntoa(recv_exact(sock, 4))
    elif atyp == 3:
        length = recv_exact(sock, 1)[0]
        host = recv_exact(sock, length).decode("idna")
    elif atyp == 4:
        host = socket.inet_ntop(socket.AF_INET6, recv_exact(sock, 16))
    else:
        raise ValueError("unsupported address type")

    port = int.from_bytes(recv_exact(sock, 2), "big")
    return host, port


def socks_success(sock: socket.socket) -> None:
    sock.sendall(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")


def socks_failure(sock: socket.socket, code: int = 1) -> None:
    try:
        sock.sendall(bytes([5, code, 0, 1, 0, 0, 0, 0, 0, 0]))
    except OSError:
        pass


class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, server_address, handler_class, adb: str, serial: str):
        super().__init__(server_address, handler_class)
        self.adb = adb
        self.serial = serial


class SocksHandler(socketserver.BaseRequestHandler):
    request: socket.socket
    server: ThreadedTCPServer

    def handle(self) -> None:
        proc: Optional[subprocess.Popen[bytes]] = None
        try:
            self.request.settimeout(20)
            greeting = recv_exact(self.request, 2)
            version, method_count = greeting
            if version != 5:
                return
            methods = recv_exact(self.request, method_count)
            if 0 not in methods:
                self.request.sendall(b"\x05\xff")
                return
            self.request.sendall(b"\x05\x00")

            host, port = parse_socks_request(self.request)
            proc = self.open_android_nc(host, port)
            socks_success(self.request)
            log(f"CONNECT {host}:{port}")
            self.pipe_until_closed(proc)
        except Exception as exc:
            log(f"connection failed: {exc}")
            socks_failure(self.request)
        finally:
            if proc and proc.poll() is None:
                proc.kill()

    def open_android_nc(self, host: str, port: int) -> subprocess.Popen[bytes]:
        command = [self.server.adb]
        if self.server.serial:
            command += ["-s", self.server.serial]
        command += ["shell", "-T", "-x", "nc", "-w", "120"]

        try:
            ip = ipaddress.ip_address(host)
            if ip.version == 4:
                command += ["-4"]
            elif ip.version == 6:
                command += ["-6"]
        except ValueError:
            pass

        command += [host, str(port)]
        return subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=0,
        )

    def pipe_until_closed(self, proc: subprocess.Popen[bytes]) -> None:
        assert proc.stdin is not None
        assert proc.stdout is not None

        client = self.request
        client.setblocking(False)
        stdout_fd = proc.stdout.fileno()
        stdin = proc.stdin

        while True:
            if proc.poll() is not None:
                break

            readable, _, _ = select.select([client, stdout_fd], [], [], 0.5)
            if client in readable:
                try:
                    data = client.recv(65536)
                except BlockingIOError:
                    data = b""
                if not data:
                    try:
                        stdin.close()
                    except OSError:
                        pass
                    break
                try:
                    stdin.write(data)
                    stdin.flush()
                except (BrokenPipeError, OSError):
                    break

            if stdout_fd in readable:
                try:
                    data = proc.stdout.read(65536)
                except OSError:
                    data = b""
                if not data:
                    break
                try:
                    client.sendall(data)
                except OSError:
                    break


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=10808)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial", default="")
    args = parser.parse_args()

    with ThreadedTCPServer((args.host, args.port), SocksHandler, args.adb, args.serial) as server:
        stopping = threading.Event()

        def stop(_signum, _frame) -> None:
            stopping.set()
            server.shutdown()

        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)

        log(f"SOCKS5 listening on {args.host}:{args.port}")
        log("Use Ctrl-C to stop.")

        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        while not stopping.is_set():
            time.sleep(0.5)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
