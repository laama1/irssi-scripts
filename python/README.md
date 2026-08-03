# Python Tools

This folder contains the `ip_info.py` utility and its test suite.

## ip_info.py

`ip_info.py` checks an IP address and prints a single comma-separated output line.

Current features:
- Geo/IP metadata lookup (via `ipinfo.io` or local GeoLite2 DBs)
- Ping latency check
- Reverse DNS lookup
- Proxy list matching (`socks4.txt`, `socks5.txt`, `http.txt`)
- Optional Nmap check when a matching proxy entry includes a port
- DNSBL checks with parallel lookups
- IPv4 and IPv6 support (including AAAA DNSBL queries)

## Requirements

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

## Run Script

Example IPv4:

```bash
./ip_info.py 1.1.1.1
```

Example IPv6:

```bash
./ip_info.py 2606:4700:4700::1111
```

## Tests

Test file:
- `test_ip_info.py`

### Default test run (unit tests)

Runs deterministic tests with mocks/stubs. Live tests are skipped by default.

```bash
python3 -m unittest test_ip_info.py
```

### Live integration tests (no mocks)

Runs the script as a subprocess against real network services.

```bash
RUN_LIVE_IP_INFO_TESTS=1 python3 -m unittest test_ip_info.TestIpInfoLive
```

Notes:
- Live tests delete local proxy list files first (`socks4.txt`, `socks5.txt`, `http.txt`) to exercise download flow.
- Live tests assert those files are recreated.
- Live tests require `dnspython` in the same interpreter environment.

### Run one specific test

```bash
python3 -m unittest test_ip_info.TestIpInfoMain.test_main_with_dnsbl_hits_for_127_0_0_2
```
