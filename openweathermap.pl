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
	authors     => "LAama1",
	contact     => "LAama1",
	name        => "openweathermap",
	description => "Fetches weather data from openweathermap.com or something.",
	license     => "Fublic Domain",
	url         => "http://kaaosradio.fi",
	changed     => $VERSION
);

my $apikey = '4c8a7a171162e3a9cb1a2312bc8b7632';
my $url = 'https://api.openweathermap.org/data/2.5/weather?q=';
my $DEBUG = 1;
my $DEBUG1 = 0;
my $DEBUG_decode = 1;
my $myname = "openweathermap.pl";

# Data type

sub replace_scandic_letters {
	my ($row, @rest) = @_;
	#dd("replace non url chars row: $row");

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
	dd("replace non url chars row after: $row") if $DEBUG;
	return $row;
}


sub findWeather {
	my ($searchword, @rest) = @_;
	my $searchtime = time() - (2*60*60);
	dp("findWeather: $searchword") if $DEBUG;
	my $returnstring;
	my $temp = "";

	my $data = KaaosRadioClass::fetchUrl($url.$searchword."&units=metric&appid=".$apikey, 0);
	da("DATA:",$data);
	if ($data == -1) {
		dp('data = 0');
		return 0;
	}
	
	my $json = decode_json($data);
	da('JSON:',$json);
	da('JSON-temp: '. $json->{main}->{temp});
	

	return $json;
}

sub createShortAnswerFromResults {
	my @resultarray = @_;
	my $amount = @resultarray;
	dp("create short answer fom results.. how many values: $amount");
	if ($amount == 0) {
		return "Ei tuloksia.";
	}

	my $returnstring = "";
	my $rowid = $resultarray[0];
	$returnstring = "ID: $rowid, ";
	my $nick = $resultarray[1];					# who added
	my $when = $resultarray[2];					# when added
	my $url = $resultarray[3];					# url
	$returnstring .= "url: $url";
	my $title = $resultarray[4];				# title
	my $desc = $resultarray[5];					# description
	my $channel = $resultarray[6];				# channel

	if ($rowid) {
		Irssi::print("$myname: Found: id: $rowid, nick: $nick, when: $when, title: $title, description: $desc, channel: $channel, url: $url");
		#Irssi::print("$myname: return string: $returnstring");
	}

	dp("stringi: $returnstring");
	#dp($string);
	return $returnstring;

}

# Create one line from one result!
sub createAnswerFromResults {
	dp("createAnswerFromResults");
	my @resultarray = @_;

	my $amount = @resultarray;
	dp(" #### create answer from results.. how many values: $amount");
	da(@resultarray);
	if ($amount == 0) {
		return "Ei tuloksia.";
	}

	my $returnstring = "";
	my $rowid = $resultarray[0];
	$returnstring = "ID: $rowid, ";
	my $nick = $resultarray[1];					# who added
	my $when = $resultarray[2];					# when added
	my $url = $resultarray[3];					# url
	$returnstring .= "url: $url, ";
	my $title = $resultarray[4];
	$returnstring .= "title: $title, ";
	dp("title: $title");
	my $desc = $resultarray[5];
	$returnstring .= "desc: $desc, ";
	my $channel = $resultarray[6];
	#$returnstring .= "kanava: $channel"; }
	my $md5hash = $resultarray[7];
	#my $md5hash = "";
	#my $deleted = $resultarray[8] || "";
	
	#if ($nick ne "") { $string .= "nick: $nick"; }

	if ($rowid) {
		Irssi::print("$myname: Found: id: $rowid, nick: $nick, when: $when, title: $title, description: $desc, channel: $channel, url: $url, md5: $md5hash");
		Irssi::print("$myname: return string: $returnstring");
	}

	dp("string: $returnstring");
	#dp($string);
	return $returnstring;

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
	if ($DEBUG_decode == 1 || $DEBUG == 1) {
		print("\n$myname debug: ".$string);
	}
}

# debug print array
sub da {
	Irssi::print("debugarray: ");
	Irssi::print(Dumper(@_)) if ($DEBUG == 1 || $DEBUG_decode == 1);
}


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
	if ($msg =~ /\!(sää|saa) (.*)$/i) {
		dp("Hopsan");
		return if KaaosRadioClass::floodCheck() > 0;
		my $searchWord = replace_scandic_letters($1);
		my $city = $2;
		my $sayline = getSayLine(findWeather($city));
		dp("sig_msg_pub: found some results from '$city' on channel '$target'. '$sayline'") if $sayline;
		$server->command("msg -channel $target $sayline") if grep(/$target/, @enabled) && $sayline;
		return;
	}
}

sub sig_msg_pub_own {
	my ($server, $msg, $target) = @_;
	dp("own public");
	sig_msg_pub($server, $msg, $server->{nick}, "", $target);
}

Irssi::settings_add_str('openweathermap', 'openweathermap_enabled_channels', '');

Irssi::settings_add_str('openweathermap', 'openweathermap_shortmode_channels', '');

Irssi::signal_add('message public', 'sig_msg_pub');
#Irssi::signal_add('message own_public', 'sig_msg_pub_own');
Irssi::print("$myname v. $VERSION loaded.");
Irssi::print("\nNew commands:");
Irssi::print('/set openweathermap_enabled_channels #1 #2');
Irssi::print('/set openweathermap_shortmode_channels #1 #2');
