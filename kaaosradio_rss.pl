use warnings;
use strict;
use Irssi;
use utf8;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;		# LAama1 9.5.2018
use XML::RSS;
use LWP::Simple;
#use XML::RSS::Parser;
use Data::Dumper;
use DBI;
use HTTP::Date;
use HTML::Entities qw(decode_entities);

# http://www.perl.com/pub/1998/12/cooper-01.html


use vars qw($VERSION %IRSSI);
$VERSION = "2018-05-11";
%IRSSI = (
	authors     => "LAama1",
	contact     => "ircnet: LAama1",
	name        => "kaaosradio_aikataulu RSS-feed",
	description => "Fetch new data from kaaosradio.fi/Aikataulu",
	license     => "Public Domain",
	url         => "http://www.kaaosradio.fi",
	changed     => $VERSION
);

my $DEBUG = 1;
my $myname = "kaaosradio_rss.pl";
my $db = Irssi::get_irssi_dir() . "/scripts/kaaosradio_aikataulu.sqlite";
my $rssurl = "http://kaaosradio.fi/kalenteri6/rssfeed.php?cal=kaaos";
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
	my $help = "kaaosradio_rss -skripti hakee ajoittain uusimmat kalenterimerkinnät sivulta kaaosradio.fi/Aikataulu ja tulostaa ne kanavalle.";
}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;

    my $enabled_raw = Irssi::settings_get_str('kaaosradio_aikataulu_enabled_channels');
    my @enabled = split(/ /, $enabled_raw);
    return unless grep(/$target/, @enabled);

	if ($msg =~ /^[\.\!]help\b/i) {
		print_help($server, $target);
		return;
	}

	if($msg =~ /^!kaaosradio/gi) {
		getXML();
	}

}

sub msg_to_channel {
	#my ($title, $link, $date, $desc, $forumlink, @rest) = @_;
	my ($title, $link, @rest) = @_;
    my $enabled_raw = Irssi::settings_get_str('kaaosradio_aikataulu_enabled_channels');
    my @enabled = split(/ /, $enabled_raw);

	#if (defined($desc) && length($desc) > 150) {
	#	$desc = substr($desc, 0, 150);
	#	$desc .= "...";
	#} else {
		#$desc = "";
	#}
	#my $sayline = "$title: ($date) $link $desc";
	#my $sayline = "$title: $link ($forumlink)";
	my $sayline = "$title -> $link";

	my @windows = Irssi::windows();
	foreach my $window (@windows) {
		next if $window->{name} eq "(status)";
		next unless $window->{active}->{type} eq "CHANNEL";
		if($window->{active}->{name} ~~ @enabled) {
			dp("Found! $window->{active}->{name}");
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
	my $sth = $dbh->prepare("SELECT * from kaaosradio_aikataulu where GUID = ?");
	$sth->bind_param(1, $link);
	$sth->execute();
	while(my @line = $sth->fetchrow_array) {
		$sth->finish();
		return 1;			# item allready found
	}
	$sth->finish();
	return 0;				# new item!
}

# Save new item to sqlite DB
sub saveToDB {
	my ($title, $link, $date, $desc, $guid, @rest) = @_;
	my $pvm = time();
	my $sth = $dbh->prepare("INSERT INTO kaaosradio_aikataulu VALUES(?,?,?,?,?,?,0)") or die DBI::errstr;
	$sth->bind_param(1, $pvm);
	$sth->bind_param(2, $title);
	$sth->bind_param(3, $link);
	$sth->bind_param(4, $date);
	$sth->bind_param(5, $desc);
	$sth->bind_param(6, $guid);
	$sth->execute;
	$sth->finish();

	Irssi::print("$myname: New data saved to database: $title");
}

sub createDB {
	open_database_handle();

	# Using FTS (full-text search)
	my $stmt = "CREATE VIRTUAL TABLE kaaosradio_aikataulu using fts4(PVM int,TITLE,LINK,PUBDATE,DESCRIPTION, GUID int, DELETED int default 0)";

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
	my $stmt = "SELECT rowid,title,description FROM kaaosradio_aikataulu where TITLE like ? or DESCRIPTION like ?";
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

sub parseIDfromGuid {
	my ($url, @rest) = @_;
	if ($url =~ /\/\?evt=(\d+)/) {	# .fi/?p=3369
		return $1;
	}
}

sub getXML {
	my ($xmlFile, @rest) = KaaosRadioClass::fetchUrl($rssurl);
	$parser->parse($xmlFile);
	#da($parser->{'items'});
	my $index = 0;
	open_database_handle();
	foreach my $item (@{$parser->{items}}) {
		dp("item $index:");
		#da($item);
		#my $havaintoid = parseIDfromLink($item->{'link'});
		dp("item title: ". decode_entities($item->{'title'}));
		dp("item link: ". $item->{'link'});
		dp("item pubDate: ". $item->{'pubDate'});
		dp("item description: ". decode_entities($item->{'description'}));
		#dp("item guid: ". $item->{guid});
		my $id = parseIDfromGuid($item->{guid});
		dp("item guid: ". $id);
		my $desc = decode_entities($item->{'description'});
		$desc =~ s/Lisää(.*)$//i;
		dp("item description: ".$desc);

		my $desc = decode_entities($item->{'description'} =~ s/Lisää(.*)$//i);
		$index++;
		#if (read_from_DB($item->{'link'}) == 0) {
		if (read_from_DB($id) == 0) {
			dp("^new item $index");
			#Irssi::print("$myname New item: $item->{title}");
			saveToDB(decode_entities($item->{'title'}), $item->{'link'}, $item->{'pubDate'}, $desc, $id);
			#msg_to_channel(decode_entities($item->{'title'}), $item->{'link'}, $item->{'pubDate'}, $desc, $forumlink);
			msg_to_channel(decode_entities($item->{'title'}), $item->{'link'});
		}
	}
	close_database_handle();

}

# get all from RSS-feed
sub timerfunc {
	getXML();
}

Irssi::command_bind('kaaosradio_aikataulu_update', \&timerfunc);
Irssi::command_bind('kaaosradio_aikataulu_search', \&searchDB);
Irssi::settings_add_str('kaaos', 'kaaosradio_aikataulu_enabled_channels', '');
Irssi::signal_add('message public', 'sig_msg_pub');

Irssi::timeout_add(900000, 'timerfunc', undef);		# 30 minutes
#Irssi::timeout_add(5000, 'timerfunc', undef);			# 5 aseconds

Irssi::print("$myname v. $VERSION Loaded!");
Irssi::print("$myname new commands: /kaaosradio_aikataulu_update, /kaaosradio_aikataulu_search");
