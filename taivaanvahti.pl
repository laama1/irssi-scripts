use warnings;
use strict;
use Irssi;
use utf8;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;		# LAama1 31.7.2017
use XML::RSS;
use LWP::Simple;
#use XML::RSS::Parser;
use Data::Dumper;
use DBI;
use HTTP::Date;
#use DateTime;
use DateTime::Format::Strptime;
use Time::Piece;
use Encode qw/encode decode/;

# http://www.perl.com/pub/1998/12/cooper-01.html
# 6.7.2021: use kaaosradioclass more

use vars qw($VERSION %IRSSI);
$VERSION = '2021-07-06';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'taivaanvahti.pl',
	description => 'Fetch new data from Taivaanvahti.fi',
	license     => 'Public Domain',
	url         => 'http://www.kaaosradio.fi',
	changed     => $VERSION,
);

my $DEBUG = 1;
my $myname = 'taivaanvahti.pl';
my $db = Irssi::get_irssi_dir() . '/scripts/taivaanvahti.sqlite';
my $timeout_tag;
my $dbh;		# database handle
my $taivaanvahtiURL = 'https://www.taivaanvahti.fi/observations/rss';
my $count = 0;
my $resultarray = {};
my $parser = new XML::RSS();

unless (-e $db) {
	unless(open FILE, '>'.$db) {
		prindw("Unable to create database file: $db");
		die;
	}
	close FILE;
	create_db();
	prind("Database file $db created.");
} else {
	prind("Database file $db found!");
}

sub DP {
	return unless $DEBUG == 1;
	print("$myname debug> @_");
	return;
}

sub DA {
	return unless $DEBUG == 1;
	print("$myname-debug array>");
	print Dumper (@_);
	return;
}

sub print_help {
	my ($server, $targe, @rest) = @_;
	my $help = 'https://bot.8-b.fi/#taivaanvahti';
	return;
}

# search DB for ID, when signal was received from urltitle3.pl
sub sig_taivaanvahti_search {
	my ($server, $column, $target, $value) = @_;
	open_database_handle();
	my $sth = $dbh->prepare('SELECT DISTINCT TITLE, DESCRIPTION, HAVAINTODATE, CITY from taivaanvahti5 where HAVAINTOID = ? AND DELETED = 0');

	$sth->bind_param(1, $value);
	$sth->execute();
	if (my @line = $sth->fetchrow_array) {
		my $title =  decode('UTF-8', $line[0]);
		my $desc = decode('UTF-8', $line[1]);
		my $location = decode('UTF-8', $line[3]);
		my $timepiece = localtime($line[2])->strftime('%e.%m. %H:%M');
		#my $sayline = "$title: ($timepiece, $location) $desc";
		my $sayline = $line[0].': ('.$timepiece.', '.$line[3].') '.$line[1];
		sayit($server, $target, $sayline);
	}
	$sth->finish();
	close_database_handle();
	return 0;
}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
    my $mynick = quotemeta $serverrec->{nick};
	return if ($nick eq $mynick);   #self-test
	#return if ($nick eq 'kaaosradio');		# bad nicks

	if ($msg =~ /^[\.\!]help taivaanvahti\b/i) {
		print_help($server, $target);
		return;
	} elsif ($msg =~ /^[\.\!]taivaanvahti (.*)/i) {
		my $searcword = $1;
		search_db($searcword);
		foreach my $item (keys %$resultarray) {
			my $title = $resultarray->{$item}->{'title'};
			my $desc = $resultarray->{$item}->{'desc'};
			my $city = $resultarray->{$item}->{'city'};
			my $havaintodate = localtime($resultarray->{$item}->{'havaintodate'})->strftime('%d.%m.%y %H:%M');
			my $link = $resultarray->{$item}->{'link'};
			my $sayline = "\002$title: ($havaintodate, $city)\002 $link $desc";
			sayit($server, $target, $sayline);
		}
		return;
	} elsif($msg =~ /^!taivaanvahti/gi) {
		get_xml();
		parse_xml();
	}
	return;
}

sub sayit {
	my ($server, $target, $sayline, @rest) = @_;
	if (defined $sayline && length $sayline > 250) {
		$sayline = substr $sayline, 0, 250;
		$sayline .= ' ...';
	}
	$sayline = KaaosRadioClass::replaceWeird($sayline);
	$server->command("msg -channel $target $sayline");
	return;
}

sub msg_to_channel {
	my ($title, $link, $date, $desc, @rest) = @_;
    my $enabled_raw = Irssi::settings_get_str('taivaanvahti_enabled_channels');
    my @enabled = split / /, $enabled_raw;

	if (defined $desc && length $desc > 300) {
		$desc = substr $desc, 0, 300;
		$desc .= ' ...';
	} else {
		#$desc = "";
	}
	my $sayline = "\002$title ($date):\002 $link $desc";

	my @windows = Irssi::windows();
	foreach my $window (@windows) {
		next if $window->{name} eq '(status)';
		next unless defined $window->{active}->{type} && $window->{active}->{type} eq 'CHANNEL';

		if($window->{active}->{name} ~~ @enabled) {
			$window->{active_server}->command("msg $window->{active}->{name} $sayline");
		}
	}
	return;
}

sub open_database_handle {
	$dbh = KaaosRadioClass::connectSqlite($db);
	return;
}

sub close_database_handle {
	$dbh = KaaosRadioClass::closeDB($dbh);
	return;
}

# if link allready in DB
sub if_link_in_db {
	my ($link, @rest) = @_;
	my $sth = $dbh->prepare("SELECT * from taivaanvahti5 where LINK = ?");
	$sth->bind_param(1, $link);
	$sth->execute();
	while(my @line = $sth->fetchrow_array) {
		#DA(@line);
		$sth->finish();
		return 1;			# item allready found
	}
	$sth->finish();
	return 0;				# new item!
}

sub if_link_in_db2 {
	my ($link, @rest) = @_;
	my $searchstring = 'SELECT * from taivaanvahti5 where LINK = ?';
	while(my @line = $dbh->bindSQL_nc($dbh, $searchstring, $link)) {
		#$sth->finish();
		return 1;			# item allready found
	}
	#$sth->finish();
	return 0;				# new item!
}

# Save new item to sqlite DB
sub save_to_db {
	my ($title, $link, $date, $desc, $havaintoid, $city, $havaintodate, @rest) = @_;
	my $pvm = time;

	my $sth = $dbh->prepare('INSERT or ignore INTO taivaanvahti5 VALUES(?,?,?,?,?,?,?,?,0)') or die DBI::errstr;
	$sth->bind_param(1, $pvm);
	$sth->bind_param(2, $title);
	$sth->bind_param(3, $link);
	$sth->bind_param(4, $date);
	$sth->bind_param(5, $desc);
	$sth->bind_param(6, $city);
	$sth->bind_param(7, $havaintoid);
	$sth->bind_param(8, $havaintodate);
	$sth->execute;
	$sth->finish();

	prind("New data saved to database: $title");
	return;
}

sub create_db {
	open_database_handle();
	
	# Using FTS (full-text search)
	my $sqlquery = 'CREATE VIRTUAL TABLE taivaanvahti5 using fts4(PVM int,TITLE,LINK, PUBDATE int, DESCRIPTION, CITY, HAVAINTOID int primary key, HAVAINTODATE int, DELETED int default 0)';
	KaaosRadioClass::writeToDB($dbh, $sqlquery);
	close_database_handle();
	return;
}

sub search_db {
	my $searchword = shift;
	open_database_handle();
	DP(__LINE__.' searchword: '.$searchword);
	#my $stmt = 'SELECT rowid,title,description,city,havaintodate,link FROM taivaanvahti5 where TITLE like ? or DESCRIPTION like ? or CITY like ? AND deleted = 0 ORDER BY havaintoid DESC LIMIT 2';
	my $stmt = 'SELECT rowid, title, description, city, havaintodate, link FROM taivaanvahti5 where TITLE like ? or DESCRIPTION like ? or CITY like ? AND deleted = 0 ORDER BY havaintodate DESC LIMIT 2';
	my $sth = $dbh->prepare($stmt) or die DBI::errstr;
	$sth->bind_param(1, "%$searchword%");
	$sth->bind_param(2, "%$searchword%");
	$sth->bind_param(3, "%$searchword%");
	$sth->execute();
	
	my @line = ();
	my $index = 1;
	$resultarray = {};
	
	while(@line = $sth->fetchrow_array) {
		$resultarray->{$index} = {'rowid' => $line[0], 'title' => $line[1], 'desc' => $line[2], 'city' => $line[3], 'havaintodate' => $line[4], 'link' => $line[5]};
		$index++;
	}
	close_database_handle();
	DA($resultarray);
	DP(__LINE__." how many found: $index");
	return;
}

sub parse_id_from_link {
	my $link = shift;
	if ($link =~ /www.taivaanvahti.fi\/observations\/show\/(\d+)/gi) {
		return $1;
	}
	return 0;
}

# argument example: Tue, 04 Sep 2018 22:37:34 +0300
sub parseRFC822Time {
	my ($string, $tzone, @rest) = @_;
	#%z The time-zone as hour offset from UTC. Required to emit RFC822-conformant dates (using "%a, %d %b %Y %H:%M:%S %z").
	my $formatter = DateTime::Format::Strptime->new(
        pattern  => '%a, %d %b %Y %H:%M:%S %z',
		on_error => 'croak',
    );
	DP(__LINE__.' STRING: '. $string);
	my $dt = $formatter->parse_datetime($string);
	DP(__LINE__.' formatter dt: '.$dt);	# ISO 8601
	return $dt;
}

sub parse_time {
	my ($string, @rest) = @_;
	# Tue, 04 Sep 2018 22:37:34 +0300
	#my $tzone = '+0300';		# Default value for timezone (Finnish summer time)
	my $tzone = '+0200';		# Default value for timezone (Finnish winter time)
	if ($string =~ /\w{3}, (\d{2}) (\w{3}) \d{4} (\d{2}:\d{2}):\d{2} ([+-]\d{4})/i) {
		return parseRFC822Time($string, $tzone);
	} else {
		DP(__LINE__.' no luck');
	}
	return $string;
}

# Parse havaintodate
sub parse_mini {
	my ($obj_ref, $day, $month, $year, $hour, $minute, $tzone, @rest) = @_;
	my $isotime = $year. '/' .$month. '/' .$day. ' ' .$hour. ':' .$minute;
	my $unixtime = str2time($isotime);
	DP(__LINE__." isotime: $isotime, unixtime: $unixtime\n");

	$obj_ref->{'havaintodate'} = $unixtime;

	my $dt = DateTime->new(
		year => $year,
		month => $month,
		day => $day,
		hour => $hour,
		minute => $minute,
		#time_zone => $tzone,
	);
	my $unixtime2 = $dt->epoch();
	DP(__LINE__." unixtime: $unixtime, epoch: $unixtime2");
	#return $returnitem;
	return;
}

sub parse_extrainfo_from_link_new {
	my ($url, @rest) = @_;
	my $text = KaaosRadioClass::fetchUrl($url);
	my %returnObject = (
		'unixtime' => 0,
		'type' => '',
		'city' => '',
		'havaintodate' => ''
	);
}

sub parse_extrainfo_from_link {
	my ($url, @rest) = @_;
	my $text = KaaosRadioClass::fetchUrl($url);
	my %returnObject = (
		'unixtime' => 0,
		'type' => '',
		'city' => '',
		'havaintodate' => ''
	);

	my $date;
	if ($text =~ /<div class="main-heading">(.*?)<\/div>/gis) {
		my $heading = $1;
		if ($heading =~ /<h1>(.*?)<\/h1>/gis) {
			my $innerdata = KaaosRadioClass::ktrim($1);
			DP(__LINE__.' innerdata: '. $innerdata);
			# Parse havaintodate
			if ($innerdata =~ /(.*?) - (\d{1,2})\.(\d{1,2})\.(\d{4}) klo (\d{1,2})\.(\d{2}) - (\d{1,2})\.(\d{1,2})\.(\d{4}) klo (\d{1,2})\.(\d{2}) (.*?)</gis) {
				DP(__LINE__.' match1!');
				my $type = KaaosRadioClass::ktrim($1);
				my $pday = $2;
				my $pmonth = $3;
				my $pyear = $4;
				my $phour = $5;
				my $pminute = $6;
				my $city = KaaosRadioClass::ktrim($12);

				parse_mini(\%returnObject, $pday, $pmonth, $pyear, $phour, $pminute);
				$returnObject{'type'} = $type;
				$returnObject{'city'} = $city;
			}
			elsif ($innerdata =~ /(.*?) - (\d{1,2})\.(\d{1,2})\.(\d{4}) klo (\d{1,2})\.(\d{2}) (.*?)</gis) {
				DP(__LINE__.' match2!');
				my $type = KaaosRadioClass::ktrim($1);
				my $pday = $2;
				my $pmonth = $3;
				my $pyear = $4;
				my $phour = $5;
				my $pminute = $6;
				my $city = KaaosRadioClass::ktrim($7);
				parse_mini(\%returnObject, $pday, $pmonth, $pyear, $phour, $pminute);
				$returnObject{'type'} = $type;
				$returnObject{'city'} = $city;
			}
		}
	} else {
		DP(__LINE__.' NOT FOUND :(');
	}
	return %returnObject;
}

sub parse_xml {
	open_database_handle();
	my $index = 0;
	foreach my $item (@{$parser->{items}}) {
		$index++;
		if (if_link_in_db($item->{'link'}) == 0) {
			#DA($item);
			my $havaintoid = parse_id_from_link($item->{'link'});
			my %extrainfo = parse_extrainfo_from_link($item->{'link'});
			
			my $extrainfotime = $extrainfo{'havaintodate'};

			my $havaintodate = localtime($extrainfo{'havaintodate'})->strftime('%d.%m. %H:%M');

			DP(__LINE__." New item: $item->{title}, havaintodate: $havaintodate, extrainfotime: $extrainfotime");

			#my $pubdate_dt = parse_time($extrainfo{'unixtime'});
			my $pubdate_dt = parse_time($item->{'pubDate'});	# publish date
			my $unixtimestamp = $pubdate_dt->epoch();
			my $readabletimestamp = $pubdate_dt->strftime('%d.%m. %H:%M');
			save_to_db($item->{'title'}, $item->{'link'}, $item->{'pubDate'}, $item->{'description'}, $havaintoid, $extrainfo{'city'}, $extrainfotime);

			#msg_to_channel($item->{'title'}, $item->{'link'}, $item->{'pubDate'}, $item->{'description'}, $havaintoid, $extrainfo);
			msg_to_channel($item->{'title'}, $item->{'link'}, $havaintodate . ', '.$extrainfo{'city'}, $item->{'description'});
		}
	}
	close_database_handle();
	return;
}

# does not do anything
sub get_xml {
	my $xmlfile = get($taivaanvahtiURL);
	$parser->parse($xmlfile);
	return;
}

# get all from RSS-feed
sub timerfunc {
	get_xml();
	parse_xml();
	return;
}

sub timerstop {
	Irssi::timeout_remove($timeout_tag);
	prind("Timer stopped!");
	return;
}

sub prind {
	my ($text, @test) = @_;
	print("\00312" . $IRSSI{name} . ">\003 ". $text);
}
sub prindw {
	my ($text, @test) = @_;
	print("\0034" . $IRSSI{name} . " warning>\003 ". $text);
}

Irssi::command_bind('taivaanvahti_update', \&timerfunc, 'taivaanvahti');
Irssi::command_bind('taivaanvahti_search', \&search_db, 'taivaanvahti');
Irssi::command_bind('taivaanvahti_stop', \&timerstop, 'taivaanvahti');

Irssi::settings_add_str('taivaanvahti', 'taivaanvahti_enabled_channels', '');

Irssi::signal_add('message public', 'sig_msg_pub');
Irssi::signal_add('taivaanvahti_search_id', 'sig_taivaanvahti_search');

$timeout_tag = Irssi::timeout_add(1_800_000, 'timerfunc', undef);		# 30 minutes
#Irssi::timeout_add(5000, 'timerfunc', undef);			# 5 aseconds

prind("v. $VERSION Loaded!");
prind("new commands: /taivaanvahti_update, /taivaanvahti_search, /taivaanvahti_stop");
prind("/set taivaanvahti_enabled_channels #channel1 #channel2");
prind("Enabled on: ". Irssi::settings_get_str('taivaanvahti_enabled_channels'));
