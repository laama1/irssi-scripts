#!/usr/bin/python
"""
ip_info.py
Usage:
  python ip_info.py <ip-address>

This script takes an IP address as a parameter, gets GeoIP info from a local MaxMind GeoLite2 database, pings the address to get latency, and performs a reverse DNS lookup.
pip install dnspython geoip2
"""

import sys
import subprocess
import re
import dns.resolver
import dns.reversename
import geoip2.database
import os
import time


socks4_url = "https://raw.githubusercontent.com/TheSpeedX/SOCKS-List/master/socks4.txt"
socks5_url = "https://raw.githubusercontent.com/TheSpeedX/SOCKS-List/master/socks5.txt"
http_url = "https://raw.githubusercontent.com/TheSpeedX/SOCKS-List/master/http.txt"

script_dir = os.path.dirname(os.path.abspath(__file__))
geoip_city_db_location = script_dir + '/geolite2/GeoLite2-City.mmdb'
geoip_asn_db_location = script_dir + '/geolite2/GeoLite2-ASN.mmdb'
geoip_country_db_location = script_dir + '/geolite2/GeoLite2-Country.mmdb'

def check_age_of_files():
	files = ['socks4.txt', 'socks5.txt', 'http.txt']
	for file in files:
		if os.path.exists(file):
			mod_time = os.path.getmtime(file)
			age_days = (time.time() - mod_time) / (24 * 3600)
			#print(f"{file} age: {age_days:.2f} days")
		else:
			#print(f"{file} does not exist.")
			return 100
	return age_days

def download_proxy_lists():
	import requests
	files = {
		'socks4.txt': socks4_url,
		'socks5.txt': socks5_url,
		'http.txt': http_url
	}
	for file, url in files.items():
		try:
			response = requests.get(url)
			response.raise_for_status()
			with open(file, 'w') as f:
				f.write(response.text)
			#print(f"Downloaded and saved {file}")
		except Exception as e:
			print(f"Failed to download {file} from {url}: {e}")

def check_if_ip_in_proxy_lists(ip):
	files = ['socks4.txt', 'socks5.txt', 'http.txt']
	for file in files:
		shortfilename = os.path.splitext(file)[0]  # 'socks4', 'socks5', or 'http'
		try:
			with open(file, 'r') as f:
				for line in f:
					if ip in line:
						#print(f"IP {ip} found in {file}. Line: {line.strip()}")
						print(shortfilename + ": " + line.strip(), end=', ')
		except Exception as e:
			print(f"Failed to read {file}: {e}", file=sys.stderr)
	return False

def nmap_given_port(ip, port):
	try:
		completed = subprocess.run([
			'nmap', '-p', str(port), ip
		], capture_output=True, text=True)
		if completed.returncode == 0:
			return completed.stdout
		return None
	except Exception:
		return None

def get_geoip_info(ip, city_db, asn_db):
	try:
		city_reader = geoip2.database.Reader(city_db)
		asn_reader = geoip2.database.Reader(asn_db)
		city_resp = city_reader.city(ip)
		asn_resp = asn_reader.asn(ip)
		country = city_resp.country.name
		city = city_resp.city.name
		asn = asn_resp.autonomous_system_organization
		city_reader.close()
		asn_reader.close()
		return country, city, asn
	except Exception as e:
		return None, None, None

def ping_ip(ip):
	try:
		completed = subprocess.run([
			'ping', '-c', '1', '-W', '1', ip
		], capture_output=True, text=True)
		if completed.returncode == 0:
			match = re.search(r'time=([0-9.]+)\s*ms', completed.stdout)
			if match:
				return float(match.group(1))
		return None
	except Exception:
		return None

def reverse_dns(ip):
	try:
		addr = dns.reversename.from_address(ip)
		resolver = dns.resolver.Resolver()
		answer = resolver.resolve(addr, "PTR", lifetime=3.0)
		if answer:
			return str(answer[0]).rstrip('.')
	except Exception:
		return None

def main():
	if len(sys.argv) != 2:
		print("Usage: python ip_info.py <ip-address>")
		sys.exit(1)
	ip = sys.argv[1]

	country, city, asn = get_geoip_info(ip, geoip_city_db_location, geoip_asn_db_location)
	if country: print(f"Country: {country}", end=', ')
	if city: print(f"City: {city}", end=', ')
	if asn: print(f"ASN: {asn}", end=', ')

	latency = ping_ip(ip)
	if latency: print(f"Ping latency: {latency} ms", end=', ')

	hostname = reverse_dns(ip)
	if hostname: print(f"Reverse DNS: {hostname}", end=', ')

	if check_age_of_files() > 1:
		#print("Proxy list files are older than 1 day. Downloading new lists...")
		download_proxy_lists()

	check_if_ip_in_proxy_lists(ip)

if __name__ == "__main__":
	main()