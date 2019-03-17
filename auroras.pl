use strict;
use warnings;

use Irssi;
use vars qw($VERSION %IRSSI);
use Irssi::Irc;
use Data::Dumper;

require KaaosRadioClass;

$VERSION = '0.50';
%IRSSI = (
	authors => 'LAama1',
	contact => 'LAama1@ircnet',
	name => 'LAama1',
	description => 'Kaaosradion Revontuli- ja kuun vaiheet -skripti.',
	license => 'BSD',
	url => 'http://www.kaaosradio.fi',
	changed => '2018-10-28',
);

my $DEBUG = 1;

my $db = $ENV{HOME}.'/public_html/auroras.db';
#my $db = $ENV{HOME}. '/.irssi/scripts/newauroras.db';
my @channels = ('#salamolo', '#botti', '#kaaosradio');

sub getHelp {
	return '!aurora|revontuli tulostaa kanavalle revontuliaktiviteetin ja ennustuksen. Aktiviteetti perustuu Kp-arvoon.	Mitä suurempi Kp, sen etelämmässä revontulia voi silloin nähdä.	!kuu, tulostaa kuun vaiheen, esim. "täysikuu"';
}

sub pubmsg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;
	#return unless ($msg =~ /$serverrec->{nick}/i);
	return unless ($target ~~ @channels);
	return if ($nick eq $serverrec->{nick});   #self-test
	if ($msg =~ /(!help)/gi) {
		return if KaaosRadioClass::floodCheck() == 1;
		my $help = getHelp();
		$serverrec->command("MSG $target $help");
	} elsif ($msg =~ /(!aurora)/gi || $msg =~ /(!revontul.*)/gi) {
		my $keyword = $1;
		return if KaaosRadioClass::floodCheck() == 1;
		my $string = fetchAuroraData();
		$serverrec->command("MSG $target $string");
		Irssi::print("auroras.pl: $keyword request from $nick on channel $target");
	} elsif ($msg =~ /(!kuu)\b/i || $msg =~ /(!moon)/i) {
		my $keyword = $1;
		return if KaaosRadioClass::floodCheck() == 1;
		my $outputstring = KaaosRadioClass::conway();
		Irssi::print("auroras.pl: $keyword request from $nick on channel $target");
		$serverrec->command("MSG $target Kuun vaihe: $outputstring") if $outputstring;
	}
}

sub fetchAuroraData {
	my $searchdate = time() - (60*60);			# max 1 hour ago
	Irssi::print('search date: ' . $searchdate) if $DEBUG;
	my $fetchString = "select kpnow,kp1hforecast,PVM, speed from AURORAS where pvm > $searchdate ORDER BY PVM desc limit 1;";
	my (@line) = KaaosRadioClass::readLineFromDataBase($db, $fetchString);
	Irssi::print ('Dump:') if $DEBUG;
	print Dumper(@line) if $DEBUG;
	my $kpnow = $line[0];
	my $kpst = $line[1];
	my $pvm = $line[2];
	my $speed = $line[3];
	Irssi::print("auroras.pl: kpnow: $kpnow, kpst: $kpst, pvm: $pvm");
	my $returnString = 'Ei saatu tietoja!';
	if ($kpnow || $kpst) {
		#$returnString = "Kp arvo nyt: $kpnow, ennustus (1h): $kpst (Näkyvyys: Kp5=Helsinki, Kp4=Iisalmi, Kp3=Kemi)";
		$returnString = "Kp arvo nyt: $kpnow (Näkyvyys: Kp5=Helsinki, Kp4=Iisalmi, Kp3=Kemi). Aurinkotuulen nopeus: $speed km/s";
	}
	return $returnString;
}


Irssi::signal_add_last('message public', 'pubmsg');
