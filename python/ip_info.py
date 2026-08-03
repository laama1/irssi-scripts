#!/usr/bin/python
"""
ip_info.py
version: 1.0
author: laama
Usage:
  python ip_info.py <ip-address>

Script will print all errors and status messages to ip_info.log in the same directory as the script.

This script takes an IP address as a parameter, gets GeoIP info from a local MaxMind GeoLite2 database, pings the address to get latency, and performs a reverse DNS lookup.
pip install dnspython geoip2
"""

import sys
import subprocess
import re
import ipaddress
import dns.resolver
import dns.reversename
import geoip2.database
import os
import time
import requests

# SETTINGS:
use_ipinfo_io = True  # Set to True to use ipinfo.io API instead of local GeoLite2 databases (requires internet access and it is slow)
use_dnsbl = True  # Set to True to check the IP against DNSBL lists (requires internet access and it is slow)

socks4_url = "https://raw.githubusercontent.com/TheSpeedX/SOCKS-List/master/socks4.txt"
socks5_url = "https://raw.githubusercontent.com/TheSpeedX/SOCKS-List/master/socks5.txt"
http_url = "https://raw.githubusercontent.com/TheSpeedX/SOCKS-List/master/http.txt"

script_dir = os.path.dirname(os.path.abspath(__file__))
geoip_city_db_location = script_dir + '/geolite2/GeoLite2-City.mmdb'
geoip_asn_db_location = script_dir + '/geolite2/GeoLite2-ASN.mmdb'
geoip_country_db_location = script_dir + '/geolite2/GeoLite2-Country.mmdb'
proxy_file_list = {
	script_dir + '/socks4.txt': socks4_url,
	script_dir + '/socks5.txt': socks5_url,
	script_dir + '/http.txt': http_url
}

dnsbl_hosts = [
	"dnsbl.dronebl.org",
	"rbl.efnetrbl.org",
	"dnsbl.swiftbl.net",
	"combined.abuse.ch",
	"bogons.cymru.com",
	"rbl.ircbl.org",
	"rbl.evilnet.org",
]

# Collect output fragments during checks and print them as one comma-separated line at the end.
output_buffer = []

def log_to_file(logtext):
	timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
	logtext = f"[{timestamp}] {logtext}"
	with open(script_dir + '/ip_info.log', 'a') as log_file:
		log_file.write(logtext + '\n')

def check_age_of_files():
	for file, url in proxy_file_list.items():
		if os.path.exists(file):
			mod_time = os.path.getmtime(file)
			age_days = (time.time() - mod_time) / (24 * 3600)
			log_to_file(f"{file} age: {age_days:.2f} days")
		else:
			log_to_file(f"{file} does not exist.")
			age_days = 100
	return age_days

def download_proxy_lists():
	for file, url in proxy_file_list.items():
		try:
			response = requests.get(url)
			response.raise_for_status()
			with open(file, 'w') as f:
				f.write(response.text)
			log_to_file(f"Downloaded and saved {file}")
		except Exception as e:
			log_to_file(f"Failed to download {file} from {url}: {e}")

def check_if_ip_in_proxy_lists(ip):
	for file, url in proxy_file_list.items():
		shortfilename = os.path.splitext(os.path.basename(file))[0]  # 'socks4', 'socks5', or 'http'
		try:
			with open(file, 'r') as f:
				for line in f:
					if ip in line:
						output_buffer.append(shortfilename + ": " + line.strip())
						if ":" in line:
							parts = line.strip().split(':')
							if len(parts) >= 2 and parts[0] == ip:
								port = parts[1]
								nmap_result = nmap_given_port(ip, port)
								if nmap_result:
									output_buffer.append(f"Nmap result: {nmap_result}")
						return True
		except Exception as e:
			log_to_file(f"Failed to read {file}: {e}")
	return False

def nmap_given_port(ip, port):
	"""
	Use simple nmap command to scan ip and port, return the result line if found.
	"""
	try:
		completed = subprocess.run([
			'nmap', '-p', str(port), ip
		], capture_output=True, text=True)
		if completed.returncode == 0:
			lines = completed.stdout.splitlines()
			target = "PORT   STATE SERVICE"
			next_line = None
			for i, line in enumerate(lines):
				if line.strip() == target:
					if i + 1 < len(lines):
						next_line = re.sub(r'\s+', ' ', lines[i + 1].strip())
					break
			if next_line and next_line.startswith(str(port)):
				return next_line

		return None
	except Exception as e:
		log_to_file(f"Failed to run nmap on {ip}:{port}: {e}")
		return None

def ipinfo_io(ip):
	"""
	Fetches IP information from ipinfo.io API.
	"""
	try:
		response = requests.get(f"https://ipinfo.io/{ip}/json")
		response.raise_for_status()
		data = response.json()
		country = data.get('country')
		city = data.get('city')
		region = data.get('region')
		org = data.get('org')
		hostname = data.get('hostname')
		return country, city, region, org, hostname
	except Exception as e:
		log_to_file(f"Failed to get info from ipinfo.io for {ip}: {e}")
		return None, None, None, None, None

def get_geoip_info(ip, city_db, asn_db):
	"""
	Fetches GeoIP information from local MaxMind GeoLite2 databases.
	"""
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
		log_to_file(f"Failed to get GeoIP info for {ip}: {e}")
		return None, None, None

def ping_ip(ip):
	"""
	Pings the given IP address and returns the latency in milliseconds.
	-c count = 2
	-W wait time = 1 second
	-l preload = 2
	"""
	try:
		completed = subprocess.run([
			'ping', '-c', '2', '-W', '1', '-l', '2', ip
		], capture_output=True, text=True)
		if completed.returncode == 0:
			match = re.search(r'time=([0-9.]+)\s*ms', completed.stdout)
			if match:
				return float(match.group(1))
		return None
	except Exception:
		return None

def reverse_dns(ip):
	"""
	Performs a reverse DNS lookup for the given IP address. (PTR record)
	"""
	try:
		addr = dns.reversename.from_address(ip)
		resolver = dns.resolver.Resolver()
		answer = resolver.resolve(addr, "PTR", lifetime=3.0)
		if answer:
			return str(answer[0]).rstrip('.')
	except Exception:
		return None

def normalize_ipv4_for_dnsbl(ip):
	"""
	Return an IPv4Address for plain IPv4 or IPv4-mapped IPv6 input.
	"""
	try:
		parsed_ip = ipaddress.ip_address(ip)
		if isinstance(parsed_ip, ipaddress.IPv4Address):
			return parsed_ip
		if isinstance(parsed_ip, ipaddress.IPv6Address) and parsed_ip.ipv4_mapped:
			return parsed_ip.ipv4_mapped
	except ValueError as e:
		log_to_file(f"Invalid IP address for DNSBL check {ip}: {e}")
	return None

def check_dnsbl_lists(ip):
	"""
	Check IPv4 address against configured DNSBL zones and append matches to output.
	Running against each dnsbl_hosts can be slow, so consider limiting the list if speed is a concern.
	"""
	ipv4 = normalize_ipv4_for_dnsbl(ip)
	if not ipv4:
		return []

	reversed_ip = '.'.join(reversed(str(ipv4).split('.')))
	resolver = dns.resolver.Resolver()
	resolver.lifetime = 3.0
	resolver.timeout = 3.0
	matches = []

	for dnsbl_host in dnsbl_hosts:
		query_name = f"{reversed_ip}.{dnsbl_host}"
		try:
			answers = resolver.resolve(query_name, "A")
			for answer in answers:
				matches.append(f"DNSBL {dnsbl_host}: {answer}")
		except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer, dns.resolver.NoNameservers):
			continue
		except dns.exception.Timeout:
			log_to_file(f"DNSBL query timed out for {query_name}")
		except Exception as e:
			log_to_file(f"DNSBL query failed for {query_name}: {e}")

	return matches

def main():
	if len(sys.argv) != 2:
		print("Usage: python ip_info.py <ip-address>")
		sys.exit(1)
	ip = sys.argv[1]

	if (use_ipinfo_io):
		country, city, region, org, hostname = ipinfo_io(ip)
		if country: output_buffer.append(f"Country: {country}")
		if city: output_buffer.append(f"City: {city}")
		if region: output_buffer.append(f"Region: {region}")
		if org: output_buffer.append(f"Org: {org}")
		if hostname: output_buffer.append(f"Hostname: {hostname}")
	else:
		country, city, asn = get_geoip_info(ip, geoip_city_db_location, geoip_asn_db_location)
		if country: output_buffer.append(f"Country: {country}")
		if city: output_buffer.append(f"City: {city}")
		if asn: output_buffer.append(f"ASN: {asn}")
		hostname = reverse_dns(ip)
		if hostname: output_buffer.append(f"Hostname: {hostname}")

	latency = ping_ip(ip)
	if latency: output_buffer.append(f"Ping: {latency} ms")

	if use_ipinfo_io == False and check_age_of_files() > 1:
		download_proxy_lists()

	if use_dnsbl:
		output_buffer.extend(check_dnsbl_lists(ip))
	check_if_ip_in_proxy_lists(ip)

	if output_buffer:
		print(', '.join(output_buffer))

if __name__ == "__main__":
	main()