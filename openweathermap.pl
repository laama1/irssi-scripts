use warnings;
use strict;
use Irssi;
use utf8;
use JSON;
#use open ':std', ':encoding(UTF-8)';
binmode(STDIN,  ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
#binmode STDOUT, ":encoding(utf8)";
#binmode STDIN, ":encoding(utf8)";
#binmode STDERR, ":encoding(utf8)";
#binmode FILE, ':utf8';
#use open ':std', ':encoding(utf8)';

use Data::Dumper;

#use Digest::MD5 qw(md5_hex);		# LAama1 28.4.2017
#use Encode qw(encode_utf8);
use Encode;

#use lib '/home/laama/Mount/kiva/.irssi/scripts';
#use lib '/usr/lib64/perl5/vendor_perl/';
use KaaosRadioClass;				# LAama1 13.11.2016

use vars qw($VERSION %IRSSI);
$VERSION = "20180808";
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'LAama1',
	name        => 'openweathermap',
	description => 'Fetches weather data from openweathermap.org',
	license     => 'Fublic Domain',
	url         => 'http://kaaosradio.fi',
	changed     => $VERSION
);

my $apikey = '4c8a7a171162e3a9cb1a2312bc8b7632';
my $url = 'https://api.openweathermap.org/data/2.5/weather?q=';
my $DEBUG = 1;
my $DEBUG1 = 0;
my $DEBUG_decode = 0;
my $myname = 'openweathermap.pl';
my $db = Irssi::get_irssi_dir(). '/scripts/openweathermap.db';
my $dbh;	# database handle

unless (-e $db) {
	unless(open FILE, '>:utf8',$db) {
		Irssi::print("$myname: Unable to create or write file: $db");
		die;
	}
	close FILE;
	if (CREATEDB() == 0) {
		Irssi::print("$myname: Database file created.");
	}
}

# Data type
sub replace_scandic_letters {
	my ($row, @rest) = @_;
	dd("replace_scandic_letters row: $row");

	#if ($row) {
	$row =~ s/ä/ae/g;
	$row =~ s/Ä/ae/g;
	$row =~ s/ö/oe/g;
	$row =~ s/Ö/oe/g;
	$row =~ s/Ã¤/ae/g;
	$row =~ s/Ã¶/oe/g;
	#$row =~ s/\s+/ /gi;
	#$row =~ s/\’//g;
	#}
	dd("replace_scandic_letters row after: $row");
	return $row;
}

sub CREATEDB {
	$dbh = KaaosRadioClass::connectSqlite($db);
    #my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;

	my $stmt = qq/CREATE TABLE IF NOT EXISTS CITIES (ID int primary key, NAME TEXT, COUNTRY text, PVM INT, LAT TEXT, LON TEXT)/;
	
	my $rv = KaaosRadioClass::writeToOpenDB($dbh, $stmt);
	if($rv != 0) {
   		Irssi::print ("$myname: DBI Error $rv");
		return -1;
	} else {
   		Irssi::print("$myname: Table CITIES created successfully");
	}

	my $stmt2 = qq/CREATE TABLE IF NOT EXISTS DATA (CITY TEXT, PVM INT, COUNTRY TEXT, CITYID int, SUNRISE int, SUNSET int, DESCRIPTION text, WINDSPEED text, WINDDIR text,
	TEMPMAX text, TEMP text, HUMIDITY text, PRESSURE text, TEMPMIN text, LAT text, LON text)/;
	my $rv2 = KaaosRadioClass::writeToOpenDB($dbh, $stmt2);
	if($rv2 < 0) {
   		Irssi::print ("$myname: DBI Error: $rv2");
		return -2;
	} else {
   		Irssi::print("$myname: Table DATA created successfully");
	}

	$dbh = KaaosRadioClass::closeDB($dbh);
	return 0;
}

# param: searchword, returns json answer or 0
sub findWeather {
	my ($searchword, @rest) = @_;
	my $searchtime = time() - (2*60*60);
	dp("findWeather: $searchword") if $DEBUG;
	my $returnstring;

	my $data = KaaosRadioClass::fetchUrl($url.$searchword."&units=metric&appid=".$apikey, 0);
	da("DATA:",$data);
	if ($data < 0) {
		dp('data = '.$data);
		return 0;
	}
	
	my $json = decode_json($data);
	da('JSON:',$json);
	da('JSON-temp: '. $json->{main}->{temp});
	$dbh = KaaosRadioClass::connectSqlite($db);
	SAVECITY($json);
	SAVEDATA($json);
	$dbh = KaaosRadioClass::closeDB($dbh);
	return $json;
}

# save new city to database
sub SAVECITY {
	my ($json, @rest) = @_;
	my $now = time;
	my $stmt = "INSERT OR IGNORE INTO CITIES (ID, NAME, COUNTRY, PVM, LAT, LON) VALUES ($json->{id}, '$json->{name}', '$json->{sys}->{country}', $now, '$json->{coord}->{lat}', '$json->{coord}->{lon}')";
	dp('save City stmt: '.$stmt);
	return KaaosRadioClass::writeToOpenDB($dbh, $stmt);
}

sub SAVEDATA {
	my ($json, @rest) = @_;
	my $now = time;
	my $name = $json->{name};
	my $country = $json->{sys}->{country} || '';
	my $id = $json->{id} || -1;
	my $sunrise = $json->{sys}->{sunrise} || 0;
	my $sunset = $json->{sys}->{sunset} || 0;
	my $weatherdesc = $json->{weather}[0]->{description} || '';
	#my $weatherdesc = '';
	my $windspeed = $json->{wind}->{speed} || 0;
	my $winddir = $json->{wind}->{deg} || 0;
	my $tempmax = $json->{main}->{temp_max} || 0;
	my $humidity = $json->{main}->{humidity} || 0;
	my $pressure = $json->{main}->{pressure} || 0;
	my $tempmin = $json->{main}->{temp_min} || 0;
	my $temp = $json->{main}->{temp} || 0;
	my $lat = $json->{coord}->{lat} || 0;
	my $long = $json->{coord}->{lon} || 0;
									#1	#2		#2		#4		#5		#6		#7			#8			#9		#10			#11	#12			#13		#14		#15		#16	
	my $stmt = "INSERT INTO DATA (CITY, PVM, COUNTRY, CITYID, SUNRISE, SUNSET, DESCRIPTION, WINDSPEED, WINDDIR, TEMPMAX, TEMP, HUMIDITY, PRESSURE, TEMPMIN, LAT, LON)
	 VALUES ('$name', $now, '$country', $id, $sunrise, $sunset, '$weatherdesc', '$windspeed', '$winddir', '$tempmax', '$temp', '$humidity', '$pressure', '$tempmin', '$lat', '$long')";
	dp('save Data stmt: '.$stmt);
	return KaaosRadioClass::writeToOpenDB($dbh, $stmt);
}

# debug print
sub dp {
	my ($string, @rest) = @_;
	if ($DEBUG == 1) {
		print("\n$myname debug: ".$string);
	}
}

sub dd {
	my ($string, @rest) = @_;
	if ($DEBUG_decode == 1) {
		print("\n$myname debug: ".$string);
	}
}

# debug print array
sub da {
	Irssi::print("debugarray: ");
	Irssi::print(Dumper(@_)) if ($DEBUG == 1 || $DEBUG_decode == 1);
}

# format the message
sub getSayLine {
	my ($json, @rest) = @_;
	if ($json == 0) {
		dp('json = 0');
		return 0;
	}
	my $returnvalue = $json->{name}.', '.$json->{sys}->{country}.': '.$json->{main}->{temp}.'°C, '.$json->{weather}[0]->{description};
	return $returnvalue;
}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	return if ($nick eq $server->{nick});   # self-test
	
	# Check we have an enabled channel
	my $enabled_raw = Irssi::settings_get_str('openweathermap_enabled_channels');
	my @enabled = split(/ /, $enabled_raw);
	return unless grep(/$target/, @enabled);
	if ($msg =~ /\!(sää |saa |s )(.*)$/i) {
		dd("Hopsan $1");
		return if KaaosRadioClass::floodCheck() > 0;
		#my $searchWord = $1;
		my $city = $2;
		my $sayline = getSayLine(findWeather($city));
		dp("sig_msg_pub: found some results from '$city' on channel '$target'. '$sayline'") if $sayline;
		$server->command("msg -channel $target $sayline") if $sayline;
		return;
	}
}

sub sig_msg_pub_own {
	my ($server, $msg, $target) = @_;
	dp('own public');
	sig_msg_pub($server, $msg, $server->{nick}, "", $target);
}

Irssi::settings_add_str('openweathermap', 'openweathermap_enabled_channels', '');

#Irssi::settings_add_str('openweathermap', 'openweathermap_shortmode_channels', '');

Irssi::signal_add('message public', 'sig_msg_pub');
#Irssi::signal_add('message own_public', 'sig_msg_pub_own');
Irssi::print("$myname v. $VERSION loaded.");
Irssi::print("\nNew commands:");
Irssi::print('/set openweathermap_enabled_channels #1 #2');
#Irssi::print('/set openweathermap_shortmode_channels #1 #2');
