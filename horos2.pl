use strict;
use warnings;
use Encode;
use Irssi;
use Irssi::Irc;
use LWP::UserAgent;
use LWP::Simple;
use utf8;
use Data::Dumper;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;		# LAama1 16.2.2017
use POSIX qw(strftime);
use POSIX qw(locale_h);	# necessary?
use locale;	# necessary??

use vars qw($VERSION %IRSSI);
$VERSION = '0.36';
%IRSSI = (
    authors	=> 'LAama1',
    contact	=> '#kaaosradio@ircnet',
    name	=> 'horos2',
    description	=> 'Skripti kertoo horoskoopin.',
    license	=> 'BSD',
    changed	=> '23.10.2019',
    url		=> 'http://www.kaaosradio.fi'
);

my $helpmessage1 = 'Horoskooppiskripti. Ohje: https://bot.8-b.fi/#h';
#my $helpmessage2 = '!horoskkoppi <aihesana>: Tulostaa sinulle horoskoopin, mahdollisesti jostain aihepiiristä. Kokeile esim. !horoskooppi viikonloppu. Toimii myös privassa.';
my $helpmessage2 = '!horoskooppi ohje: https://bot.8-b.fi/#h';

my $debug = 0;

my @weekdays = ('maanantai', 'tiistai', 'keskiviiko', 'torstai', 'perjantai', 'lauantai', 'sunnuntai', 'maanantai');
my @moonarray = ('uusikuu', 'kuun kasvava sirppi', 'kuun ensimmäinen neljännes', 'kasvava kuperakuu', 'täysikuu', 'laskeva kuperakuu', 'kuun viimeinen neljännes', 'kuun vähenevä sirppi');

my $irssidir = Irssi::get_irssi_dir() . '/scripts/';
my $infofile;
my @channels = ('#salamolo', '#mobiilisauna', '#psykoosilaakso', '#killahoe', '#kaaosradio');

#my $enableChannels = {};
#$enableChannels->{'nerv'}->{'#salamolo'};
#$enableChannels->{'IRCnet'}->{'#mobiilisauna'};
#$enableChannels->{'QuakeNet'}->{'#killahoe'};
#$enableChannels->{'freenode'}->{'#kaaosradio'};

my $myname = 'horos2.pl';

# TODO: read these from filename
my @ignorenicks = (
	'kaaosradio',
	'ryokas',
	'KD_Butt',
	'micdrop',
);

my @userarray = ();		# who has allready requested horo today

# private horoscope not implemented
sub event_priv_msg {
	my ($server, $msg, $nick, $address) = @_;
    my $mynick = quotemeta $serverrec->{nick};
	return if ($nick eq $mynick);   #self-test
	if ($msg =~ /\!help hor/i) { 
		$server->command("msg -nick $nick $helpmessage2");
	}
	# elsif ($msg =~ /!help$/) {
	#	$server->command("msg -nick $nick $helpmessage1");
	#}
	return unless ($msg =~ /\!h!(a|e|u)/i);
	return if (KaaosRadioClass::floodCheck() == 1);
	return;
}

sub event_pub_msg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;
	return unless ($target ~~ @channels);
	return if $nick ~~ @ignorenicks;
	if ($msg =~ /\!help hor/i) {
		$serverrec->command("msg -channel $target $helpmessage2");
		return;
	}
	# elsif ($msg =~ /\!help$/i) {
	#	$serverrec->command("msg -channel $target $helpmessage1");
	#	return;
	#}

	return unless ($msg =~ /\!h/i);
	return if ($msg =~ /!huomen/ || $msg =~ /!help/ || $msg =~ /!ha/);
	return if (KaaosRadioClass::floodCheck() == 1);

	# if string: 'np:' found in channel topic
	if (get_channel_title($serverrec, $target) =~ /npv?\:/i) {
		# disabled 2023-11-01 return;
	}

	print($IRSSI{name}."> $nick sanoi: $msg, kanavalla $target");
	my $newrimpsu = '';
	if ($newrimpsu = throw_horo($msg, $nick, $address)) {
		$serverrec->command("MSG $target $nick, $newrimpsu");
		# 2022-06-05 print($IRSSI{name}."> vastasi: '$newrimpsu' for $nick on channel: $target");
		print($IRSSI{name}."> vastasin: $newrimpsu");
	}
	return;
}

sub throw_horo {
	my ($msg, $nick, $address, @rest) = @_;

	filterKeyword($msg);
	return unless (-e $infofile);

	my $rand = checkIfAllreadyDone($address);					# check if flooding... get old $rand and $infofile
	my $information = KaaosRadioClass::readTextFile($infofile);
	return unless $information;
	my $amount = @$information;
	if ($rand == -1) {					# if user not found
		$rand = int rand $amount;
		push(@userarray, [$address, time(), $rand, $infofile]);
	}
	my $linecount = -1;
	
 LINE: for (@$information) {
		$linecount++;
		# next LINE unless ($rand == $linecount);
		if($rand == $linecount) {
			chomp (my $rimpsu = $_);
			return grepKeyword($rimpsu, $nick);
		}
	}
	return;
}

sub filterKeyword {
	my ($msg, @rest) = @_;
	$msg = decode('UTF-8', $msg);
	dp("filterKeyword: $msg");
	if	($msg =~ /(juhannus)|(jussi)/ui)	{($infofile) = glob $irssidir . 'horoskooppeja_juhannus.txt'; }
	elsif	($msg =~ /(kesä)/ui)			{($infofile) = glob $irssidir . 'horoskooppeja_kesa.txt'; }
	elsif	($msg =~ /(kevä[ti])/ui)		{($infofile) = glob $irssidir . 'horoskooppeja_kevat.txt'; }
	elsif	($msg =~ /(talvi)/i)			{($infofile) = glob $irssidir . 'horoskooppeja_talvi.txt'; }
	elsif	($msg =~ /(viikonl|vkl)/i)		{($infofile) = glob $irssidir . 'horoskooppeja_vkl.txt'; }
	elsif	($msg =~ /(vappu)/i)			{($infofile) = glob $irssidir . 'horoskooppeja_vappu.txt'; }
	elsif	($msg =~ /(pikkujoulu)/i)		{($infofile) = glob $irssidir . 'horoskooppeja_pikkujoulu.txt'; }
	elsif	($msg =~ /(joulu)/i)			{($infofile) = glob $irssidir . 'horoskooppeja_joulu.txt'; }
	elsif	($msg =~ /(loppiai)/i)			{($infofile) = glob $irssidir . 'horoskooppeja_loppiainen.txt'; }
	elsif	($msg =~ /(\buv\b)|(uus[i]?vuos)/i)	{($infofile) = glob $irssidir . 'horoskooppeja_uv.txt'; }
	elsif	($msg =~ /(syksy)|(\bsyys)/i)	{($infofile) = glob $irssidir . 'horoskooppeja_syksy.txt'; }
	elsif	($msg =~ /\b(test)\b/i)			{($infofile) = glob $irssidir . 'horoskooppeja_for_testing.txt'; }
	elsif	($msg =~ /(rakkaus)/i)			{($infofile) = glob $irssidir . 'horoskooppeja_rakkaus.txt';}
	elsif	($msg =~ /(maanant)/i)			{($infofile) = glob $irssidir . 'horoskooppeja_maanantai.txt';}
	elsif	($msg =~ /(pääsiäi)/ui)			{($infofile) = glob $irssidir . 'horoskooppeja_paasiainen.txt';}
	else 									{($infofile) = glob $irssidir . 'horoskooppeja.txt';}
	#dp("horos2.pl: $& matched file: $infofile");
	print($IRSSI{name}."> $& matched file: $infofile");
	return;
}

sub grepKeyword {
	my ($rimpsu, $nick, @rest) = @_;
	my $dateseconds = (60*60*24);
	my $currenttime = time;
	my $weekday = strftime "%A", localtime ($currenttime);
	#Irssi::print("test locale1 today: $weekday");
	#Irssi::print("test locale2 today ". strftime "%A", localtime($currenttime));
	my $weekdak = @weekdays[`date +%u` -1];				#genetiivi(?)muoto

	my $tomorrow = strftime "%A", localtime ($currenttime + $dateseconds);
	my $tomorrowak = '';
	dp(@weekdays[`date +%u`].', date: '.`date +%u`);
	chomp ($tomorrowak = @weekdays[`date +%u`]);

	my $month = strftime "%B", localtime $currenttime;
	my $year = strftime "%Y", localtime $currenttime;
	#Irssi::print("tset locale 3 tomorrow: $tomorrow month: $month");
	my $nextmonth = '';
	chomp ($nextmonth = `LANG=fi_FI.utf-8; date +%B --date="next month"`);
	my $season = checkSeason($month, 0);
	my $seasongen = checkSeason($month, 1);				# genetiivi muoto?
	my $seasonob = checkSeason($month, 2);				# objektiivimuoto?
	my $moonphase = omaconway();
	
	$rimpsu =~ s/\$weekday/$weekday/g;
	$rimpsu =~ s/\$today/$weekday/g;
	$rimpsu =~ s/\$weekdak/$weekdak/g;
	$rimpsu =~ s/\$tomorrowak/$tomorrowak/g;
	$rimpsu =~ s/\$month/$month/g;
	$rimpsu =~ s/\$nextmonth/$nextmonth/g;
	$rimpsu =~ s/\$nick/$nick/g;
	$rimpsu =~ s/\$season/$season/g;
	$rimpsu =~ s/\$seasongen/$seasongen/g;
	$rimpsu =~ s/\$seasonob/$seasonob/g;
	$rimpsu =~ s/\$moonphase/$moonphase/g;
	$rimpsu =~ s/\$tomorrow/$tomorrow/g;
	$rimpsu =~ s/\$year/$year/g;
	return $rimpsu;
}

sub checkIfAllreadyDone {
	my ($address, @rest) = @_;

	my $localtime = time();
	my ($secn, $minn, $hourn, $mdayn, $monn, $yearn, $wdayn, $ydayn, $isdstn) = localtime($localtime);
	my $returnvalue = -1;
	my $index = 0;
	foreach my $item (@userarray) {
		my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($item->[1]);
		if ($item->[0] eq $address && $ydayn == $yday) {
			dp('BLING!!! allready had horoscope.. today');
			Irssi::print Dumper $item if $debug;
			$infofile = $item->[3];				# get old infofile
			$returnvalue = $item->[2];			# return previous rand number
			last;
		} elsif ($item->[0] eq $address && $ydayn != $yday) {
			#remove old values
			splice(@userarray, $index,1);
			last;
		}
		$index++;
	}
	dp('checkIfAllreadyDone function end: '. $returnvalue);
	return $returnvalue;
}

sub checkSeason	{
	my ($month, $number, @rest) = @_;
	# [perusmuoto, genetiivi, partitiivi/subjekti?]
	my @result = ('vuodenaika', 'vuodenajan', 'vuodenaikaa');
	if ($month ~~ ['joulukuu', 'tammikuu', 'helmikuu'])	{
		@result = ('talvi', 'talven', 'talvea');
	} elsif ($month ~~ ['maaliskuu', 'huhtikuu', 'toukokuu'])	{
		@result = ('kevät', 'kevään', 'kevättä');
	} elsif ($month ~~ ['kesäkuu', 'heinäkuu', 'elokuu'])	{
		@result = ('kesä', 'kesän', 'kesää');
	} elsif ($month ~~ ['syyskuu', 'lokakuu', 'marraskuu'])	{
		@result = ('syksy', 'syksyn', 'syksyä');
	}
	return $result[$number];
}

sub dp {
	my ($data, @rest) = @_;
	return if $debug != 1;
	Irssi::print("$myname-debug: $data");
	return;
}

sub da {
	my (@data, @rest) = @_;
	return if $debug != 1;
	Irssi::print Dumper @data;
	return;
}

sub get_channel_title {
	my ($server, $channel) = @_;
	my $chanrec = $server->channel_find($channel);
	return '' unless defined $chanrec;
	return $chanrec->{topic};
}

sub omaconway {
	# John Conway method
	chomp(my $y = `date +%Y`);
	chomp(my $m = `date +%m`);
	chomp(my $d = `date +%d`);
	
	my $r = $y % 100;
	$r %= 19;

	if ($r > 9) { $r-= 19; }
	$r = (($r * 11) % 30) + $m + $d;
	if ($m < 3) { $r += 2; }

	$r -= 8.3;						# year > 2000
	$r = ($r + 0.5) % 30;
	$r = 7/30 * $r + 1;
	#my $temp = 7/30;				# = 0
	#Irssi::print("r3: $r, 7/30 = $temp");
	
=pod
      0: "New Moon", 
      1: "Waxing Crescent", 
      2: "First Quarter", 
      3: "Waxing Gibbous", 
      4: "Full Moon", 
      5: "Waning Gibbous", 
      6: "Last Quarter", 
      7: "Waning Crescent"
=cut
	
	return $moonarray[$r];
}


Irssi::signal_add('message public', 'event_pub_msg');
Irssi::signal_add('message private', 'event_priv_msg');
#Irssi::signal_add('message irc action', 'event_pub_msg');
