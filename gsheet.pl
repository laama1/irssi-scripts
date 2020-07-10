use warnings;
use strict;
use Irssi;
use LWP::UserAgent;
use HTTP::Cookies;
use HTTP::Response;
#use HTML::Entities qw(decode_entities);
use JSON;
use utf8;
use Data::Dumper;

use Encode;

use KaaosRadioClass;				# LAama1 13.11.2016

use vars qw($VERSION %IRSSI);
$VERSION = '2020-07-09';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'LAama1@ircnet',
	name        => 'gsheet',
	description => 'Fetches data grom google sheets.',
	license     => 'Fublic Domain',
	url         => 'http://kaaosradio.fi',
	changed     => $VERSION,
);
my $myname = 'gsheet.pl';
my $cookie_file = Irssi::get_irssi_dir() . '/scripts/gsheet_cookies.dat';

my $apikeyfile = Irssi::get_irssi_dir(). '/scripts/google_apikey';
my $apik = KaaosRadioClass::readLastLineFromFilename($apikeyfile);

my $calid = '46oohofs0emt0rrm05darkobdo@group.calendar.google.com';
my $sheetid = '1pRBIrNYjw5Qp1B8DyiyeKhFPFZB0hS_L94d4pa6V6YU';
my $datarange = 'Musiikki!A2:D2';
my $sheeturl = 'https://sheets.googleapis.com/v4/spreadsheets/' . $sheetid . '/values/' . $datarange . '?key=' . $apik;

my $DEBUG = 1;



# Data type
my $cookie_jar = HTTP::Cookies->new(
	file => $cookie_file,
	autosave => 1,
);

my $max_size = 262144;		# bytes
my $useragent = 'Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:57.0) Gecko/20100101 Firefox/65.0';
my %headers = (
	'agent' => $useragent,
	'max_redirect' => 4,							# default 7
	'max_size' => $max_size,
	#'ssl_opts' => ['verify_hostname' => 0],			# disable cert checking
	'protocols_allowed' => ['http', 'https', 'ftp'],
	'protocols_forbidden' => [ 'file', 'mailto'],
	'timeout' => 4,									# default 180 seconds
	'cookie_jar' => $cookie_jar,
	#'default_headers' => 
	#'requests_redirectable' => ['GET', 'HEAD'],		# defaults GET HEAD
	#'parse_head' => 1,
);
my $ua = LWP::UserAgent->new(%headers);


sub fetch_data {
	my ($url, @rest) = @_;
	my $json = JSON->new->utf8;
	$json->convert_blessed(1);
	#return KaaosRadioClass::getJSON($url);
	my $response = $ua->get($url);
	#if ($response->is_success) {
	if ($response->is_success) {
		#return $response->decoded_content();
		$json = decode_json($response->decoded_content());
		da($json->{values}[0]);
		return $json->{values}[0];
	}
	return;
}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	return if ($nick eq $server->{nick});   # self-test
	return if ($nick eq 'kaaosradio');
	return if ($nick eq 'k-disco' || $nick eq 'kd' || $nick eq 'kd2');
	if ($msg !~ /!radio/)  {
		return;
	}
	Irssi::print("Radio");
	# check if flooding too fast
	if (KaaosRadioClass::floodCheck() > 0) {
		clearUrlData();
		return;
	}
	# check if flooding too many times in a row
	my $drunk = KaaosRadioClass::Drunk($nick);


	my @newdata = fetch_data($sheeturl);
	#Irssi::print('DATA0:'.$newdata[0]);
	#Irssi::print('DATA1:'.$newdata[1]);
	#Irssi::print('DATA2:'.$newdata[2]);
	#Irssi::print('DATA3:'.$newdata[3]);
	Irssi::print('DATA:');
	da(@newdata);
	return;

}

sub msg_to_channel {
	my ($server, $target, $title, @rest) = @_;
	my $enabled_raw = Irssi::settings_get_str('gsheet_enabled_channels');
	my @enabled = split / /, $enabled_raw;

	if ($title =~ /(.{260}).*/s) {
		$title = $1 . '...';
	}

	$server->command("msg -channel $target $title") if grep /$target/, @enabled;
	return;
}

# debug print
sub dp {
	my ($string, @rest) = @_;
	if ($DEBUG == 1) {
		print "\n$myname debug: ".$string;
	}
}

# debug print array
sub da {
	print("debugarray: ");
	print Dumper(@_) if $DEBUG == 1;
}

Irssi::settings_add_str('gsheet', 'gsheet_enabled_channels', '');


Irssi::signal_add('message public', 'sig_msg_pub');
Irssi::print("$myname v. $VERSION loaded.");
Irssi::print("\nNew commands:");
Irssi::print('/set gsheet_enabled_channels #channel1 #channel2');
Irssi::print('gsheet enabled channels: '. Irssi::settings_get_str('gsheet_enabled_channels'));
