use Encode qw/encode decode/;

my $DEBUG = 0;
use Irssi;
use DBI qw(:sql_types);
use warnings;
use strict;
use utf8;
binmode(STDOUT, ":utf8");
binmode(STDIN, ":utf8");
use KaaosRadioClass;		# LAama1 30.12.2016
my $myname = "addquote.pl";
my $tiedosto = "/home/laama/public_html/quotes.txt";
my $publicurl = "http://lamanzi.vhosti.fi/quotes.txt";
my $db = Irssi::get_irssi_dir(). "/scripts/quotes.db";

use vars qw($VERSION %IRSSI);
$VERSION = "20180106";
%IRSSI = (
	authors     => "LAama1",
	contact     => "ircnet: LAama1",
	name        => "addquote.pl",
	description => "Add quote to database & textfile from channel.",
	license     => "Public Domain",
	url         => $publicurl,
	changed     => $VERSION
);


unless (-e $db) {
	unless(open FILE, '>'.$db) {
		Irssi::print("$myname: Unable to create file: $db");
		die;
	}
	close FILE;
	createDB();
	Irssi::print("$myname: Database file created.");
}

sub event_privmsg {
	my ($server, $msg, $nick, $address) = @_;

	my ($target, $text) = $msg =~ /^(\S*)\s:(.*)/;
	return if ($nick eq $server->{nick});	#self-test
	dp("priv, target: $target, msg: $msg");
	parseQuote($msg, $nick, "priv", $server);
}

sub parseQuote {
	my ($msg, $nick, $target, $server, @rest) = @_;
	#dp("parseQuote: $msg");
	if($msg =~ /^!aq\s(.{1,470})/gi)
	{
		dp("parseQuote nick: $nick");
		my $uusiquote = $1;
		my $pituus = length($uusiquote);
		if ($pituus < 470) {
			return if KaaosRadioClass::floodCheck();
			KaaosRadioClass::addLineToFile($tiedosto, $uusiquote);
			saveToDB($nick, $uusiquote, $target);
			Irssi::print("$myname: $msg request from $nick");
			$server->command("msg $nick quote lisätty! $publicurl");
		} else {
			Irssi::print("$myname: $msg request from $nick (too long!)");
			$server->command("msg $nick quote liiian pitkä ($pituus)! max. about 470 merkkiä!");
		}
	}	
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
	dp("pub: nick: $nick, msg: $msg, target: $target");
	parseQuote($msg, $nick, $target, $server);
}

sub createDB {
    my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;
	my $stmt = qq(CREATE TABLE QUOTES (NICK TEXT, PVM INT, QUOTE TEXT not null,CHANNEL TEXT));
	#my $stmt = qq(CREATE TABLE QUOTES using fts4(NICK, PVM, QUOTE,CHANNEL));
	my $rv = $dbh->do($stmt);
	if($rv < 0) {
   		Irssi::print DBI::errstr;
	} else {
   		Irssi::print "$myname: Table created successfully";
	}
	$dbh->disconnect();
}


# Save to sqlite DB
sub saveToDB {
	my ($nick, $quote, $channel, @rest) = @_;
	my $pvm = time();

	my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;
	my $sth = $dbh->prepare("INSERT INTO quotes VALUES(?,?,?,?)") or die DBI::errstr;
	$sth->bind_param(1, $nick);
	$sth->bind_param(2, $pvm, { TYPE => SQL_INTEGER });
	$sth->bind_param(3, $quote);
	$sth->bind_param(4, $channel);
	$sth->execute;
	$sth->finish();
	$dbh->disconnect();
	Irssi::print("$myname: Quote saved to database. $quote");
}

sub dp {
	return unless $DEBUG == 1;
	Irssi::print("$myname debug: @_");
}

Irssi::signal_add('message public', 'event_pubmsg');
#Irssi::signal_add('event privmsg', 'event_privmsg');
Irssi::signal_add('message private', 'event_privmsg');
