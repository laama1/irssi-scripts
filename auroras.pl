use strict;
use warnings;

use Irssi;
use vars qw($VERSION %IRSSI);
use Irssi::Irc;
use Data::Dumper;

require KaaosRadioClass;

$VERSION = '0.46';
%IRSSI = (
'authors' => 'LAama1',
'contact' => 'LAama1@ircnet',
'name' => 'LAama1',
'description' => 'Kaaosradion Revontuli- ja kuun vaiheet -skripti.',
'license' => 'BSD',
'url' => 'http://www.kaaosradio.fi',
'changed' => '2018-09-04',
);

my $DEBUG = 1;

my $db = $ENV{HOME}.'/public_html/auroras.db';
my @channels = ('#salamolo2', '#botti');

sub getHelp {
	return '!aurora|revontuli tulostaa kanavalle revontuliaktiviteetin ja ennustuksen. Aktiviteetti perustuu Kp-arvoon.	Mitä suurempi Kp, sen etelämmässä revontulia voi silloin nähdä.	!kuu, tulostaa kuun vaiheen, esim. 'täysikuu'.';
}

sub pubmsg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;
	return unless ($msg =~ /$serverrec->{nick}/i);
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
		my $outputstring = conway();
		Irssi::print("auroras.pl: $keyword request from $nick on channel $target");
		$serverrec->command("MSG $target Kuun vaihe: $outputstring");
	}
}

sub fetchAuroraData {
	my $searchdate = time() - (60*60);			# max 1 hour ago
	Irssi::print('search date: ' . $searchdate) if $DEBUG;
	my $fetchString = "select * from AURORAS where pvm > $searchdate ORDER BY PVM desc limit 1;";
	my (@line) = KaaosRadioClass::readLinesFromDataBase($db, $fetchString);
	Irssi::print ('Dump:') if $DEBUG;
	print Dumper(@line) if $DEBUG;
	my $kpnow = $line[0];
	my $kpst = $line[1];
	my $pvm = $line[2];
	Irssi::print("auroras.pl: kpnow: $kpnow, kpst: $kpst, pvm: $pvm");
	my $returnString = 'Ei saatu tietoja!';
	if ($kpnow || $kpst) {
		$returnString = "Kp arvo nyt: $kpnow, ennustus (1h): $kpst (Näkyvyys: Kp5=Helsinki, Kp4=Iisalmi, Kp3=Kemi)";
	}
	return $returnString;
}


sub conway {
	# John Conway method
	#my ($y,$m,$d);
	chomp(my $y = `date +%Y`);
	chomp(my $m = `date +%m`);
	chomp(my $d = `date +%d`);

	my $r = $y % 100;
	$r %= 19;
	if ($r > 9) { $r-= 19; }
	$r = (($r * 11) % 30) + $m + $d;
	if ($m < 3) { $r += 2; }
	$r -= 8.3;                                              # year > 2000

	$r = ($r + 0.5) % 29;	#test321
	my $age = $r;
	$r = 7/30 * $r + 1;

=pod
      0: 'New Moon',
      1: 'Waxing Crescent',
      2: 'First Quarter',
      3: 'Waxing Gibbous',
      4: 'Full Moon',
      5: 'Waning Gibbous',
      6: 'Last Quarter',
      7: 'Waning Crescent'
=cut

	my @moonarray = ('uusikuu', 'kuun kasvava sirppi', 'kuun ensimmäinen neljännes', 'kasvava kuperakuu', 'täysikuu', 'laskeva kuperakuu', 'kuun viimeinen neljännes', 'kuun vähenevä sirppi');
	return $moonarray[$r] .", ikä: $age vrk.";
}

Irssi::signal_add_last('message public', 'pubmsg');
