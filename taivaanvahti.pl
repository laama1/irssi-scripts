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

my $DEBUG = 1;
my $myname = "taivaanvahti.pl";
my $db = Irssi::get_irssi_dir() . "/scripts/taivaanvahti.sqlite";

my $dbh;		# database handle

my $count = 0;
my $resultarray = {};
my $parser = new XML::RSS();
#$parser->setHandlers(Char => \&char_handler,
#					 Default => \&default_handler);

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
		$desc = "";
	}
	my $sayline = "$title: ($date) $link $desc";

	my @windows = Irssi::windows();
	foreach my $window (@windows) {
		#dp("window:");
		#da($window);
		next if $window->{name} eq "(status)";
		next unless $window->{active}->{type} eq "CHANNEL";
		dp("window name:");
		dp($window->{active}->{name});
		if($window->{active}->{name} ~~ @enabled) {
			dp("Found! $window->{active}->{name}");
			dp("what if...");
			da($window);
			#$window->command("$window kakka.", "msg");
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
	my $sth = $dbh->prepare("SELECT * from taivaanvahti where LINK = ?");
	$sth->bind_param(1, $link);
	$sth->execute();
	while(my @line = $sth->fetchrow_array) {
		da(@line);
		$sth->finish();
		return 1;			# item allready found
	}
	$sth->finish();
	return 0;				# new item!
}

# Save new item to sqlite DB
sub saveToDB {
	my ($title, $link, $date, $desc, @rest) = @_;
	my $pvm = time();

	my $sth = $dbh->prepare("INSERT INTO taivaanvahti VALUES(?,?,?,?,?,0)") or die DBI::errstr;
	$sth->bind_param(1, $pvm);
	$sth->bind_param(2, $title);
	$sth->bind_param(3, $link);
	$sth->bind_param(4, $date);
	$sth->bind_param(5, $desc);
	$sth->execute;
	$sth->finish();

	Irssi::print("$myname: New data saved to database: $title");
}

sub createDB {
	open_database_handle();

	# Using FTS (full-text search)
	my $stmt = "CREATE VIRTUAL TABLE taivaanvahti using fts4(PVM,TITLE,LINK,PUBDATE,DESCRIPTION,DELETED)";
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
	my $stmt = "SELECT rowid,title,description FROM taivaanvahti where TITLE like ? or DESCRIPTION like ?";
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
		$resultarray->{$index} = {'rowid' => @line[0], 'title' => @line[1], 'desc' => @line[3]};
		$index++;
		da(@line);
	}
	close_database_handle();
	da($resultarray);
	dp("index: $index");
	
}

sub getXML {
	my $xmlFile = get("https://www.taivaanvahti.fi/observations/rss");
	$parser->parse($xmlFile);
	#da($parser->{'items'});
	my $index = 0;
	open_database_handle();
	foreach my $item (@{$parser->{items}}) {
		#dp("item $index:");
		#da($item);
		
		#dp("item title: ". $item->{'title'});
		#dp("item link: ". $item->{'link'});
		#dp("item pubDate: ". $item->{'pubDate'});
		#dp("item description: ". $item->{'description'});
		#dp("item guid: ". $item->{guid});
		$index++;
		if (read_from_DB($item->{'link'}) == 0) {
			dp("New item: $item->{title}");
			saveToDB($item->{'title'}, $item->{'link'}, $item->{'pubDate'}, $item->{'description'});
			msg_to_channel($item->{'title'}, $item->{'link'}, $item->{'pubDate'}, $item->{'description'});
		}
	}
	close_database_handle();

}

sub timerfunc {
	getXML();
}

Irssi::command_bind('taivaanvahtisearch', \&searchDB);
Irssi::settings_add_str('taivaanvahti', 'taivaanvahti_enabled_channels', '');
Irssi::signal_add('message public', 'sig_msg_pub');

Irssi::timeout_add(1800000, 'timerfunc', undef);		# 30 minutes
#Irssi::timeout_add(5000, 'timerfunc', undef);			# 5 aseconds

Irssi::print("$myname v. $VERSION Loaded!");
