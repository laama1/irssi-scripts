use warnings;
use strict;
use Irssi;
use utf8;
use KaaosRadioClass;		# LAama1 31.7.2017
use XML::RSS;
use LWP::Simple;
#use XML::RSS::Parser;
use Data::Dumper;
use DBI;
use HTTP::Date;

# http://www.perl.com/pub/1998/12/cooper-01.html


use vars qw($VERSION %IRSSI);
$VERSION = '2018-89-04';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'taivaanvahti',
	description => 'Fetch new data from Taivaanvahti.fi',
	license     => 'Public Domain',
	url         => 'http://www.kaaosradio.fi',
	changed     => $VERSION
);

my $DEBUG = 1;
my $myname = 'taivaanvahti.pl';
my $db = Irssi::get_irssi_dir() . '/scripts/taivaanvahti.sqlite';

my $dbh;		# database handle
my $taivaanvahtiURL = 'https://www.taivaanvahti.fi/observations/rss';
my $count = 0;
my $resultarray = {};
my $parser = new XML::RSS();

unless (-e $db) {
	unless(open FILE, '>'.$db) {
		Irssi::print("$myname: Unable to create database file: $db");
		die;
	}
	close FILE;
	createDB();
	Irssi::print("$myname: Database file created.");
} else {
	Irssi::print("$myname: Database file found!");
}

sub dp {
	return unless $DEBUG == 1;
	Irssi::print("$myname: @_");
}

sub da {
	return unless $DEBUG == 1;
	Irssi::print("$myname-debug array:");
	Irssi::print Dumper (@_);
}

sub print_help {
	my ($server, $targe, @rest) = @_;
	my $help = 'Taivaanvahti -skripti hakee ajoittain uusimmat havainnot sivulta taivaanvahti.fi. Vastaa myös kutsuttaessa komennolla !taivaanvahti.';
}

# search for ID, when signal received from urltitle3.pl
sub sig_taivaanvahti_search {
	dp('sig_taivaavahti_search');
	my ($server, $column, $target, $value) = @_;
	open_database_handle();
	my $sth = $dbh->prepare('SELECT DISTINCT * from taivaanvahti4 where HAVAINTOID = ?');
	$sth->bind_param(1, $value);
	$sth->execute();
	if (my @line = $sth->fetchrow_array) {
		# sayit($server, $target, '');
		da(@line);
	}
	$sth->finish();
	close_database_handle();
	return 0;
}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;

    my $enabled_raw = Irssi::settings_get_str('taivaanvahti_enabled_channels');
    my @enabled = split(/ /, $enabled_raw);
    return unless grep(/$target/, @enabled);

	if ($msg =~ /^[\.\!]help\b/i) {
		print_help($server, $target);
		return;
	}

	if($msg =~ /^!taivaanvahti/gi)
	{
		getXML();
		parseXML();
	}

}

sub sayit {
	my ($server, $target, $sayline, @rest) = @_;
	$server->command("msg -channel $target $sayline");
}

sub msg_to_channel {
	my ($title, $link, $date, $desc, @rest) = @_;
    my $enabled_raw = Irssi::settings_get_str('taivaanvahti_enabled_channels');
    my @enabled = split / /, $enabled_raw;

	if (defined($desc) && length($desc) > 150) {
		$desc = substr $desc, 0, 150;
		$desc .= '...';
	} else {
		#$desc = "";
	}
	my $sayline = "$title: ($date) $link $desc";

	my @windows = Irssi::windows();
	foreach my $window (@windows) {
		next if $window->{name} eq '(status)';
		next unless $window->{active}->{type} eq 'CHANNEL';

		if($window->{active}->{name} ~~ @enabled) {
			dp("Found! $window->{active}->{name}");

			$window->{active_server}->command("msg $window->{active}->{name} $sayline");
			dp('');
		}
	}
}

sub open_database_handle {
	$dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;
}

sub close_database_handle {
	$dbh->disconnect();
}

# if link allready in DB
sub if_link_in_db {
	my ($link, @rest) = @_;
	my $sth = $dbh->prepare("SELECT * from taivaanvahti4 where LINK = ?");
	$sth->bind_param(1, $link);
	$sth->execute();
	while(my @line = $sth->fetchrow_array) {
		#da(@line);
		$sth->finish();
		return 1;			# item allready found
	}
	$sth->finish();
	return 0;				# new item!
}

# Save new item to sqlite DB
sub saveToDB {
	my ($title, $link, $date, $desc, $havaintoid, $city, $havaintodate, @rest) = @_;
	my $pvm = time();

	my $sth = $dbh->prepare('INSERT or ignore INTO taivaanvahti4 VALUES(?,?,?,?,?,?,?,?,0)') or die DBI::errstr;
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

	Irssi::print("$myname: New data saved to database: $title");
}

sub createDB {
	open_database_handle();

	# Using FTS (full-text search)
	my $stmt = 'CREATE VIRTUAL TABLE taivaanvahti4 using fts4(PVM int,TITLE,LINK,PUBDATE,DESCRIPTION, CITY, HAVAINTOID int primary key, HAVAINTODATE, DELETED int default 0)';

	my $rv = $dbh->do($stmt);		# return value
	if($rv < 0) {
   		Irssi::print ("$myname: DBI Error: ". DBI::errstr);
	} else {
   		Irssi::print "$myname: Table created successfully";
	}
	close_database_handle();
}

sub searchDB {
	my $searchword = shift;
	open_database_handle();
	dp($searchword);
	my $stmt = "SELECT rowid,title,description FROM taivaanvahti4 where TITLE like ? or DESCRIPTION like ? or CITY like ?";
	my $sth = $dbh->prepare($stmt) or die DBI::errstr;
	$sth->bind_param(1, "%$searchword%");
	$sth->bind_param(2, "%$searchword%");
	$sth->bind_param(3, "%$searchword%");
	$sth->execute();
	
	my @line = ();
	my $index = 1;
	$resultarray = {};
	
	while(@line = $sth->fetchrow_array) {
		#push @{ $resultarray[$index]}, @line;
		#$resultarray->{$index} = "kakka";#@line;
		$resultarray->{$index} = {'rowid' => $line[0], 'title' => $line[1], 'desc' => $line[3]};
		$index++;
		da(@line);
	}
	close_database_handle();
	da($resultarray);
	dp("index: $index");
	
}

sub parseIDfromLink {
	my $link = shift;
	if ($link =~ /www.taivaanvahti.fi\/observations\/show\/(\d+)/gi) {
		return $1;
	}
	return 0;
}

sub owntrim {
	my $text = shift;
	# Special chars
	$text =~ s/^[\s\t]+//g;		# Remove trailing/beginning whitespace
	$text =~ s/[\s\t]+$//g;
	$text =~ s/[\s]+/ /g;		# convert multiple spaces to one
	$text =~ s/[\t]+//g;		# remove tabs within..
	$text =~ s/[\n\r]+//g;		# remove line feeds
	return $text;
}

sub parseMini {
	my ($type, $day, $month, $year, $hour, $minute, $city, @rest) = @_;
	dp("CITY: $city, TYPE: $type");
	my $isotime = $year."/".$month."/".$day. " ".$hour.":".$minute;
	my $unixtime = str2time($isotime);
	dp("isotime: $isotime, unixtime: $unixtime\n");
	my $returnitem;
	$returnitem->{'unixtime'} = $unixtime;
	$returnitem->{'city'} = $city;
	$returnitem->{'type'} = $type;
	return $returnitem;
}

sub parseExtraInfoFromLink {
	my $url = shift;
	#dp('parseExtraInfoFromLink url: '. $url);
	my $text = KaaosRadioClass::fetchUrl($url);
	
	my $date = '';
	if ($text =~ /<div class="main-heading">(.*?)<\/div>/gis) {
		my $heading = $1;
		#dp('heading: '. $heading);
		#$heading = KaaosRadioClass::replaceWeird($heading);
		#my $innerdata = KaaosRadioClass::replaceWeird($heading);
		if ($heading =~ /<h1>(.*?)<\/h1>/is) {
			my $innerdata = owntrim($1);
			#dp('innerdata: '. $innerdata);
			if ($innerdata =~ /(.*?) - (\d{1,2})\.(\d{1,2})\.(\d{4}) klo (\d{1,2})\.(\d{2}) - (\d{1,2})\.(\d{1,2})\.(\d{4}) klo (\d{1,2})\.(\d{2}) (.*?) </gis) {
				my $type = $1;
				my $pday = $2;
				my $pmonth = $3;
				my $pyear = $4;
				my $phour = $5;
				my $pminute = $6;
				my $city = $12;
				return parseMini($1, $2, $3, $3, $4, $6, $12);
				#dp("CITY: $city, TYPE: $type");
				#dp("datedata: ".$2);
				#dp("monthdata: ". $3);
				#my $isotime = $pyear."/".$pmonth."/".$pday. " ".$phour.":".$pminute;
				#my $unixtime = str2time($isotime);
				#dp("isotime: $isotime, unixtime: $unixtime\n");
				#my $returnitem;
				#$returnitem->{'unixtime'} = $unixtime;
				#$returnitem->{'city'} = $city;
				#$returnitem->{'type'} = $type;
				#return $returnitem;
			}
			elsif ($innerdata =~ /(.*?) - (\d{1,2})\.(\d{1,2})\.(\d{4}) klo (\d{1,2})\.(\d{2}) (.*?) </gis) {
				my $type = $1;
				my $pday = $2;
				my $pmonth = $3;
				my $pyear = $4;
				my $phour = $5;
				my $pminute = $6;
				my $city = $7;
				return parseMini($1, $2, $3, $4, $5, $6, $7);
				#dp("CITY: $city, TYPE: $type");
				#dp("datedata: ".$1);
				#dp("monthdata: ". $2);
				#my $isotime = $pyear."/".$pmonth."/".$pday. " ".$phour.":".$pminute;
				#dp("isotime: ".$isotime);
				#my $unixtime = str2time($isotime);
				#dp("isotime: $isotime, unixtime: $unixtime \n");
				#my $returnitem;
				#$returnitem->{'unixtime'} = $unixtime;
				#$returnitem->{'city'} = $city;
				#$returnitem->{'type'} = $type;
				#return $returnitem;
			}
		}
	} else {
		dp('NOT FOUND :(');
	}
	return '';
}

sub parseXML {
	open_database_handle();
	my $index = 0;
	foreach my $item (@{$parser->{items}}) {
		dp("item $index:");
		#da($item);
		
		#dp("item title: ". $item->{'title'});
		#dp("item link: ". $item->{'link'});
		#dp("item pubDate: ". $item->{'pubDate'});
		#dp("item description: ". $item->{'description'});
		#dp("item guid: ". $item->{guid});

		#da($extrainfo);
		$index++;
		if (if_link_in_db($item->{'link'}) == 0) {
			my $havaintoid = parseIDfromLink($item->{'link'});
			my $extrainfo = parseExtraInfoFromLink($item->{'link'});
			Irssi::print("$myname New item: $item->{title}");
			my $extrainfotime = defined($extrainfo->{'unixtime'}) ? $extrainfo->{'unixtime'} : 0;
			my $extrainfocity = defined($extrainfo->{'city'}) ? $extrainfo->{'city'} : '';

			saveToDB($item->{'title'}, $item->{'link'}, $item->{'pubDate'}, $item->{'description'}, $havaintoid, $extrainfocity, $extrainfotime);

			msg_to_channel($item->{'title'}, $item->{'link'}, $item->{'pubDate'}, $item->{'description'}, $havaintoid, $extrainfo);
		}
	}
	close_database_handle();
}

sub getXML {
	my $xmlFile = get($taivaanvahtiURL);
	$parser->parse($xmlFile);
}

# get all from RSS-feed
sub timerfunc {
	getXML();
	parseXML();
}

Irssi::command_bind('taivaanvahti_update', \&timerfunc);
Irssi::command_bind('taivaanvahti_search', \&searchDB);
Irssi::settings_add_str('taivaanvahti', 'taivaanvahti_enabled_channels', '');
Irssi::signal_add('message public', 'sig_msg_pub');
Irssi::signal_add('taivaanvahti_search_id', 'sig_taivaanvahti_search');

Irssi::timeout_add(1800000, 'timerfunc', undef);		# 30 minutes
#Irssi::timeout_add(5000, 'timerfunc', undef);			# 5 aseconds

Irssi::print("$myname v. $VERSION Loaded!");
Irssi::print("$myname new commands: /taivaanvahti_update, /taivaanvahti_search");
