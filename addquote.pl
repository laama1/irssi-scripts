use warnings;
use strict;
use Encode qw/encode decode/;
use Irssi;
use Data::Dumper;
use DBI qw(:sql_types);

use utf8;
binmode(STDOUT, ":utf8");
binmode(STDIN, ":utf8");
use KaaosRadioClass;		# LAama1 30.12.2016

#my $tiedosto = $ENV{HOME}.'/public_html/quotes.txt';
my $tiedosto = '/var/www/html/quotes/quotes.txt';
my $publicurl = 'http://lamaz.bot.nu/quotes.txt';

my $kanava = '#kaaosradio';
my $verkko = 'IRCnet';

my $db = Irssi::get_irssi_dir(). '/scripts/quotes.db';
my $DEBUG = 1;

use vars qw($VERSION %IRSSI);
$VERSION = '20190703';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'addquote.pl',
	description => 'Add quote to database & textfile from channel.',
	license     => 'Public Domain',
	url         => $publicurl,
	changed     => $VERSION,
);


unless (-e $db) {
	unless(open FILE, '>', $db) {
		Irssi::print($IRSSI{name}. ": Unable to create file: $db");
		die;
	}
	close FILE;
	createDB();
	Irssi::print($IRSSI{name}. ': Database file created.');
}

sub event_privmsg {
	my ($server, $msg, $nick, $address) = @_;
	#my ($target, $text) = $msg =~ /^(\S*)\s:(.*)/;
	return if ($nick eq $server->{nick});	#self-test
	parseQuote($msg, $nick, 'priv', $server);
	return;
}

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
	if($msg =~ /^!aq\s(.{1,470})/gi)
	{
		#dp("parseQuote nick: $nick");
		my $uusiquote = $1;
		my $pituus = length $uusiquote;
		if ($pituus < 470) {
			return if KaaosRadioClass::floodCheck();
			KaaosRadioClass::addLineToFile($tiedosto, $uusiquote);
			saveToDB($nick, $uusiquote, $target);
			Irssi::print($IRSSI{name}.": $msg request from $nick") if $DEBUG;
			$server->command("msg $nick quote lisätty! $publicurl");
			sayit(':)');
		} else {
			Irssi::print($IRSSI{name}.": $msg request from $nick (too long!)");
			$server->command("msg $nick quote liiian pitkä ($pituus)! max. about 470 merkkiä!");
		}
	}
	return;
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
	parseQuote($msg, $nick, $target, $server);
	return;
}

sub createDB {
    my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;
	my $stmt = qq(CREATE VIRTUAL TABLE QUOTES using fts4(NICK, PVM, QUOTE,CHANNEL));
	my $rv = $dbh->do($stmt);
	if($rv < 0) {
   		Irssi::print DBI::errstr;
	} else {
   		Irssi::print $IRSSI{name}.": Table created successfully";
	}
	$dbh->disconnect();
	return;
}


# Save to sqlite DB
sub saveToDB {
	my ($nick, $quote, $channel, @rest) = @_;
	my $pvm = time;

	my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;
	my $sth = $dbh->prepare("INSERT INTO quotes VALUES(?,?,?,?)") or die DBI::errstr;
	$sth->bind_param(1, $nick);
	$sth->bind_param(2, $pvm, { TYPE => SQL_INTEGER });
	$sth->bind_param(3, $quote);
	$sth->bind_param(4, $channel);
	$sth->execute;
	$sth->finish();
	$dbh->disconnect();
	Irssi::print($IRSSI{name}.": Quote saved to database. $quote");
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
