# Python Tools

This folder contains utilities for IP information lookup, IRC server monitoring, and YouTube transcript extraction.

Main scripts:
- `ip_info.py` - IP geolocation and proxy detection
- `unrealircd-versions.py` - UnrealIRCd version checker for IRC networks
- `youtube_transcript.py` - YouTube transcript extraction

## ip_info.py

`ip_info.py` checks an IP address and prints a single comma-separated output line.

Current features:
- Geo/IP metadata lookup (via `ipinfo.io` or local GeoLite2 DBs)
- `ping` latency check
- Reverse DNS lookup using a python library
- Proxy list matching against `socks4.txt`, `socks5.txt`, `http.txt`
- Optional `nmap` check when a matching proxy entry includes a port
- DNSBL checks with parallel lookups
- IPv4 and IPv6 support (including AAAA DNSBL queries)
- `whois` command support

### Requirements

Minimum:
- Python 3
- `requests`
- `dnspython`

Optional/local mode:
- `geoip2`
- GeoLite2 DB files under `geolite2/`

Install Python dependencies:

```bash
python3 -m pip install requests dnspython geoip2
```

### Run Script

Example IPv4:

```bash
./ip_info.py 1.1.1.1
```

Example IPv6:

```bash
./ip_info.py 2606:4700:4700::1111
```

### Tests

#### ip_info.py tests

Test file:
- `test_ip_info.py`

#### Default test run (unit tests)

Runs deterministic tests with mocks/stubs. Live tests are skipped by default.

```bash
python3 -m unittest test_ip_info.py
```

#### Live integration tests (no mocks)

Runs the script as a subprocess against real network services.

```bash
RUN_LIVE_IP_INFO_TESTS=1 python3 -m unittest test_ip_info.TestIpInfoLive
```

Notes:
- Live tests delete local proxy list files first (`socks4.txt`, `socks5.txt`, `http.txt`) to exercise download flow.
- Live tests assert those files are recreated.
- Live tests require `dnspython` in the same interpreter environment.

#### Run one specific test

```bash
python3 -m unittest test_ip_info.TestIpInfoMain.test_main_with_dnsbl_hits_for_127_0_0_2
```

## unrealircd-versions.py

`unrealircd-versions.py` connects to an IRC network and checks the UnrealIRCd version on each server.

Features:
- Fetches the latest stable UnrealIRCd version from the official repository
- Connects to an IRC server via SSL or standard connection
- Discovers all servers on the network using the LINKS command
- Queries each server for its UnrealIRCd version using the VERSION command
- Categorizes servers as UP TO DATE, OUTDATED, UNKNOWN, or UNAVAILABLE
- Displays a detailed summary with version comparison results

Usage:

```bash
python3 unrealircd-versions.py [IRC_HOST]
```

Arguments:
- `IRC_HOST` (optional): The IRC server hostname to connect to (default: `irc.example.net`)

Examples:

```bash
python3 unrealircd-versions.py
python3 unrealircd-versions.py irc.your-network.net
```

The script outputs all server communication followed by a summary table showing each server's version and status.

### unrealircd-versions.py tests

Test file:
- `test_unrealircd_versions.py`

Run all tests:

```bash
python3 -m unittest test_unrealircd_versions.py
```

Run a specific test class:

```bash
python3 -m unittest test_unrealircd_versions.TestVersionTuple
```

Run a specific test:

```bash
python3 -m unittest test_unrealircd_versions.TestVersionTuple.test_simple_version
```
