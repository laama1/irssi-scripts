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
$VERSION = "2018-02-18";
%IRSSI = (
	authors     => "LAama1",
	contact     => "ircnet: LAama1",
	name        => "taivaanvahti",
	description => "Fetch new data from Taivaanvahti.fi",
	license     => "Public Domain",
	url         => "http://www.kaaosradio.fi",
	changed     => $VERSION
);

my $DEBUG = 0;
my $myname = "taivaanvahti.pl";
my $db = Irssi::get_irssi_dir() . "/scripts/taivaanvahti.sqlite";

my $dbh;		# database handle

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
	return unless $DEBUG;
	Irssi::print("$myname: @_");
}

sub da {
	return unless $DEBUG;
	Irssi::print("$myname-debug array:");
	Irssi::print Dumper (@_);
}

sub print_help {
	my ($server, $targe, @rest) = @_;
	my $help = "Taivaanvahti -skripti hakee ajoittain uusimmat havainnot sivulta
	taivaanvahti.fi.";
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

	}

}

sub msg_to_channel {
	my ($title, $link, $date, $desc, @rest) = @_;
    my $enabled_raw = Irssi::settings_get_str('taivaanvahti_enabled_channels');
    my @enabled = split(/ /, $enabled_raw);

	#msg_to_channel($item->{'title'}, $item->{'link'}, $item->{'pubDate'}, $item->{'description'});
	#if (exists($desc) && length($desc) > 150) {
	if (defined($desc) && length($desc) > 150) {
		$desc = substr($desc, 0, 150);
		$desc .= "...";
	} else {
		#$desc = "";
	}
	my $sayline = "$title: ($date) $link $desc";

	my @windows = Irssi::windows();
	foreach my $window (@windows) {
		next if $window->{name} eq "(status)";
		next unless $window->{active}->{type} eq "CHANNEL";
		#dp("window name:");
		#dp($window->{active}->{name});
		if($window->{active}->{name} ~~ @enabled) {
			dp("Found! $window->{active}->{name}");
			#dp("what if...");
			#da($window);
			$window->{active_server}->command("msg $window->{active}->{name} $sayline");
			dp("");
		}
	}
}

sub open_database_handle {
	$dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;
}

sub close_database_handle {
	$dbh->disconnect();
}

sub read_from_DB {
	my ($link, @rest) = @_;
	my $sth = $dbh->prepare("SELECT * from taivaanvahti3 where LINK = ?");
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
	my ($title, $link, $date, $desc, $havaintoid, $havaintodate, @rest) = @_;
	my $pvm = time();

	my $sth = $dbh->prepare("INSERT INTO taivaanvahti3 VALUES(?,?,?,?,?,?,?,0)") or die DBI::errstr;
	$sth->bind_param(1, $pvm);
	$sth->bind_param(2, $title);
	$sth->bind_param(3, $link);
	$sth->bind_param(4, $date);
	$sth->bind_param(5, $desc);
	$sth->bind_param(6, $havaintoid);
	$sth->bind_param(7, $havaintodate);
	$sth->execute;
	$sth->finish();

	Irssi::print("$myname: New data saved to database: $title");
}

sub createDB {
	open_database_handle();

	# Using FTS (full-text search)
	my $stmt = "CREATE VIRTUAL TABLE taivaanvahti3 using fts4(PVM int,TITLE,LINK,PUBDATE,DESCRIPTION, HAVAINTOID int, HAVAINTODATE, DELETED int default 0)";
	#my $stmt = "CREATE VIRTUAL TABLE taivaanvahti using fts4(PVM,TITLE,LINK PRIMARY KEY,PUBDATE,DESCRIPTION,DELETED)";

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
	my $stmt = "SELECT rowid,title,description FROM taivaanvahti2 where TITLE like ? or DESCRIPTION like ?";
	my $sth = $dbh->prepare($stmt) or die DBI::errstr;
	$sth->bind_param(1, "%$searchword%");
	$sth->bind_param(2, "%$searchword%");
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

sub parseExtraInfoFromLink {
	my $url = shift;
	my $text = KaaosRadioClass::fetchUrl($url);
	my $date = "";
	if ($text =~ /<div class="main-heading">(.*?)<\/div>/gis) {
		my $heading = $1;
		$heading = KaaosRadioClass::replaceWeird($heading);
		if ($heading =~ /<h1>(.*?)<\/h1>/gis) {
			my $innerdata = $1;
			#dp("GOT DEPER: ".$innerdata);
			if ($innerdata =~ /(\d{1,2})\.(\d{1,2})\.(\d{4}) klo (\d{1,2})\.(\d{2})/gis) {
				my $pday = $1;
				my $pmonth = $2;
				my $pyear = $3;
				my $phour = $4;
				my $pminute = $5;
				dp("datedata: ".$1);
				dp("monthdata: ". $2);
				my $isotime = $pyear."/".$pmonth."/".$pday. " ".$phour.":".$pminute;
				dp("isotime: ".$isotime);
				my $unixtime = str2time($isotime);
				dp("unixtime: $unixtime");
				return $unixtime;
			}
		}
	} else {
		dp("NOT FOUND :(");
	}

}

sub getXML {
	my $xmlFile = get("https://www.taivaanvahti.fi/observations/rss");
	$parser->parse($xmlFile);
	#da($parser->{'items'});
	my $index = 0;
	open_database_handle();
	foreach my $item (@{$parser->{items}}) {
		dp("item $index:");
		#da($item);
		my $havaintoid = parseIDfromLink($item->{'link'});
		#dp("item title: ". $item->{'title'});
		#dp("item link: ". $item->{'link'});
		#dp("item pubDate: ". $item->{'pubDate'});
		#dp("item description: ". $item->{'description'});
		#dp("item guid: ". $item->{guid});
		my $extrainfo = parseExtraInfoFromLink($item->{'link'});
		$index++;
		if (read_from_DB($item->{'link'}) == 0) {
			Irssi::print("$myname New item: $item->{title}");
			saveToDB($item->{'title'}, $item->{'link'}, $item->{'pubDate'}, $item->{'description'}, $havaintoid, $extrainfo);
			msg_to_channel($item->{'title'}, $item->{'link'}, $item->{'pubDate'}, $item->{'description'}, $havaintoid, $extrainfo);
		}
	}
	close_database_handle();

}

# get all from RSS-feed
sub timerfunc {
	getXML();
}
Irssi::command_bind('taivaanvahti_update', \&timerfunc);
Irssi::command_bind('taivaanvahti_search', \&searchDB);
Irssi::settings_add_str('taivaanvahti', 'taivaanvahti_enabled_channels', '');
Irssi::signal_add('message public', 'sig_msg_pub');

Irssi::timeout_add(1800000, 'timerfunc', undef);		# 30 minutes
#Irssi::timeout_add(5000, 'timerfunc', undef);			# 5 aseconds

Irssi::print("$myname v. $VERSION Loaded!");
Irssi::print("$myname new commands: /taivaanvahti_update, /taivaanvahti_search");
