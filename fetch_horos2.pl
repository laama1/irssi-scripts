use strict;
use warnings;
use utf8;
use Data::Dumper;
use lib '/home/laama/.irssi/scripts';
use KaaosRadioClass;		# LAama1 16.2.2017
#use Getopt::Long;
use vars qw($VERSION);

$VERSION = "0.1";
=pod
%INFO = (
    authors	=> 'LAama1',
    contact	=> '#kaaosradio ircnet',
    name	=> 'horos2.pl',
    description	=> 'Skripti kertoo horoskoopin.',
    license	=> 'BSD',
    changed	=> '22.11.2017',
    url		=> 'http://www.kaaosradio.fi'
);
=cut
my $DEBUG = 0;

#my %args;
#GetOptions(\%args, "arg1=s") or die "KAPUT";

#dp("Param0: ".$0);
#dp("Arg1: ". $args{arg1});

my $mydir = "/home/laama/.irssi/scripts/newhoro2";

my @astrourls = (
	'https://www.astro.fi/future/weeklyForecast/sign/aries',
	'https://www.astro.fi/future/weeklyForecast/sign/taurus',
	'https://www.astro.fi/future/weeklyForecast/sign/gemini',
	'https://www.astro.fi/future/weeklyForecast/sign/cancer',
	'https://www.astro.fi/future/weeklyForecast/sign/leo',
	'https://www.astro.fi/future/weeklyForecast/sign/virgo',
	'https://www.astro.fi/future/weeklyForecast/sign/libra',
	'https://www.astro.fi/future/weeklyForecast/sign/scorpion',
	'https://www.astro.fi/future/weeklyForecast/sign/sagittarius',
	'https://www.astro.fi/future/weeklyForecast/sign/capricorn',
	'https://www.astro.fi/future/weeklyForecast/sign/aquarius',
	'https://www.astro.fi/future/weeklyForecast/sign/pisces',
);

my $iltisUrl = "http://iltalehti.fi/horoskooppi";


my $logfile = $mydir."/logs/fetch_horos2.log";
my $debuglog = $mydir."/logs/fetch_horos2_debug.log";
my $horofile = $mydir."/horos.txt";
my $db = $mydir."/horos.db";
my $dbh;
#my $infofile = $mydir."/horos.txt";

unless (-e $db) {
	unless(open FILE, '>:utf8',$db) {
		print("Unable to create or write file: $db.\n");
		die;
	}
	close FILE;
	createHoroDB();
	print("Database file created. ($db)\n");
}

if (!defined($ARGV[0])) {
	print("No parameters given. Quit.\n");
	&print_help;
	exit(0);
} elsif ($ARGV[0] eq "iltis") {
	grepIltis();
} elsif ($ARGV[0] eq "astro") {
	grepAstro();
}

sub print_help {
	my ($server, $target) = @_;
	my $helpmessage = "Fetch horoscopes from internet. Give parameters iltis or astro.\n";
	print("$helpmessage");
}


sub grepAstro {
	my $index = 0;
	
	# open database connection
	$dbh = KaaosRadioClass::connectSqlite($db);
	
	foreach my $currentURl (@astrourls) {
		dp("grepAstro index: ". $index);
		if ($index >= 1 && $DEBUG) {
			return;
		}
		dp("grepAstro current url: $currentURl");
		my $page = KaaosRadioClass::fetchUrl($currentURl, 0);
		my $sign;
		if ($page =~ /\<h2 class="center"\>Viikkovillitys(.*)/si) {
			$page = $1;
			#dp("page: ".$page);
		} else {
			return;
		}
		if ($index == 0) {
			grepAstrosaa($page, $currentURl);
		}
		$index++;
		grepAstroHoro($page, $currentURl);
	}
}

sub grepAstroHoro {
	my ($page, $url, @rest) = @_;
	#dw($page);
	my $skoopit = "";
	while ($page =~ m/<h2>(.*?)<\/h2>\n\s+<p><em>(.*?)\n<\/em>/sgi) {
		my $sign = $1;
		my $horo = $2;
		#dp("grepAstroHoro positions: ". pos($page));
		#dp(@-);
		#dp(@+);

		dp("grepAstroHoro sign: ".$sign);
		dp("grepAstroHoro horo: ".$horo);
		
		if (defined($horo)) {
			saveHoroToDB($horo, $url, $sign);
			$horo = filterKeyword($horo);
			$skoopit .= $horo . "\n" if $horo;
		} else {
			dp("grepAstroHoro: no horo found!");
		}
	}
	#dp("grepAstroHoro Skoopit: ". $skoopit);
	saveHoroToFile($skoopit);
}

sub grepAstrosaa {
	my ($data, $url, @rest) = @_;
	
	my $astrosaas = "";
	#if ($data =~ /<p><strong>Astrosää:<\/strong>(.*?)<\/p>/gi) {
	while ($data =~ m/<p><strong>Astrosää:<\/strong>(.*?)<\/p>/sgi) {
		my $horo = $1;
		dp("grepAstrosaa positions: ". pos($data));
		#dp("grepAstrosaa: ".$returnvalue);
		
		if (defined($horo) && $horo ne "") {
			saveHoroToDB($horo, $url, "Astrosää");
			$horo = filterKeyword($horo);
			$astrosaas .= $horo . "\n" if $horo;
		}
	}
	dp("Astrosaas: " .$astrosaas);
	saveHoroToFile($astrosaas);
	#return $returnvalue;
}

sub grepIltis {
	my $page = KaaosRadioClass::fetchUrl($iltisUrl, 0);
	if ($page =~ /<p class="ingressi"><\/p>(.*?)<\/div>/si) {
		my $parsethis = $1;
		my $allHoros = "";
		dw("parse this: ".$parsethis);
		
		# open database connection
		$dbh = KaaosRadioClass::connectSqlite($db);
		
		while($parsethis =~ m/<p>(\w+) (\d+\.\d+\.-\d+\.\d+\.) (.*?)<\/p>/sgi) {
			my $sign = $1;
			my $datum = $2;
			my $horo = $3;
			dp("grepIltis sign: $sign");
			dp("grepIltis datum: $datum");
			dp("grepIltis horo: $horo");
			if (defined($horo) && $horo ne "") {
				saveHoroToDB($horo, $iltisUrl, $sign);
				$horo = filterKeyword($horo);
				$allHoros .= $horo . "\n" if $horo;
			}
		}
		dp("grepIltis allhoros: ".$allHoros);
		saveHoroToFile($allHoros);
	} else {
		return;
	}
}

# save to different file if keyword found.
sub filterKeyword {
	my ($msg, @rest) = @_;
	my $infofile = "";
	if	($msg =~ /(\bjussi.*)|(juhannus)/i)	{$infofile = $mydir . "/horos_juhannus.txt"; }
	elsif	($msg =~ /\b(kesä)/i)			{$infofile = $mydir . "/horos_kesa.txt"; }
	elsif	($msg =~ /\b(kevä[ti])/i)		{$infofile = $mydir . "/horos_kevat.txt"; }
	elsif	($msg =~ /\b(talv[ie])/i)		{$infofile = $mydir . "/horos_talvi.txt"; }
	#elsif	($msg =~ /\b(talve)/i)			{($infofile) = $mydir . "horoskooppeja_talvi.txt"; }
	elsif	($msg =~ /(syksy)|(\bsyys)/i)	{$infofile = $mydir . "/horos_syksy.txt"; }
	elsif	($msg =~ /(viikonl|vkl)/i)		{$infofile = $mydir . "/horos_vkl.txt"; }
	elsif	($msg =~ /(vappu)|(vapun)/i)	{$infofile = $mydir . "/horos_vappu.txt"; }
	elsif	($msg =~ /\b(joulu)/i)			{$infofile = $mydir . "/horos_joulu.txt"; }
	elsif	($msg =~ /(pikkujoulu)/i)		{$infofile = $mydir . "/horos_pikkujoulu.txt"; }
	elsif	($msg =~ /(loppiai)/i)			{$infofile = $mydir . "/horos_loppiainen.txt"; }
	elsif	($msg =~ /(\buv\b)|(uus[i]?vuos[i]?)/i)	{$infofile = $mydir . "/horos_uv.txt"; }
	elsif	($msg =~ /(\buuteen vuoteen\b)/i)		{$infofile = $mydir . "/horos_uv.txt"; }
	elsif	($msg =~ /(\buudenvuo)/i)		{$infofile = $mydir . "/horos_uv.txt"; }
	elsif	($msg =~ /(\bvuosi alkaa\b)/i)	{$infofile = $mydir . "/horos_uv.txt"; }
	#elsif	($msg =~ /\b(test)\b/i)			{($infofile) = glob $mydir . "horoskooppeja_for_testing.txt"; }
	elsif	($msg =~ /(rakkau[sd])/i)		{$infofile = $mydir . "/horos_rakkaus.txt";}
	elsif	($msg =~ /(maanant)/i)			{$infofile = $mydir . "/horos_maanantai.txt";}
	elsif	($msg =~ /(pääsiä)/i)			{$infofile = $mydir . "/horos_pääsiäinen.txt";}
	#else 									{$infofile = $mydir . "horoskooppeja.txt";}
	
	if ($infofile ne "" && $infofile ne $horofile) {
		dp("fetch_horos2.pl: $& matched infofile: $infofile");
		KaaosRadioClass::addLineToFile($infofile, $msg);
		return;
	} else {
		dp("filterKeyword: no match!");
	}
	
	return $msg;
}

sub grepKeyword {
	my ($rimpsu, $nick, @rest) = @_;
	chomp (my $weekday = `LC_ALL=fi_FI.utf-8; date +%A 2>>$logfile`);
	my @weekdays = ("maanantain", "tiistain", "keskiviikon", "torstain", "perjantain", "lauantain", "sunnuntain");
	chomp (my $weekdak = @weekdays[`date +%u` -1]);		#genetiivi(?)muoto
	chomp (my $tomorrow = `LC_ALL=fi_FI.utf-8; date +%A --date="tomorrow" 2>>$logfile`);
	chomp (my $tomorrowak = @weekdays[`date +%u`]);

	chomp (my $month = `LC_ALL=fi_FI.utf-8; date +%B 2>>$logfile`);
	chomp (my $nextmonth = `LC_ALL=fi_FI.utf-8; date +%B --date="next month" 2>>$logfile`);
	my $season = checkSeason($month, 0);
	my $seasongen = checkSeason($month, 1);				# genetiivi muoto?
	my $seasonob = checkSeason($month, 2);				# objektiivimuoto?
	my $moonphase = conway();
	
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


sub checkSeason	{
	my ($month, $number, @rest) = @_;
	# [perusmuoto, genetiivi, partitiivi/subjekti?]
	my @result = ("vuodenaika", "vuodenajan", "vuodenaikaa");
	if ($month ~~ ["joulukuu", "tammikuu", "helmikuu"])	{
		@result = ("talvi", "talven", "talvea");
	} elsif ($month ~~ ["maaliskuu", "huhtikuu", "toukokuu"])	{
		@result = ("kevät", "kevään", "kevättä");
	} elsif ($month ~~ ["kesäkuu", "heinäkuu", "elokuu"])	{
		@result = ("kesä", "kesän", "kesää");
	} elsif ($month ~~ ["syyskuu", "lokakuu", "marraskuu"])	{
		@result = ("syksy", "syksyn", "syksyä");
	}
	
	return $result[$number];

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
	
	my @moonarray = ("uusikuu", "kuun kasvava sirppi", "kuun ensimmäinen neljännes", "kasvava kuperakuu", "täysikuu", "laskeva kuperakuu", "kuun viimeinen neljännes", "kuun vähenevä sirppi");
	#Irssi::print $moonarray[$r] if $debug;
	return $moonarray[$r];
}

# Create FTS4 table (full text search)
sub createHoroDB {
	$dbh = KaaosRadioClass::connectSqlite($db);
	# Using FTS (full-text search)
	my $stmt = qq(CREATE VIRTUAL TABLE HOROS
			    using fts4(PVM,	URL, HORO, SIGN));

	my $rv = $dbh->do($stmt);
	if($rv < 0) {
   		print ("DBI Error: ". DBI::errstr. "\n");
	} else {
   		print("Table $db created successfully.\n");
	}
}

# Save one horo to database. Params: $horo, $url, $sign
sub saveHoroToDB {
	my ($horo, $url, $sign, @rest) = @_;
	dp("saveHoroToDB");
	my $pvm = time();
	my $sqlString = "Insert into horos values ('$pvm', '$url', '$horo', '$sign')";
	return KaaosRadioClass::writeToOpenDB($dbh, $sqlString);
}

sub saveHoroToFile {
	my ($data, @rest) = @_;
	return if $data eq "";
	# parse lasta linefeed
	$data = substr($data,0,length($data) -1);
	return KaaosRadioClass::addLineToFile($horofile, grepKeyword($data));
}

sub dw {
	return KaaosRadioClass::writeToFile($debuglog, @_);
}

# debug print
sub dp {
    return unless $DEBUG;
    print("debug: @_ \n");
}

$dbh->disconnect();
