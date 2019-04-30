use Irssi;
use Irssi::Irc;
use LWP::UserAgent;
use LWP::Simple;
use utf8;
use Data::Dumper;
use KaaosRadioClass;		# LAama1 16.2.2017
use strict;
use warnings;

use vars qw($VERSION %IRSSI);
$VERSION = '0.33';
%IRSSI = (
    authors	=> 'LAama1',
    contact	=> '#kaaosradio@ircnet',
    name	=> 'horos2',
    description	=> 'Skripti kertoo horoskoopin.',
    license	=> 'BSD',
    changed	=> '24.03.2019',
    url		=> 'http://www.kaaosradio.fi'
);


# my $mynick = 'kaaos';
my $debug = 0;

my @weekdays = ('maanantain', 'tiistain', 'keskiviikon', 'torstain', 'perjantain', 'lauantain', 'sunnuntain');
my @moonarray = ('uusikuu', 'kuun kasvava sirppi', 'kuun ensimmäinen neljännes', 'kasvava kuperakuu', 'täysikuu', 'laskeva kuperakuu', 'kuun viimeinen neljännes', 'kuun vähenevä sirppi');

my $irssidir = Irssi::get_irssi_dir() . '/scripts/';
my $infofile;
my @channels = ('#salamolo', '#mobiilisauna', '#psykoosilaakso', '#killahoe');

my $enableChannels = {};
$enableChannels->{'nerv'}->{'#salamolo'};
$enableChannels->{'IRCnet'}->{'#mobiilisauna'};
$enableChannels->{'QuakeNet'}->{'#killahoe'};
$enableChannels->{'freenode'}->{'#kaaosradio'};

my $myname = 'horos2.pl';

my @userarray = ();		# who has allready requested horo today

sub print_help {
	my ($server, $target) = @_;
	my $helpmessage = '!horo <aihesana>: Tulostaa sinulle horoskoopin, mahdollisesti jostain aihepiiristä. Kokeile esim. !horo vkl. Kokeile myös: !kuu, !aurora';
	$server->command("msg -channel $target $helpmessage");
}

sub event_pub_msg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;
	return unless ($target ~~ @channels);
	if ($msg =~ /\!help/i) { print_help($serverrec, $target); }
	
	#return unless ($msg =~ /\bkaaos\b(?!\.)/i );                                              # are we interested in this msg?
	return unless ($msg =~ /\!horo/i);
	da($serverrec);
	return if (KaaosRadioClass::floodCheck() == 1);
	
	if (get_channel_title($serverrec, $target) =~ /np\:/i) {
		return;
	}

	Irssi::print("$nick sanoi: $msg, kanavalla $target");

	filterKeyword($msg);
	return unless (-e $infofile);

	my $rand = checkIfAllreadyDone($address);					# check if flooding... get old $rand and $infofile

	open(UF,"$infofile") || die("can't open $infofile: $!");    # get info from the files.       
	my @information = <UF>;
	close(UF);                                                  # close all open files
	return unless @information;
	my $amount = @information;
	if ($rand == -1) {					# if user not found
		$rand = int(rand($amount));
		push(@userarray, [$address, time(), $rand, $infofile]);
	}
	
	#my $rand = getLineNumber($address, @information);			# get line number and possibly file also

	my $linecount = -1;
	
LINE: for (@information) {
		$linecount++;
		next LINE unless ($rand == $linecount);
		if($rand == $linecount) {
			chomp (my $rimpsu = $_);
			$rimpsu = grepKeyword($rimpsu, $nick);
			$serverrec->command("MSG $target $nick, $rimpsu");			#splitlong.pl handles splitting message to many (if installed)
			Irssi::print("vastasi: '$rimpsu' for $nick on channel: $target");
			#break;
			last;
		}
	}
	
	Irssi::signal_stop();
}

sub filterKeyword {
	my ($msg, @rest) = @_;
	dp("filterKeyword: $msg");
	if	($msg =~ /(\bjussi.*)|(juhannus)/i)	{($infofile) = glob $irssidir . 'horoskooppeja_juhannus.txt'; }
	elsif	($msg =~ /\b(kes..)|(kesä)/i)	{($infofile) = glob $irssidir . 'horoskooppeja_kesa.txt'; }
	elsif	($msg =~ /\b(kev..t)|(kevät)/i)	{($infofile) = glob $irssidir . 'horoskooppeja_kevat.txt'; }
	elsif	($msg =~ /\b(talvi)/i)			{($infofile) = glob $irssidir . 'horoskooppeja_talvi.txt'; }
	elsif	($msg =~ /(viikonl|vkl)/i)		{($infofile) = glob $irssidir . 'horoskooppeja_vkl.txt'; }
	elsif	($msg =~ /(vappu)/i)			{($infofile) = glob $irssidir . 'horoskooppeja_vappu.txt'; }
	elsif	($msg =~ /\b(joulu)/i)			{($infofile) = glob $irssidir . 'horoskooppeja_joulu.txt'; }
	elsif	($msg =~ /(pikkujoulu)/i)		{($infofile) = glob $irssidir . 'horoskooppeja_pikkujoulu.txt'; }
	elsif	($msg =~ /(loppiai)/i)			{($infofile) = glob $irssidir . 'horoskooppeja_loppiainen.txt'; }
	elsif	($msg =~ /(\buv\b)|(uus[i]?vuos[i]?)/i)	{($infofile) = glob $irssidir . 'horoskooppeja_uv.txt'; }
	elsif	($msg =~ /(syksy)|(\bsyys)/i)	{($infofile) = glob $irssidir . 'horoskooppeja_syksy.txt'; }
	elsif	($msg =~ /\b(test)\b/i)			{($infofile) = glob $irssidir . 'horoskooppeja_for_testing.txt'; }
	elsif	($msg =~ /(rakkaus)/i)			{($infofile) = glob $irssidir . 'horoskooppeja_rakkaus.txt';}
	elsif	($msg =~ /(maanant)/i)			{($infofile) = glob $irssidir . 'horoskooppeja_maanantai.txt';}
	elsif	($msg =~ /(p....si..)|(p..si.i)|pääsiäi/i)		{($infofile) = glob $irssidir . 'horoskooppeja_paasiainen.txt';}
	else 						{($infofile) = glob $irssidir . 'horoskooppeja.txt';}	
	dp("horos2.pl: $& matched infofile: $infofile");
}

sub grepKeyword {
	my ($rimpsu, $nick, @rest) = @_;
	chomp (my $weekday = `LC_ALL=fi_FI.utf-8; date +%A 2>>horosstderr.txt`);
	
	chomp (my $weekdak = @weekdays[`date +%u` -1]);		#genetiivi(?)muoto
	chomp (my $tomorrow = `LC_ALL=fi_FI.utf-8; date +%A --date="tomorrow" 2>>horosstderr.txt`);
	chomp (my $tomorrowak = @weekdays[`date +%u`]);

	chomp (my $month = `LC_ALL=fi_FI.utf-8; date +%B 2>>horosstderr.txt`);
	chomp (my $nextmonth = `LC_ALL=fi_FI.utf-8; date +%B --date="next month" 2>>horosstderr.txt`);
	my $season = checkSeason($month, 0);
	my $seasongen = checkSeason($month, 1);				# genetiivi muoto?
	my $seasonob = checkSeason($month, 2);				# objektiivimuoto?
	my $moonphase = omaconway();
	
	$rimpsu =~ s/\$weekday/$weekday/g;
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
		if ($debug) {
			Irssi::print ('address: '.$item->[0]);
			#Irssi::print Dumper @$item;
			Irssi::print ('time: ' . $item->[1]);
			Irssi::print('localtime: '. localtime($item->[1]));
			Irssi::print('rand number: '. $item->[2]);
			Irssi::print('info file: '. $item->[3]);
			Irssi::print('yday: '.$yday);
		}
		if ($item->[0] eq $address && $ydayn == $yday) {
			Irssi::print('BLING!!! allready had horoscope.. today') if $debug;
			Irssi::print Dumper $item if $debug;
			$infofile = $item->[3];				# get old infofile
			$returnvalue = $item->[2];			# return previous rand number
			last;
		} elsif ($item->[0] eq $address && $ydayn != $yday) {
			Irssi::print ('Userarray before splicing: ') if $debug;
			Irssi::print Dumper @userarray if $debug;
			#remove old values
			splice(@userarray, $index,1);
			Irssi::print('Userarray after splicing: ') if $debug;
			Irssi::print Dumper @userarray if $debug;
			last;
		}
		$index++;
	}
	Irssi::print ('checkIfAllreadyDone function end: '. $returnvalue) if $debug;
	return $returnvalue;
}

=pod
sub getLineNumber {
	my ($address, @rest) = @_;
	my $linecount = 0;
	my $localtime = time();
	my ($secn, $minn, $hourn, $mdayn, $monn, $yearn, $wdayn, $ydayn, $isdstn) = localtime($localtime);

	#for (@file) { $linecount++; }			# how many lines total
	
	#my $rand = int(rand($linecount));
	#if($debug) { Irssi::print("timenow: $localtime, ydayn: $ydayn linecount: $linecount"); }
	my $index = 0;
	foreach my $item (@userarray) {
		my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($item->[1]);
		if ($debug) {
			Irssi::print ("address: ".$item->[0]);
			#Irssi::print Dumper @$item;
			Irssi::print ("time: " . $item->[1]);
			Irssi::print("localtime: ". localtime($item->[1]));
			Irssi::print("rand number: ". $item->[2]);
			Irssi::print("info file: ". $item->[3]);
			Irssi::print("yday: ".$yday);
		}
		if ($item->[0] eq $address && $ydayn == $yday) {
			Irssi::print("BLING!!! allready had horoscope.. today") if $debug;
			Irssi::print Dumper $item if $debug;
			#$infofile = $item->[3];		# get old infofile
			return $item->[2];			# return previous rand number
		} elsif ($item->[0] eq $address && $ydayn != $yday) {
			Irssi::print ("Userarray before splicing: ") if $debug;
			Irssi::print Dumper @userarray if $debug;
			#remove old values
			splice(@userarray, $index,1);
			# save new values
			push(@userarray, [$address, $localtime, $rand, $infofile]);
			Irssi::print("userarray after: ") if $debug;
			Irssi::print Dumper @userarray if $debug;
			return $rand;
		}
		$index++;
	}
	push(@userarray, [$address, $localtime, $rand, $infofile]);
	Irssi::print ("userarray function end:") if $debug;
	Irssi::print Dumper @userarray if $debug;
	return $rand;
}
=cut

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
}

sub da {
	my (@data, @rest) = @_;
	return if $debug != 1;
	Irssi::print Dumper @data;
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
Irssi::signal_add('message irc action', 'event_pub_msg');
