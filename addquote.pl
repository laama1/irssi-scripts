use warnings;
use strict;
use Encode qw/encode decode/;
use Irssi;
use Data::Dumper;
use DBI qw(:sql_types);

use utf8;
binmode STDOUT, ':utf8';
binmode STDIN, ':utf8';
use KaaosRadioClass;		# LAama1 30.12.2016

my $tiedosto = '/mnt/music/quotes.txt';
my $vitsitiedosto = '/mnt/music/vitsit.txt';
my $quoteurl = 'https://ul.8-b.fi/quotes.txt';
my $vitsiurl = 'https://ul.8-b.fi/vitsit.txt';

my $quotedb = Irssi::get_irssi_dir(). '/scripts/quotes.db';
my $vitsidb = Irssi::get_irssi_dir(). '/scripts/vitsit.db';
my $DEBUG = 0;

use vars qw($VERSION %IRSSI);
$VERSION = '20220716';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'addquote.pl',
	description => 'Add quote or joke to database & textfile from channel.',
	license     => 'Public Domain',
	url         => 'https://bot.8-b.fi',
	changed     => $VERSION,
);

unless (-e $quotedb) {
	unless(open FILE, '>', $quotedb) {
		prindw("Fatal error: Unable to create file: $quotedb");
		die;
	}
	close FILE;
	createDB();
	prind('Quotes Database file created.');
}

unless (-e $vitsidb) {
	unless(open FILE, '>', $vitsidb) {
		prindw("Fatal error: Unable to create file: $vitsidb");
		die;
	}
	close FILE;
	createVitsiDB();
	prind('Jokes Database file created.');
}

sub event_privmsg {
	my ($server, $msg, $nick, $address) = @_;
	return if ($nick eq $server->{nick});	#self-test
	parseQuote($msg, $nick, $nick, $server);
	return;
}

sub parseQuote {
	my ($msg, $nick, $target, $server, @rest) = @_;
	if($msg =~ /^!aq (.{1,470})/gi) {
		my $uusiquote = decode('UTF-8', $1);
		return if KaaosRadioClass::floodCheck();
		KaaosRadioClass::addLineToFile($tiedosto, $uusiquote);
		saveToDB($quotedb, 'QUOTES', $nick, $uusiquote, $target);
		prind("$msg -- request from $nick on channel: $target");
		$server->command("msg $nick quote lisätty! $quoteurl");
		$server->command("msg $target :)");
	} elsif ($msg =~ /^!rq (.{3,15})/gi) {
		my $searchword = decode('UTF-8', $1);
		return if KaaosRadioClass::floodCheck();
		my @answers = search_from_file($tiedosto, $searchword);
		if (my $rimpsu = rand_line(@answers)) {
			$server->command("MSG $target $rimpsu");
			prind("answered: '$rimpsu' for $nick on channel: $target");
		}
	} elsif ($msg =~ /^!rq/gi) {
		return if KaaosRadioClass::floodCheck();
		my $data = KaaosRadioClass::readTextFile($tiedosto);
		if (my $rimpsu = rand_line(@$data)) {
			$server->command("MSG $target $rimpsu");
			prind("answered: '$rimpsu' for $nick on channel: $target");
		}
	} elsif ($msg =~ /^!aj (.*)/gi) {
		my $uusivitsi = decode('UTF-8', $1);
		return if KaaosRadioClass::floodCheck();
		KaaosRadioClass::addLineToFile($vitsitiedosto, $uusivitsi);
		saveToDB($vitsidb, 'JOKES', $nick, $uusivitsi, $target);
		prind("$msg request from $nick") if $DEBUG;
		$server->command("msg $nick vitsi lisätty! $vitsiurl");
		$server->command("msg $target xD");
	} elsif ($msg =~ /^!rj (.{3,15})/gi) {
		my $searchword = decode('UTF-8', $1);
		return if KaaosRadioClass::floodCheck();
		my @answers = search_from_file($vitsitiedosto, $searchword);
		if (my $rimpsu = rand_line(@answers)) {
			$server->command("MSG $target $rimpsu");
			prind("answered: '$rimpsu' for $nick on channel: $target");
		}
	} elsif ($msg =~ /^!rj/gi) {
		return if KaaosRadioClass::floodCheck();
		my $data = KaaosRadioClass::readTextFile($vitsitiedosto);
		if (my $rimpsu = rand_line(@$data)) {
			$server->command("MSG $target $rimpsu");
			prind("answered: '$rimpsu' for $nick on channel: $target");
		}
	}
	return;
}

sub search_from_file {
	my ($filename, $searchword) = @_;
	my $textdata = KaaosRadioClass::readTextFile($filename);
	my @searchresults;
	LINE: for (@$textdata) {
		if ($_ =~ /$searchword/gi) {
			chomp (my $found = $_);
			push @searchresults, $found;
			dp("Löytyi: $found");
		}
	}
	return @searchresults;
}

# return random line from array
sub rand_line {
	my (@values, @rest) = @_;
	my $amount = scalar @values;
	my $rand = int rand $amount;
	my $linecount = -1;
  	LINEFOR: for (@values) {
		$linecount++;
		next LINEFOR unless ($rand == $linecount);
		chomp (my $rimpsu = $_);
		return $rimpsu unless $rimpsu eq '';
		last;
	}
	return undef;
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
	parseQuote($msg, $nick, $target, $server);
	return;
}

sub createDB {
	my $error = '';
	if ($error = KaaosRadioClass::writeToDB($quotedb, 'CREATE VIRTUAL TABLE QUOTES using fts4(NICK, PVM, QUOTE,CHANNEL)')) {
		prindw($error);
		die;
	}
	prind('Table created successfully');
	return;
}

sub createVitsiDB {
	my $error = '';
	if ($error = KaaosRadioClass::writeToDB($vitsidb, 'CREATE VIRTUAL TABLE JOKES using fts4(NICK, PVM, JOKE, CHANNEL)')) {
		prindw($error);
		die;
	}
	return;
}

# Save to sqlite DB
sub saveToDB {
	my ($dbname, $table, $nick, $quote, $channel, @rest) = @_;
	my $pvm = time;

	my $dbh = DBI->connect("dbi:SQLite:dbname=$dbname", "", "", { RaiseError => 1 },) or die DBI::errstr;
	my $sth = $dbh->prepare("INSERT INTO $table VALUES(?,?,?,?)") or die DBI::errstr;
	$sth->bind_param(1, $nick);
	$sth->bind_param(2, $pvm, { TYPE => SQL_INTEGER });
	$sth->bind_param(3, $quote);
	$sth->bind_param(4, $channel);
	$sth->execute;
	$sth->finish();
	$dbh->disconnect();
	prind("Saved to database. $quote");
	return;
}

sub dp {
	return unless $DEBUG == 1;
	Irssi::print($IRSSI{name}." debug: @_");
	return;
}

sub da {
	return unless $DEBUG == 1;
	Irssi::print('addquote: ');
	Irssi::print(Dumper(@_));
	return;
}

sub prind {
	my ($text, @rest) = @_;
	print "\0038" . $IRSSI{name} . ">\003 " . $text;
}

sub prindw {
	my ($text, @rest) = @_;
	print "\0034" . $IRSSI{name} . ">\003 " . $text;
}

Irssi::signal_add('message public', 'event_pubmsg');
Irssi::signal_add('message private', 'event_privmsg');
