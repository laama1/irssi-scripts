	#  /set tvrage_enabled_channels #channel1 #channel2 ...
#  Enables url fetching on these channels
#

use warnings;
use strict;
use Irssi;
#use LWP::UserAgent;
#use HTTP::Cookies;
#use DateTime::Format::ISO8601;
#use Crypt::SSLeay;
#use HTML::Entities qw(decode_entities);
use JSON;
use Data::Dumper;
#use XML::Simple;
use utf8;
#use DateTime::Format::ISO8601;
use KaaosRadioClass;		# LAama1 26.10.2016

#use DBI;
#use DBI qw(:sql_types);

use vars qw($VERSION %IRSSI);
$VERSION = '2019-01-28';
%IRSSI = (
	authors     => "LAama1",
	contact     => "ircnet: LAama1",
	name        => "tv-skripta3",
	description => "Fetch urls and print their title",
	license     => "Public Domain",
	url         => "http://www.kaaosradio.fi",
	changed     => $VERSION
);

#my $tsfile = Irssi::get_irssi_dir()."/scripts/ts";
my $logfile = Irssi::get_irssi_dir()."/scripts/urllog.txt";
#my $cookie_file = Irssi::get_irssi_dir() . '/scripts/tv_cookies.dat';
my $db = Irssi::get_irssi_dir(). "/scripts/tv-skripta2.db";
# TODO: floodportect via KaaosRadioClass
my $floodernick = '';
my $floodertimes = 0;
#my $XML = new XML::Simple;

my $myname = 'tv-skripta3.pl';

my $DEBUG = 1;
my $DEBUG1 = 0;
my $DEBUG_decode = 0;

unless (-e $db) {
	unless(open FILE, '>'.$db) {
		Irssi::print("$myname: Unable to create file: $db");
		die;
	}
	close FILE;
	Irssi::print("$myname: Database file created.");
	#createDB();
}

sub fetch_search {
	my ($name, $param1, @rest) = @_;
	my $url = "http://api.tvmaze.com/singlesearch/shows?q=$name";
	my $response = KaaosRadioClass::fetchUrl($url);
	if ($response ne '-1') {
		Irssi::print("Successfully fetched tvmaze $url.");
		my $json = JSON->new->utf8;
		$json->convert_blessed(1);
		$json = decode_json($response);
		if ($DEBUG1) {
			Irssi::print("Json after fetch search: ");
			Irssi::print Dumper($json);
		}
		return $json;
	} else {
		Irssi::print("Failure tvmaze ($url): " . $response->code() . " " . $response->message() . " " . $response->status_line);
		return;
	}
}

sub dp {
	return unless $DEBUG;
	Irssi::print("$myname-debug: @_");
}

sub fetch_url_return_json {
	my ($url, $param1, @rest) = @_;
	dp($url);
	my $json = JSON->new->utf8;
	$json->convert_blessed(1);
	my $response = KaaosRadioClass::fetchUrl($url);
	if ($response ne '-1') {
		Irssi::print("$myname: Succesfully fetched url: $url.");
		$json = decode_json($response);
	} else {
		Irssi::print("$myname: Fetching url: $url failed.");
		return;
	}

	my $title = '';
	if ($json->{'name'}) {
        	my $seriesname = $json->{'name'};
        	my $season = $json->{'season'};
        	my $epnumber = $json->{'number'};
        	my $airdate = $json->{'airstamp'};
			dp($airdate);
			my $year = 1;
			my $month = 1;
			my $day = 1;
			my $hour = 1;
			my $minutes = 1;
			my $seconds = 1;
			my $timezone = 1;
			my $formatted_time = '';
			if ($airdate =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})([+-]\d{2}):(\d{2})/ ) {
				$year = $1;
				$month = $2;
				$day = $3;
				$hour = $4;
				$minutes = $5;
				$seconds = $6;
				$timezone = $7;
				dp("$day.$month.$year $hour:$minutes $timezone");
				$formatted_time = "$day.$month.$year $hour:$minutes UTC";
				dp('my formatted time: '.$formatted_time);
			} else {
				$formatted_time = $airdate;
			}

        	my $summary = $json->{'summary'} || '';
        	$summary =~ s/<(\/|!)?[-.a-zA-Z0-9]*.*?>//g;    #http://www.perlmonks.org/?node_id=46815
        	#$title = "$seriesname ${season}x${epnumber}, $airdate, $summary";
			$title = "$seriesname ${season}x${epnumber}, $formatted_time, $summary";
	}
	return $title;
}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;

	# Check we have an enabled channel
	my $enabled_raw = Irssi::settings_get_str('tv-skripta_enabled_channels');
	my @enabled = split(/ /, $enabled_raw);
	return unless grep(/$target/, @enabled);
	return unless ($msg =~ /^[\.\!]ep\b/i);
	my $episode = '';
	my $previousepisode = 0;
	my $info = 0;
	if ($msg =~ /\binfo (.*)/i) {
		$episode = $1;
		$info = 1;
	} elsif ($msg =~ /\bprev (.*)$/i) {
		$previousepisode = 1;
		$episode = $1;
	} elsif ($msg =~ /^\!ep (.*)$/i) {
		$episode = $1;
	} else { return; }

	return if KaaosRadioClass::Drunk($nick);
	return if KaaosRadioClass::floodCheck();

	dp("Episode: $episode");
	my $localjson = JSON->new->utf8;
	$localjson->convert_blessed(1);
	$localjson = fetch_search($episode, $info) || 0;
	if ($DEBUG1) {
		Irssi::print('localjson dumper:');
		Irssi::print Dumper $localjson;
	}
	
	my $title = 'error.';
	if ($previousepisode == 1 && $localjson) {
		my $prevepisodeurl = $localjson->{'_links'}->{'previousepisode'}->{'href'} || 0;
		dp("prevepisodeurl: $prevepisodeurl");
		$title = fetch_url_return_json($prevepisodeurl);
	} elsif ($info == 0 && $localjson) {	# get next episode
		my $nextepisodeurl = $localjson->{'_links'}->{'nextepisode'}->{'href'} || $localjson->{'_links'}->{'previousepisode'}->{'href'} || 0;
		dp("episodeurl: $nextepisodeurl");
		$title  = fetch_url_return_json($nextepisodeurl);
	} elsif ($info == 1) {
		$title = get_series_info($localjson);
	}
	$server->command("msg -channel $target $title");
}

sub get_series_info {
	my ($ownjson, @rest) = @_;
	#Irssi::print Dumper($ownjson);
	my $showname = $ownjson->{'name'};
	my $type = $ownjson->{'type'};
	my $language = $ownjson->{'language'};
	my @genres = $ownjson->{'genres'};
	#my $network = $ownjson->{'network'};	#JSON
	my $country = $ownjson->{'network'}->{'country'}->{'code'};		# US, GB..
	my $showimage = $ownjson->{'image'}->{'original'};
	my $prevepisode = $ownjson->{'_links'}->{'previousepisode'}->{'href'};
	my $nextepisode = $ownjson->{'_links'}->{'nextepisode'}->{'href'};
	my $summary = $ownjson->{'summary'};
	$summary =~ s/<(\/|!)?[-.a-zA-Z0-9]*.*?>//g;	#http://www.perlmonks.org/?node_id=46815
	dp("info: $showname, $type, $language, $country, $showimage");
	return "$showname, ($language, $country, $type), $summary image: $showimage";
}

sub get_next_episode {
	my ($myjson, @rest) = @_;
	Irssi::print Dumper $myjson if $DEBUG;
	my $nextepisodeurl = $myjson->{'_links'}->{'nextepisode'}->{'href'};
	$nextepisodeurl = $myjson->{'_links'}->{'lastepisode'}->{'href'} unless $nextepisodeurl;
	
	Irssi::print $myname . ': '.$nextepisodeurl;
	my $myjson2 = fetch_episode($nextepisodeurl);
    my $seriesname = $myjson2->{'name'};
    my $season = $myjson2->{'season'};
    my $epnumber = $myjson2->{'number'};
    my $airdate = $myjson2->{'airstamp'};
    my $summary = $myjson2->{'summary'};
    $summary =~ s/<(\/|!)?[-.a-zA-Z0-9]*.*?>//g;    #http://www.perlmonks.org/?node_id=46815
    my $title = "$seriesname ${season}x${epnumber}, $airdate, $summary";
	return $title;
}

sub sig_msg_pub_own {
	my ($server, $msg, $target) = @_;
	sig_msg_pub($server, $msg, $server->{nick}, "", $target);
}

Irssi::settings_add_str('tvrage', 'tv-skripta_enabled_channels', '');
Irssi::signal_add('message public', 'sig_msg_pub');
Irssi::signal_add('message own_public', 'sig_msg_pub_own');
