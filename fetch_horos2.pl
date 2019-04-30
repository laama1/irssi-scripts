#!/usr/bin/perl
use strict;
#use warnings;
use utf8;
use Data::Dumper;
use lib $ENV{HOME}.'/.irssi/scripts';
use KaaosRadioClass;		# LAama1 16.2.2017
#use Getopt::Long;
use vars qw($VERSION);

$VERSION = 0.4;

my $DEBUG = 0;
my $DEBUG1 = 0;
#my %args;
#GetOptions(\%args, "arg1=s") or die "KAPUT";

#dp("Param0: ".$0);
#dp("Arg1: ". $args{arg1});

my $mydir = $ENV{HOME}.'/.irssi/scripts/newhoro2';	# output dir
my ($seconds, $minutes, $hours, $mday, $month, $year, $weekday, $yearday, $isdst) = localtime(time);
$year += 1900;
$month += 1;
#print( "Seconds: $seconds, Minutes: $minutes, Hours $hours, Monthday: $mday, Month: $month, Year: $year, Weekday: $weekday, Yearday: $yearday, ISDST: $isdst \n");
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

#my $iltisUrl = 'http://iltalehti.fi/horoskooppi/index.shtml';
my $iltisUrl = 'https://www.iltalehti.fi/horoskooppi';
my $menaisetUrl = 'https://www.menaiset.fi/artikkeli/horoskooppi/paivan-horoskooppi/paivan-horoskooppi-';
$menaisetUrl .= $mday.$month;
#dp("menaiset url: $menaisetUrl");
#print $menaisetUrl . "\n";


my $logfile = $mydir.'/logs/fetch_horos2.log';
open(STDERR, ">>:utf8", $logfile) or do {
	print "failed to open STDERR ($!)\n";
	die;
};

warn 'testing warning redirect' if $DEBUG1;
my $debuglog = $mydir.'/logs/fetch_horos2_debug.log';
my $horofile = $mydir.'/horos.txt';
my $db = $mydir.'/horos.db';
my $dbh;
my $howManySaved = 0;
#my $infofile = $mydir."/horos.txt";

my @seasons = ('talvi', 'kevät', 'kesä', 'syksy');
my @seasonsak = ('talven', 'kevään', 'kesän', 'syksyn');
my @weekdaysak = ('maanantain', 'tiistain', 'keskiviikon', 'torstain', 'perjantain', 'lauantain', 'sunnuntain', 'maanantain');
my @months = ('tammikuu', 'helmikuu', 'maaliskuu', 'huhtikuu', 'toukokuu', 'kesäkuu', 'heinäkuu',
'elokuu', 'syyskuu', 'lokakuu', 'marraskuu', 'joulukuu');

chomp (my $tomorrowak = @weekdaysak[`date +%u`]);
chomp (my $tomorrow = `LANG=fi_FI.utf-8; date +%A --date="tomorrow" 2>>$logfile`);
chomp (my $weekdak = @weekdaysak[`date +%u` -1]);
chomp (my $curmonth = `LC_ALL=fi_FI.utf-8; date +%B 2>>$logfile`);
chomp (my $nextmonth = `LC_ALL=fi_FI.utf-8; date +%B --date="next month" 2>>$logfile`);
my $curseason = checkSeason($curmonth, 0);

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
} elsif ($ARGV[0] eq 'iltis') {
	grepIltis();
} elsif ($ARGV[0] eq 'astro') {
	grepAstro();
} elsif ($ARGV[0] eq 'menaiset') {
	grepMenaiset();
}

sub print_help {
	my ($server, $target) = @_;
	my $helpmessage = "Fetch horoscopes from internet. Give parameter iltis or astro or menaiset.\n";
	print("$helpmessage");
}

sub grepAstro {
	my $index = 0;
	my $logtext = '';
	# open database connection
	$dbh = KaaosRadioClass::connectSqlite($db);
	
	foreach my $currentURl (@astrourls) {
		dp("\n\ngrepAstro index: ". $index);
		dp("grepAstro current url: $currentURl");
		my $page = KaaosRadioClass::fetchUrl($currentURl, 0);
		my $sign;
		#if ($page =~ /\<h2 class="center"\>Viikkovillitys(.*?)sidebar/si) {
		if ($page =~ /\<div id="entireWeek"(.*?)script/si) {
			$page = $1;
			$page =~ s/<img.*?>//gi;	# clean the debug a bit
		} else {
			dp("div entireWeek not found! ($index)");
			next;
		}
		if ($index == 0) {
			grepAstrosaa($page, $currentURl);
		}
		grepAstroHoro($page, $currentURl);
		$index++;
	}
	$logtext = "grep astro horo done. ($index)";
	logmsg($logtext);
}

sub grepAstroHoro {
	my ($page, $url, @rest) = @_;
	#dw($page);
	my $skoopit = "";
	my $index = 0;
	while ($page =~ m/<h2>(.*?)<\/h2>\n\s+<p>.*?<em>(.*?)<\/em>/sgi && $index < 100) {
		my $sign = $1;
		my $horo = $2;
		dp("grepAstroHoro sign: ".$sign) if $DEBUG1;
		dp("grepAstroHoro horo: ".$horo) if $DEBUG1;
		
		if (defined($horo)) {
			saveHoroToDB($horo, $url, $sign);
			$horo = filterKeyword($horo);
			$skoopit .= $horo . "\n" if $horo;
		} else {
			dp('grepAstroHoro: no horo found!');
		}
		$index++;
	}
	if ($index == 0) {
		dp('grepAstroHoro regex failed!');
	} else {
		saveHoroToFile($skoopit);
		logmsg("astroHORO done ($index)");
	}
}

sub grepAstrosaa {
	my ($data, $url, @rest) = @_;
	
	my $astrosaas = '';
	#if ($data =~ /<p><strong>Astrosää:<\/strong>(.*?)<\/p>/sgi) {
	#	dp('astrosaa found!');
	#}
	my $index = 0;
	#dp("grepAstrosaa page: $data");
	#<strong>Astrosää:</strong>Halmikuun aloittava viikko on .... eniten.</p>
	#while ($data =~ m/<p><strong>Astrosää:<\/strong>(.*?)<\/p>/sgi && $index++) {
	while ($data =~ m/<strong>Astrosää:<\/strong>(.*?)<\/p>/sgi && $index < 100) {
	# <p><strong>Astrosää:</strong>Tammikuun t... </p>
		$index++;
		my $horo = $1;

		dp("grepAstrosaa ($index): ".$horo);
		
		if (defined $horo && $horo ne '') {
			saveHoroToDB($horo, $url, 'Astrosää');
			$horo = filterKeyword($horo);
			$astrosaas .= $horo . "\n" if $horo;
		}
	}

	if ($index == 0) {
		dp('grepAstrosaa regex failed!');
	} else {
		logmsg("astroSää done ($index)");
		saveHoroToFile($astrosaas);
	}

}

sub grepIltis {
	my $page = KaaosRadioClass::fetchUrl($iltisUrl, 0);
	$page = parseComments($page);
	my $logtext;
	#logmsg($page);
	#if ($page != -1 && $page =~ /<p class="ingressi"><\/p>(.*?)<\/div>/si) {
	if ($page != -1 && $page =~ /itemProp="articleBody"/si) {
		$page = KaaosRadioClass::ktrim($page);
		#my $parsethis = $1;
		my $allHoros = '';
		my $index = 0;
		#dw("parse this: ".$page);
		
		# open database connection
		$dbh = KaaosRadioClass::connectSqlite($db);
		
		while($page =~ m/<b>(\w+) (\d+\.\d+\.-\d+\.\d+\.)<\/b> (.*?)<\/p>/sgi && $index < 100) {
		#while($page =~ m/<p>(\w+) (\d+\.\d+\.-\d+\.\d+\.) (.*?)<\/p>/sgi) {
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
			$index++;
		}
		if ($index == 0 ) {
			dp('iltis regexp 2..');
			# iltis regex #2, if nothing found
			#<p>OINAS 21.3.–19.4. Voimiasi ja hermojasi koetellaan tänään toden teolla, mutta kun pidät tavoitteesi mielessäsi etkä antaudu häiriötekijöiden edessä, huomaat, että lopussa kiitos seisoo.</p>
			while($page =~ m/<p>(\w+) (\d+\.\d+\.[–-]\d+\.\d+\.) (.*?)<\/p>/sgi) {
				my $sign = $1;
				my $datum = $2;
				my $horo = $3;
				dp("grepIltis2 sign: $sign");
				dp("grepIltis2 datum: $datum");
				dp("grepIltis2 horo: $horo");
				if (defined($horo) && $horo ne '') {
					saveHoroToDB($horo, $iltisUrl, $sign);
					$horo = filterKeyword($horo);
					$allHoros .= $horo . "\n" if $horo;
				}
				$index++;
			}
		}
		if ($index == 0 ) {
			# iltis regex #3, if nothing found
			dp('iltis regexp 3..');
			while($page =~ m/<p><em>(\w+) (\d+\.\d+\.-\d+\.\d+\.)<\/em> (.*?)<\/p>/sgi) {
				my $sign = $1;
				my $datum = $2;
				my $horo = $3;
				dp("grepIltis3 sign: $sign");
				dp("grepIltis3 datum: $datum");
				dp("grepIltis3 horo: $horo");
				if (defined($horo) && $horo ne '') {
					saveHoroToDB($horo, $iltisUrl, $sign);
					$horo = filterKeyword($horo);
					$allHoros .= $horo . "\n" if $horo;
				}
				$index++;
			}
		}
		dp("grepIltis allhoros ($index): ".$allHoros);
		$logtext = "iltis horo done. ($index)";
		saveHoroToFile($allHoros);
	} else {
		#warn("Can't parse $iltisUrl");
		$logtext = "Can't parse $iltisUrl";
		#return;
	}
	logmsg($logtext);
}

sub grepMenaiset {
	my ($data, $url, @rest) = @_;
	my $horos = '';
	my $index = 0;
	$dbh = KaaosRadioClass::connectSqlite($db);

	my $page = KaaosRadioClass::fetchUrl($menaisetUrl, 0);
	my ($allHoros, $logtext) = '';
	#logmsg($page);
	#while ($page =~ /<div class="field-item even"><p>([^<].*?)<\!--EndFragment/sgi) {
	#while ($page =~ /<div class="field-item even"><p>Lue(.*?)inline-teaser/sgi && $index < 100) {
	while ($page =~ /<div class="field-item even"><p>Lue(.*?)digilehdet-magazine/sgi && $index < 100) {
		my $newdata = $1;
		$newdata = parseComments($newdata);
		#logmsg($newdata);

		
		my $localsign = '';
		#my $horoscope = "";
		print("menaiset BLOB FOUND! index: $index") if $DEBUG1;
		dp('menaiset BLOBL found!');
		while ($newdata =~ /<h3>(.*?)<\/p>/sgi) {
			my $horodata = $1;
			my $localdata = '';
			#dp("\n\nHORO DATA: ->$horodata<-H \n");
			if ($horodata =~ /(.*?)<\/h/sgi) {
				$localsign = KaaosRadioClass::ktrim($1);
				print("SIGN FOUND: $localsign\n") if $DEBUG1;
			}
			if ($horodata =~ /p>(.*)/sgi) {
				$localdata = KaaosRadioClass::ktrim($1);
				$localdata = filterKeyword($localdata);
				$allHoros .= $localdata . "\n" if $localdata;
				dp("DATA FOUND: ->$localdata<-D");
			}
			saveHoroToDB($localdata, $url, $localsign);
		}
		$index++;
	}

	if ($index == 0) {
		$logtext .= 'grepMenaiset regex failed!';
	} else {
		saveHoroToFile($allHoros);
		#logmsg("allhoros: $allHoros");
		$logtext .= "grepMenaiset regex success! ($index)";
	}
	logmsg($logtext);
}

# save to a different file if certain keyword found.
sub filterKeyword {
	my ($msg, @rest) = @_;
	my $infofile = '';
	if	($msg =~ /(\bjussi.*)|(juhannu[sk])/i)	{$infofile = $mydir . '/horos_juhannus.txt'; }
	elsif	($msg =~ /\b(kesä)/i)			{$infofile = $mydir . '/horos_kesa.txt'; }
	elsif	($msg =~ /\b(kevä[ti])|(\bkevään)/i)		{$infofile = $mydir . '/horos_kevat.txt'; }
	elsif	($msg =~ /\b(talv[ie])/i)		{$infofile = $mydir . '/horos_talvi.txt'; }
	#elsif	($msg =~ /\b(talve)/i)			{($infofile) = $mydir . "horoskooppeja_talvi.txt"; }
	elsif	($msg =~ /(syksy)|(\bsyys[^t])/i)	{$infofile = $mydir . '/horos_syksy.txt'; }
	elsif	($msg =~ /(viikonl|vkl)/i)		{$infofile = $mydir . '/horos_vkl.txt'; }
	elsif	($msg =~ /(vappu)|(vapun)/i)	{$infofile = $mydir . '/horos_vappu.txt'; }
	elsif	($msg =~ /\b(joulu)/i)			{$infofile = $mydir . '/horos_joulu.txt'; }
	elsif	($msg =~ /(pikkujoulu)/i)		{$infofile = $mydir . '/horos_pikkujoulu.txt'; }
	elsif	($msg =~ /(loppiai)/i)			{$infofile = $mydir . '/horos_loppiainen.txt'; }
	elsif	($msg =~ /(\buv\b)|(uus[i]?vuos[i]?)/i)	{$infofile = $mydir . '/horos_uv.txt'; }
	elsif	($msg =~ /(\buuteen vuoteen\b)/i)		{$infofile = $mydir . '/horos_uv.txt'; }
	elsif	($msg =~ /(\buudenvuo)/i)		{$infofile = $mydir . '/horos_uv.txt'; }
	elsif	($msg =~ /(\bvuosi alkaa\b)/i)	{$infofile = $mydir . '/horos_uv.txt'; }
	#elsif	($msg =~ /\b(test)\b/i)			{($infofile) = glob $mydir . "horoskooppeja_for_testing.txt"; }
	elsif	($msg =~ /(rakkau[sd])/i)		{$infofile = $mydir . '/horos_rakkaus.txt';}
	elsif	($msg =~ /(maananta)/i)			{$infofile = $mydir . '/horos_maanantai.txt';}
	elsif	($msg =~ /(aloitat viikkosi)/i) {$infofile = $mydir . '/horos_maanantai.txt';}
	elsif	($msg =~ /(viikko alkaa)/i)		{$infofile = $mydir . '/horos_maanantai.txt';}
	elsif	($msg =~ /(pääsiä)/i)			{$infofile = $mydir . '/horos_pääsiäinen.txt';}
	#else 									{$infofile = $mydir . "horoskooppeja.txt";}
	
	if ($infofile ne '' && $infofile ne $horofile) {
		dp("fetch_horos2.pl: $& matched infofile: $infofile \n");
		KaaosRadioClass::addLineToFile($infofile, $msg);
		return;
	} else {
		print("filterKeyword: no match!\n") if $DEBUG1;
	}
	
	return $msg;
}

sub grepKeyword {
	my ($rimpsu, $nick, @rest) = @_;

	#my @wordlist = split(/\s/, $rimpsu);


	#chomp (my $weekday = `LC_ALL=fi_FI.utf-8; date +%A 2>>$logfile`);
	
	# fixme: "ensi maanantain"
	foreach my $weekda (@weekdaysak) {
		$rimpsu =~ s/$weekda/\$weekday/gi;
	}

	foreach my $monthlocal (@months) {
		$rimpsu =~ s/$monthlocal/\$month/gi;
	}

	my $season = checkSeason($month, 0);
	#my $seasongen = checkSeason($month, 1);			# genetiivi muoto?
	#my $seasonob = checkSeason($month, 2);				# objektiivimuoto?
	my $moonphase = KaaosRadioClass::conway();			# VAROITUS

	$rimpsu =~ s/$tomorrowak/\$tomorrowak/gi;

	$rimpsu =~ s/$tomorrow/\$tomorrow/gi;

	$rimpsu =~ s/$weekdak/\$weekdak/gi;

	$rimpsu =~ s/$nextmonth/\$nextmonth/gi;

	$rimpsu =~ s/$curmonth/\$month/gi;
	$rimpsu =~ s/$month/\$month/gi;

	$rimpsu =~ s/$curseason/\$season/gi;
	$rimpsu =~ s/$season/\$season/gi;
	#$rimpsu =~ s/\$seasongen/$seasongen/g;
	#$rimpsu =~ s/\$seasonob/$seasonob/g;
	$rimpsu =~ s/$moonphase/\$moonphase/g;
	$rimpsu =~ s/täysikuu\b/\$moonphase/gi;

	return $rimpsu;
}


sub checkSeason {
	my ($monthp, $number, @rest) = @_;
	# [perusmuoto, genetiivi, partitiivi/objekti?]
	my @result = ('vuodenaika', 'vuodenajan', 'vuodenaikaa');
	if ($monthp ~~ ['joulukuu', 'tammikuu', 'helmikuu']) {
		@result = ('talvi', 'talven', 'talvea');
	} elsif ($monthp ~~ ['maaliskuu', 'huhtikuu', 'toukokuu']) {
		@result = ('kevät', 'kevään', 'kevättä');
	} elsif ($monthp ~~ ['kesäkuu', 'heinäkuu', 'elokuu']) {
		@result = ('kesä', 'kesän', 'kesää');
	} elsif ($monthp ~~ ['syyskuu', 'lokakuu', 'marraskuu']) {
		@result = ('syksy', 'syksyn', 'syksyä');
	}
	
	return $result[$number];

}

# Create FTS4 table (full text search)
sub createHoroDB {
	$dbh = KaaosRadioClass::connectSqlite($db);
	# Using FTS (full-text search)
	my $stmt = qq(CREATE VIRTUAL TABLE HOROS using fts4(PVM, URL, HORO, SIGN));

	my $rv = $dbh->do($stmt);
	if($rv < 0) {
   		warn('DBI Error: '. DBI::errstr. "\n");
	} else {
   		print "Table $db created successfully.\n";
	}
	return;
}

# Save one horo to database. Params: $horo, $url, $sign
sub saveHoroToDB {
	my ($horo, $url, $sign, @rest) = @_;
	dp("saveHoroToDB: $horo") if $DEBUG1;
	my $pvm = time;
	# TODO: bind values
	my $sqlString = "Insert into horos values ('$pvm', '$url', '$horo', '$sign')";
	$howManySaved++;
	return KaaosRadioClass::writeToOpenDB($dbh, $sqlString);
}

sub saveHoroToFile {
	my ($data, @rest) = @_;
	return -1 if $data eq '';
	# parse last linefeed
	#$data = substr $data,0,length $data -1;
	return KaaosRadioClass::addLineToFile($horofile, grepKeyword($data));
}

# parse away comments, head, script and style tags
sub parseComments {
	my ($data, @rest) = @_;
	my $i = 0;
	while($data =~ s/<\!\-\-(.*?)\-\->//si) {
		$i++;
	}
	while ($data =~ s/<script.*?>(.*?)<\/script>//si) {
		$i++;
	}
	while ($data =~ s/<style.*?>(.*?)<\/style>//si) {
		$i++;
	}
	$data =~ s/<head>(.*?)<\/head>//si;
	dp("comments etc. elements parsed: $i");
	return $data;
}

sub logmsg {
	my ($logdata,@rest) = @_;
	dp("logdata: $logdata");
	return KaaosRadioClass::addLineToFile($logfile, localtime . '; '.$logdata);
}

sub dw {
	my ($data, @rest) = @_;
	return KaaosRadioClass::writeToFile($debuglog, @_);
}

# debug print
sub dp {
    return unless $DEBUG == 1 || $DEBUG1 == 1;
    print "debug: @_ \n";
}

$dbh->disconnect();
print "arg: $ARGV[0], how many saved: $howManySaved\n" if $DEBUG;
