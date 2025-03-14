use strict;
use warnings;
use Irssi;
use vars qw($VERSION %IRSSI);
#use lib $ENV{HOME}.'/.irssi/irssi-scripts/';
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use Data::Dumper;
use KaaosRadioClass;
#require "$ENV{HOME}/.irssi/scripts/irssi-scripts/KaaosRadioClass.pm";

$VERSION = '0.51';
%IRSSI = (
	authors => 'LAama1',
	contact => 'LAama1@ircnet',
	name => 'auroras',
	description => 'Revontuli- ja kuun vaiheet -skripti.',
	license => 'BSD',
	url => 'http://www.kaaosradio.fi',
	changed => '2020-12-21',
);

my $DEBUG = 0;

my $db = $ENV{HOME}.'/public_html/auroras.db';

sub getHelp {
	#return '!aurora|revontuli tulostaa kanavalle revontuliaktiviteetin ja ennustuksen. Aktiviteetti perustuu Kp-arvoon. Mitä suurempi Kp, sen etelämmässä revontulia voi silloin nähdä. !kuu, tulostaa kuun vaiheen, esim. "täysikuu"';
	return '!kuu ja !aurora ohje: https://bot.8-b.fi/#rev';
}

sub prind {
	my ($text, @rest) = @_;
	print("\00311" . $IRSSI{name} . "\003> ". $text);
}

sub pubmsg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;
	my $mynick = quotemeta $serverrec->{nick};
	return if ($nick eq $mynick);   #self-test
	if ($msg =~ /(^\!help aurora)/gi || $msg =~ /(^\!help kuu)/) {
		return if KaaosRadioClass::floodCheck() == 1;
		$serverrec->command("MSG $target " . getHelp);
	} elsif ($msg =~ /(^\!aurora)/gi || $msg =~ /(^\!revontul.*)/gi) {
		my $keyword = $1;
		return if KaaosRadioClass::floodCheck() == 1;
		my $string = fetchAuroraData();
		$serverrec->command("MSG $target $string");
		Irssi::print("auroras.pl> $keyword request from $nick on channel $target. Answer: $string");
	} elsif ($msg =~ /(^\!kuu)\b/i || $msg =~ /(^\!moon)/i) {
		my $keyword = $1;
		return if KaaosRadioClass::floodCheck() == 1;
		my $outputstring = KaaosRadioClass::conway();
		# 2024-02-14 my $outputstring = omaconway();
		Irssi::print("auroras.pl> $keyword request from $nick on channel $target. Answer: $outputstring");
		$serverrec->command("MSG $target Kuun vaihe: $outputstring") if $outputstring;
	}
}

sub privmsg {
	my ($server, $msg, $nick, $address) = @_;
	pubmsg($server, $msg, $nick, $address, $nick);
}

sub fetchAuroraData {
	my $searchdate = time - (60*60);			# max 1 hour ago
	my $fetchString = "SELECT kpnow, kp1hforecast, PVM, bz, density, speed from AURORAS where pvm > $searchdate ORDER BY PVM desc limit 1;";
	my (@line) = KaaosRadioClass::readLineFromDataBase($db, $fetchString);
	Irssi::print ('Dump:') if $DEBUG;
	print Dumper(@line) if $DEBUG;
	my $kpnow = $line[0];
	my $kpst = $line[1];
	my $pvm = $line[2];
	my $bz = $line[3];
	my $density = $line[4];
	my $speed = $line[5];
	my $date = localtime($pvm);
	Irssi::print("auroras.pl: kpnow: $kpnow, kpst: $kpst, pvm: $date, bz: $bz nT, density: $density, speed: $speed");
	my $returnString = 'Ei saatu tietoja!';
	if (defined $kpnow || defined $kpst) {
		#$returnString = "Kp arvo nyt: $kpnow, ennustus (1h): $kpst (Näkyvyys: Kp5=Helsinki, Kp4=Iisalmi, Kp3=Kemi)";
		$returnString = "Kp arvo nyt: $kpnow (Näkyvyys: 5=Helsinki, 4=Iisalmi, 3=Kemi). Aurinkotuulen nopeus: $speed km/s, bz: ${bz}nT, tiheys: $density p/cm3";
	}
	return $returnString;
}

sub omaconway {
	# John Conway method
	#my ($y,$m,$d);
	my @params = @_;
	chomp(my $y = `date +%Y`);
	chomp(my $m = `date +%m`);
	chomp(my $d = `date +%d`);

	my $r = $y % 100;
	$r %= 19;
	if ($r > 9) { $r-= 19; }
	$r = (($r * 11) % 30) + $m + $d;
	if ($m < 3) { $r += 2; }
	$r -= 8.3;              # year > 2000

	$r = ($r + 0.5) % 30;	#test321
	my $age = $r;
	$r = 7/30 * $r + 1;

=pod
	  0: 'New Moon'        🌑
	  1: 'Waxing Crescent' 🌒
	  2: 'First Quarter',  🌓
	  3: 'Waxing Gibbous', 🌔
	  4: 'Full Moon',      🌕
	  5: 'Waning Gibbous', 🌖
	  6: 'Last Quarter',   🌗
	  7: 'Waning Crescent' 🌘
=cut

	my @moonarray = ('🌑 uusikuu', '🌒 kuun kasvava sirppi', '🌓 kuun ensimmäinen neljännes', '🌔 kasvava kuperakuu', '🌕 täysikuu', '🌖 laskeva kuperakuu', '🌗 kuun viimeinen neljännes', '🌘 kuun vähenevä sirppi');
	return $moonarray[$r] .", ikä: $age vrk.";
}

Irssi::signal_add_last('message public', 'pubmsg');
Irssi::signal_add_last('message private', 'privmsg');

