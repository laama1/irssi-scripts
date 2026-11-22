
#!/usr/bin/env python3
"""
UnrealIRCd Version Checker Script

DESCRIPTION:
  This script connects to an IRC network and checks the UnrealIRCd version
  running on each server. It compares each server's version against the
  latest stable release and reports which servers are outdated.

FUNCTIONALITY:
  1. Fetches the latest stable UnrealIRCd version from the official repository
  2. Connects to an IRC server using SSL
  3. Discovers all servers on the network using the LINKS command
  4. Queries each server for its UnrealIRCd version using the VERSION command
  5. Compares versions and categorizes servers as:
     - UP TO DATE: Running the latest stable version
     - OUTDATED: Running an older version
     - UNKNOWN: Version cannot be determined
     - UNAVAILABLE: Server did not respond to VERSION query
  6. Displays a summary with all results

USAGE:
  python3 unrealircd-versions.py [IRC_HOST]

ARGUMENTS:
  IRC_HOST (optional): The IRC server hostname to connect to
                       Default: irc.example.net

EXAMPLES:
  python3 unrealircd-versions.py
  python3 unrealircd-versions.py irc.your-server.net

OUTPUT:
  The script prints all communication with the server ([CLIENT] and [SERVER]
  prefixes) followed by a detailed summary table of version check results.
"""

import socket
import ssl
import json
import re
import select
import urllib.request
import time
import sys

# Configuration
IRC_HOST = "irc.example.net"
#IRC_PORT = 6697
IRC_PORT = 6667
IRC_NICK = "VersionCheck"
IRC_USER = "versioncheck"
IRC_PASSWORD = None

# Official UnrealIRCd release information
VERSION_URL = "https://www.unrealircd.org/downloads/list.json"


class IRC:
    def __init__(self, host, port):
        raw = socket.create_connection((host, port), timeout=15)

        if port == 6697:
            ctx = ssl.create_default_context()
            self.sock = ctx.wrap_socket(raw, server_hostname=host)
        else:
            self.sock = raw

        self.sock.setblocking(False)
        self.buffer = b""

    def send(self, command):
        print(f"[CLIENT] {command}")
        self.sock.sendall((command + "\r\n").encode())

    def readline(self, timeout=10):
        deadline = time.monotonic() + timeout

        while time.monotonic() < deadline:
            if b"\r\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\r\n", 1)
                return line.decode(errors="replace")

            remaining = deadline - time.monotonic()

            ready, _, _ = select.select(
                [self.sock], [], [], remaining
            )

            if not ready:
                break

            data = self.sock.recv(4096)

            if not data:
                raise ConnectionError("IRC connection closed")

            self.buffer += data

        raise TimeoutError("IRC response timeout")

    def receive(self, timeout=10):
        while True:
            line = self.readline(timeout)

            print(f"[SERVER] {line}")

            if line.startswith("PING"):
                self.send("PONG " + line[5:])
                continue

            return line

    def wait_numeric(self, numeric, timeout=15):
        deadline = time.monotonic() + timeout

        while time.monotonic() < deadline:
            line = self.receive(deadline - time.monotonic())

            if re.search(r"\s" + numeric + r"\s", line):
                return line

        raise TimeoutError(f"Missing IRC numeric {numeric}")

    def close(self):
        self.sock.close()


def latest_version():
    req = urllib.request.Request(
        VERSION_URL,
        headers={"User-Agent": "UnrealIRCd-Version-Checker"}
    )

    with urllib.request.urlopen(req, timeout=15) as response:
        releases = json.load(response)

    return releases["6.0"]["Stable"]["version"]


def version_tuple(version):
    return tuple(map(int, version.split(".")))


def get_servers(irc):
    print("Discovering network servers...")

    irc.send("LINKS")

    servers = set()

    while True:
        line = irc.receive(15)

        if re.search(r"\s365\s", line):
            break

        if re.search(r"\s364\s", line):
            fields = line.split()

            if len(fields) >= 5:
                servers.add(fields[3])

    return sorted(servers)


def get_server_version(irc, server):
    irc.send(f"VERSION {server}")

    deadline = time.monotonic() + 10

    while time.monotonic() < deadline:
        try:
            line = irc.receive(deadline - time.monotonic())
        except TimeoutError:
            return None

        if re.search(r"\s351\s", line):
            match = re.search(
                r"UnrealIRCd[-/]?(\d+(?:\.\d+)+)",
                line,
                re.IGNORECASE
            )

            if match:
                return match.group(1)

            return "Unknown: " + line

        if re.search(r"\s(?:402|421)\s", line):
            return None

    return None


def main():
    global IRC_HOST
    
    # Accept IRC_HOST as command-line argument
    if len(sys.argv) > 1:
        IRC_HOST = sys.argv[1]
    
    latest = latest_version()

    print(f"Latest stable UnrealIRCd: {latest}\n")

    irc = IRC(IRC_HOST, IRC_PORT)

    try:
        if IRC_PASSWORD:
            irc.send(f"PASS {IRC_PASSWORD}")

        irc.send(f"NICK {IRC_NICK}")
        irc.send(f"USER {IRC_USER} 0 * :Version checker")

        irc.wait_numeric("001")

        servers = get_servers(irc)

        print(f"Found {len(servers)} servers\n")

        results = []

        for server in servers:
            print(f"Checking {server}...", end=" ", flush=True)

            version = get_server_version(irc, server)

            if version is None:
                status = "UNAVAILABLE"
            elif version.startswith("Unknown"):
                status = "UNKNOWN"
            elif version_tuple(version) < version_tuple(latest):
                status = "OUTDATED"
            else:
                status = "UP TO DATE"

            print(f"{version or 'N/A':15} [{status}]")

            results.append((server, version, status))

        print("\n========== SUMMARY ==========")

        for server, version, status in results:
            print(f"{server:35} {version or 'N/A':15} {status}")

        outdated = [
            item for item in results
            if item[2] == "OUTDATED"
        ]

        print("\n=============================")
        print(f"Servers checked: {len(results)}")
        print(f"Outdated:        {len(outdated)}")

    finally:
        irc.close()


if __name__ == "__main__":
    main()
