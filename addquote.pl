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
my $publicurl = 'https://upload.8-b.fi/quotes.txt';
my $vitsiurl = 'https://upload.8-b.fi/vitsit.txt';

my $kanava = '#kaaosradio';
my $verkko = 'IRCnet';

my $db = Irssi::get_irssi_dir(). '/scripts/quotes.db';
my $vitsidb = Irssi::get_irssi_dir(). '/scripts/vitsit.db';
my $DEBUG = 1;

use vars qw($VERSION %IRSSI);
$VERSION = '20220716';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'addquote.pl',
	description => 'Add quote or joke to database & textfile from channel.',
	license     => 'Public Domain',
	url         => $publicurl,
	changed     => $VERSION,
);

unless (-e $db) {
	unless(open FILE, '>', $db) {
		print($IRSSI{name}. "> Fatal error: Unable to create file: $db");
		die;
	}
	close FILE;
	createDB();
	print($IRSSI{name}. '> Quotes Database file created.');
}

unless (-e $vitsidb) {
	unless(open FILE, '>', $vitsidb) {
		print($IRSSI{name}. "> Fatal error: Unable to create file: $vitsidb");
		die;
	}
	close FILE;
	createVitsiDB();
	print($IRSSI{name}. '> Jokes Database file created.');
}

sub event_privmsg {
	my ($server, $msg, $nick, $address) = @_;
	return if ($nick eq $server->{nick});	#self-test
	parseQuote($msg, $nick, $nick, $server);
	return;
}

# msg to $kanava
sub sayit {
	my ($msg) = @_;
	my @windows = Irssi::windows();
	foreach my $window (@windows) {
		if ($window->{active_server}->{tag} eq $verkko) {
			if ($window->{active}->{type} eq 'CHANNEL' && $window->{active}->{name} eq $kanava) {
				$window->{active_server}->command("MSG $kanava $msg");
				return;
			}
		}
	}
	return;
}

sub parseQuote {
	my ($msg, $nick, $target, $server, @rest) = @_;
	if($msg =~ /^!aq\s(.{1,470})/gi) {
		my $uusiquote = decode('UTF-8', $1);
		my $pituus = length $uusiquote;
		if ($pituus < 470) {
			return if KaaosRadioClass::floodCheck();
			KaaosRadioClass::addLineToFile($tiedosto, $uusiquote);
			saveToDB($db, 'QUOTES', $nick, $uusiquote, $target);
			print($IRSSI{name}."> $msg request from $nick") if $DEBUG;
			$server->command("msg $nick quote lisätty! $publicurl");
			$server->command("msg $target :)");
		} else {
			print($IRSSI{name}."> $msg request from $nick (too long!)");
			$server->command("msg $nick quote liiian pitkä ($pituus)! max. about 470 merkkiä!");
		}
	} elsif ($msg =~ /^!rq (.{3,15})/gi) {
		my $searchword = decode('UTF-8', $1);
		dp(__LINE__." searchword: $searchword");
		my $data = KaaosRadioClass::readTextFile($tiedosto);
		my $sql = 'SELECT quote from quotes where quote like ?';
		my @answers;
		LINE: for (@$data) {
			if ($_ =~ /$searchword/gi ) {
				chomp (my $rimpsu = $_);
				push @answers, $rimpsu;
			}
		}
		my $amount_a = scalar @answers;
		if ($amount_a > 0) {
			dp(__LINE__." LÖYTYI!");
			my $sayline = rand_line(@answers);
			$server->command("MSG $target $sayline");
		} else {
			dp(__LINE__." EI LÖYTYNYT");
			da(@answers);

		}
	} elsif ($msg =~ /^!rq/gi) {
		my $data = KaaosRadioClass::readTextFile($tiedosto);
		my $amount = @$data;
		my $rand = int(rand($amount));
		my $linecount = -1;
		dp("amount: $amount, rand: $rand");
		LINE: for (@$data) {
			$linecount++;
			next LINE unless ($rand == $linecount);
			if($rand == $linecount) {
				chomp (my $rimpsu = $_);
				$server->command("MSG $target $rimpsu");
				print($IRSSI{name}."> vastasi: '$rimpsu' for $nick on channel: $target");
				last;
			}
		}
	} elsif ($msg =~ /^!aj (.*)/gi) {
		my $uusivitsi = decode('UTF-8', $1);
		return if KaaosRadioClass::floodCheck();
		KaaosRadioClass::addLineToFile($vitsitiedosto, $uusivitsi);
		saveToDB($vitsidb, 'JOKES', $nick, $uusivitsi, $target);
		print($IRSSI{name}."> $msg request from $nick") if $DEBUG;
		$server->command("msg $nick vitsi lisätty! $vitsiurl");
		$server->command("msg $target xd");
	} elsif ($msg =~ /^!rj/gi) {
		my $data = KaaosRadioClass::readTextFile($vitsitiedosto);
		dp($data);
		my $amount = @$data;
		my $rand = int(rand($amount));
		my $linecount = -1;
		dp("amount: $amount, rand: $rand");
		LINE: for (@$data) {
			$linecount++;
			next LINE unless ($rand == $linecount);
			if($rand == $linecount) {
				chomp (my $rimpsu = $_);
				$server->command("MSG $target $rimpsu");
				print($IRSSI{name}."> vastasi: '$rimpsu' for $nick on channel: $target");
				last;
			}
		}
	}
	return;
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
			if($rand == $linecount) {
				chomp (my $rimpsu = $_);
				print($IRSSI{name}."> löytyi: $rimpsu");
				return $rimpsu;
				last;
			}
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
	if ($error = KaaosRadioClass::writeToDB($db, 'CREATE VIRTUAL TABLE QUOTES using fts4(NICK, PVM, QUOTE,CHANNEL)')) {
		print $IRSSI{name}.'> '.$error;
		die;
	}
	print $IRSSI{name}.'> Table created successfully';
	return;
}

sub createVitsiDB {
	my $error = '';
	if ($error = KaaosRadioClass::writeToDB($vitsidb, 'CREATE VIRTUAL TABLE JOKES using fts4(NICK, PVM, JOKE, CHANNEL)')) {
		print $IRSSI{name}.'> '.$error;
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
	Irssi::print($IRSSI{name}.": Saved to database. $quote");
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

Irssi::signal_add('message public', 'event_pubmsg');
Irssi::signal_add('message private', 'event_privmsg');
