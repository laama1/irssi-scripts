package KaaosRadioClass;
use strict;
use warnings;
use lib $ENV{HOME}.'/perl5/lib/perl5';
use utf8;
binmode STDOUT, ':utf8';
binmode STDIN, ':utf8';

use Exporter;
use DBI;
use LWP::UserAgent;
use HTTP::Cookies;
use HTML::Entities qw(decode_entities);
use Encode;
use URI::Escape;
use JSON;

use Data::Dumper;

#
# module for kaaosradio irc-scripts
# author: LAama1
# contact: LAama1 @ ircnet
# date created: 17.9.2016
# date changed: 17.9.2016, 21.9.2016, 29.7.2017, 9.10.2017, 21.10.2017
# date changed: 6.11.2017, 17.12.2017, 18.12.2017, 3.2.2018, 20.7.2018
# date changed: 9.9.2018, added ktrim function


use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
$VERSION = 1.02;
@ISA = qw(Exporter);
@EXPORT = ();
@EXPORT_OK = qw(readLastLineFromFilename readTextFile writeToFile addLineToFile getNytsoi24h replaceWeird stripLinks connectSqlite writeToDB getMonthString);

#$currentDir = cwd();
my $currentDir = $ENV{HOME}.'/.irssi/scripts';
# tsfile, time span.. save value of current time there. For flood protect.
my $tsfile = "$currentDir/ts";	# ????
my $djlist = "$currentDir/dj_list.txt";
my $database;

#my $myname = $0;
my $DEBUG = 1;
my $DEBUG_decode = 0;

my $floodernick;
my $floodertimes = 0;
my $flooderdate = time;		# init

# returns last line from file -param.
sub readLastLineFromFilename {
	my ($file, @rest) = @_;

	my $readline = '';
	if (-e $file) {
		open (INPUT, "<$file:utf8") || return -1;
		while (<INPUT>)	{
			chomp;
			$readline = $_;
		}
		close (INPUT) || return -2;
	} else {
		return -3;
	}
	return $readline;
}

sub readLinesFromDataBase {
	my ($db, $string, @rest) = @_;
	dp("Reading lines from DB.");
	my $dbh = connectSqlite($db);
	return $dbh if ($dbh < 0);
	my $sth = $dbh->prepare($string) or return DBI::errstr;
	$sth->execute();
	my @returnArray;
	my @line;
	my $index = 0;
	while(@line = $sth->fetchrow_array) {
		dp("--fetched a line--");
		dp(Dumper @line);
		#push @{ $returnArray[$index] }, @line;
		#push @returnArray, \@line;
		$returnArray[$index] = @line;
		#push @{ $Hits[$i] }, $i;
		dp("Index: $index \n");
		$index++;
	}
	dp('return array:');
	dp(Dumper(@returnArray));
	$dbh->disconnect();
	return @returnArray;
}

sub readLineFromDataBase {
	my ($db, $string, @rest) = @_;
	dp("Reading lines from DB $db.");
	my $dbh = connectSqlite($db);
	return $dbh if ($dbh < 0);
	my $sth = $dbh->prepare($string) or return DBI::errstr;
	$sth->execute();

	if(my @line = $sth->fetchrow_array) {
		dp('--fetched a result--');
		dp(Dumper @line);
		$sth->finish();
		$dbh->disconnect();
		return @line;
	}
	dp('-- Did not find a result');
	$sth->finish();
	$dbh->disconnect();
	#return @returnArray, "jee", $db, $string;
	return;
}

sub readTextFile {
	my ($file, @rest) = @_;
	my @returnArray;
	open(INPUT, "<$file:utf8") || do {
		return -1;
	};
	while(<INPUT>) {
		chomp;
		push @returnArray, $_;
	}
	close (INPUT) || return -1;
	return (\@returnArray);
}

# add one line of text to a file given in param
sub addLineToFile {
	my ($filename, $textToWrite, @rest) = @_;
    #open (OUTPUT, ">>$filename") || return -1;
	open OUTPUT, '>>:utf8', $filename || return -1;
    print OUTPUT $textToWrite ."\n";
    close OUTPUT || return -2;
	return 0;
}

# add content to new file
sub writeToFile {
	my ($filename, $textToWrite, @rest) = @_;
	open (OUTPUT, '>:utf8', $filename) || return -1;
	print OUTPUT $textToWrite ."\n";
	close OUTPUT || return -2;
	dp('Write done to '. $filename);
	return 0;
}

# overwrite
sub writeArrayToFile {
	my ($filename, @array) = @_;
	open my $OUTPUT, '>:utf8', $filename || do {
		return -1;
	};
	foreach my $line (@array) {
		print $OUTPUT $line . "\n";
	}
	close $OUTPUT || return -2;
	dp('write array done');
	return 0;
}

# check if people are flooding two or more commands too soon
sub floodCheck {
	my ($timedifference, @rest) = @_ || 3;
	my $last = 0;
	my $cur = time;

	$last = readLastLineFromFilename($tsfile);
	writeToFile($tsfile, $cur);
	if ($cur - $last < $timedifference) {
		return 1;									# return 1, means "flooding"
	}
	return 0;
}

# Return true if flooding too many (urls) in a row
sub Drunk {
	my ($nick, @rest) = @_;
	if ($nick eq $floodernick) {
		$floodertimes++;
		if ($floodertimes > 5 && (time - $flooderdate <= 600)) {
			return 1;
		} elsif ($floodertimes > 5 && (time - $flooderdate > 600)) {	#10min
			$flooderdate = time;
			$floodertimes = 0;
		} else {
		}
	} else {
		$floodernick = $nick;
		$floodertimes = 0;
		$flooderdate = time;
	}
	return 0;
}

# get stream2 !nytsoi value
sub getNytsoi24h {
	my $rimpsu = '';
	$rimpsu = `/home/kaaosradio/stream/meta_stream2.sh nytsoi`;
	chomp $rimpsu;
	return $rimpsu;
}

# trim excess white space
sub ktrim {
	my $text = shift;
	# Special chars
	$text =~ s/^[\s\t]+//g;		# Remove trailing/beginning whitespace
	$text =~ s/[\s\t]+$//g;
	$text =~ s/[\s]+/ /g;		# convert multiple spaces to one
	$text =~ s/[\t]+//g;		# remove tabs within..
	$text =~ s/[\n\r]+//g;		# remove line feeds
	return $text;
}

# replace weird html characters
sub replaceWeird {
	my ($text, @rest) = @_;
	return unless defined $text;

	dp("Text before: $text");
	$text = Encode::decode('utf8', uri_unescape($text));
	dp("Text before2: $text");
	# HTML encoded
	return 0 unless ($text);

	$text =~ s/\&quot;/\"/gi;	# replace &quot; with "
	$text =~ s/\&quote;/\"/gi;
	$text =~ s/\&\#039;/\'/g;	# replace &#039; with '
	$text =~ s/\&amp;/\&/gi;		# replace &amp; with &
	$text =~ s/\&lt;/\</gi;		# replace &lt; with <
	$text =~ s/\&gt;/\>/gi;		# replace &gt; with >
	$text =~ s/(&#10;)+//g;		# linefeed
	$text =~ s/(&#13;)+//g;		# carriage return
	$text =~ s/(&#039\;)+/'/g;	# '
	
	# ASCII encoded
    $text =~ s/\%20/ /g;        # asciitable.com
    $text =~ s/\%3A/:/gi;		# :
    $text =~ s/\%2C/,/gi;		# ,
    $text =~ s/\%2F/\//gi;       # /
    $text =~ s/\%3F/\?/gi;       # ?
    $text =~ s/\%26/&/g;		# &
	$text =~ s/\%23/#/g;		# #
    $text =~ s/Ã¨/é/g;			# é
	$text =~ s/Ã¤/ä/g;			# ä
	$text =~ s/Ã¶/ö/g;			# ö
	$text =~ s/Ã¥/å/g;			# å
	$text =~ s/õ/ä/g;			# ä
    $text =~ s/Õ/Ä/g;			# Ä
    $text =~ s/÷/ö/g;			# ö
	

	# UTF encoded
    $text =~ s/\%C3\%96/Ö/gi;	# Ö
	$text =~ s/\%C3\%A4/ä/gi;	# ä
	$text =~ s/\%C3\%84/Ä/gi;	# Ä
	$text =~ s/\%C3\%B6/ö/gi;	# ö
	$text =~ s/\%C3\%A5/å/gi;	# å
	$text =~ s/\%C3\%A8/è/gi;	# è
	$text =~ s/\%C3\%A9/é/gi;	# é
	$text =~ s/\%C3\%AD/í/gi;	# í
	$text =~ s/\%C3\%BC/ü/gi;	# ü
	$text =~ s/\%C3\%B4/ô/gi;	# ô
	$text =~ s/\%C3\%A1/á/gi;	# á
	$text =~ s/\%C3\%88/È/gi;	# È
	$text =~ s/\%C3\%93/1\/2/g; # 1/2 

	# Special chars
	$text =~ s/^[\s\t]+//g;		# Remove trailing/beginning whitespace
	$text =~ s/[\s\t]+$//g;
	$text =~ s/[\s]+/ /g;		# convert multiple spaces to one
	$text =~ s/[\t]+//g;		# remove tabs within..
	$text =~ s/[\n\r]+//g;		# remove line feeds

	$text =~ s/\x10//g;
	$text =~ s/\x13//g;
	$text =~ s/\x97/-/g;		# convert long dash to normal

	$text =~ s/\\x\{e4\}/ä/g;	# ä, JSON tms.
	
	#decode_entities($text);
	#$text = Encode::decode('utf8', uri_unescape($text));
	dp("Text after: $text");
	return $text;
}

sub stripLinks {
	my ($string, @rest) = @_;
	if ( $string =~ /(<a.*href.*>)[\s\S]+?<\/a>/) {
		$string =~ s/$1//g;
		$string =~ s/<\/a>//g;
		return $string;
	}
	return $string;
}

sub connectSqlite {
	my ($dbfile, @rest) = @_;
	unless (-e $dbfile) {
		return -1;						# return error
	}
	my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile",'','', {RaiseError => 1});
	return $dbh if $dbh;
	return -2;
}

sub writeToOpenDB {
	my ($dbh, $string) = @_;
	my $rv = $dbh->do($string);
	if ($rv < 0) {
		dp('KaaosRadioClass.pm, DBI Error: '.DBI::errstr);
   		return DBI::errstr;
	}
	return 0;
}

sub writeToDB {
	my ($db, $string) = @_;
    my $dbh = connectSqlite($db);
	return $dbh if ($dbh < 0);

	my $rv = $dbh->do($string);
	if ($rv < 0){
		dp('KaaosRadioClass.pm, DBI Error: '.DBI::errstr);
   		return DBI::errstr;
	}
	$dbh->disconnect();
	return 0;
}

sub closeDB {
	my ($dbh, @rest) = @_;
	$dbh->disconnect() or return -1;
	return 0;
}

# get month based on integer 1-12. Optional parameter: lowercase enabled or not
sub getMonthString {
	my ($month, $lowercase, @rest);
	($month, $lowercase, @rest) = @_
	if ($month > 12 || $month < 1) return;
	my @months = qw(Tammikuu Helmikuu Maaliskuu Huhtikuu Toukokuu Kesäkuu Heinäkuu Elokuu Syyskuu Lokakuu Marraskuu Joulukuu);
	if ($lowercase == 1) {
		return lc $months[$month-1];	
	}
	return $months[$month-1];
}

sub readDjList {
	return readTextFile($djlist);
}

sub fetchUrl {
	my ($url, $getsize);
	($url, $getsize) = @_;
	dp('fetchUrl url: '. $url);
	#$url = decode_entities($url);
	my $useragent = 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.1.11) Gecko/20100721 Firefox/3.0.6';
	my $cookie_file = $currentDir .'/KRCcookies.dat';
	my $cookie_jar = HTTP::Cookies->new(
		file => $cookie_file,
		autosave => 1,
	);
	my $ua = LWP::UserAgent->new('agent' => $useragent, max_size => 265536);
	$ua->cookie_jar($cookie_jar);
	$ua->timeout(3);				# 3 seconds
	$ua->protocols_allowed( [ 'http', 'https', 'ftp'] );
	$ua->protocols_forbidden( [ 'file', 'mailto'] );
	#$ua->proxy(['http', 'ftp'], 'http://proxy.jyu.fi:8080/');
	$ua->ssl_opts('verify_hostname' => 0);

	my $response = $ua->get($url);
	my $size = 0;
	my $page = '';
	my $finalURI = '';
	if ($response->is_success) {
		$page = $response->decoded_content();		# $page = $response->decoded_content(charset => 'none');
		$size = $response->content_length || 0;		# or content_size?
		if ($size / (1024*1024) > 1) {
			$size = sprintf("%.2f", $size / (1024*1024)).'MiB';
		} elsif ($size / 1024 > 1) {
			$size = sprintf("%.2f", $size / 1024) . 'KiB';
		} else {
			$size = $size.'B';
		}
		$finalURI = $response->request()->uri() || '';
		#Irssi::print("Successfully fetched $url. ".$response->content_type.", ".$response->status_line.", ". $size);
	} else {
		#return("Failure ($url): " . $response->code() . ", " . $response->message() . ", " . $response->status_line);
		return -1;
		#return;
	}
	if (defined $getsize && $getsize == 1) {
		return $page, $size, $finalURI;
	} else {
		return $page;
	}
}

sub getJSON {
	my ($url, @rest) = @_;
	my $response = fetchUrl($url, 0);
	if ($response && $response eq '-1') {
		dp('error fetching url!');
		return -1;
	}
	return -2 unless $response;
	
	my $json = JSON->new->utf8;
	$json->convert_blessed(1);

	$json = decode_json($response);
	return $json;
}

sub dp {
    return unless $DEBUG == 1;
    #Irssi::print("$myname-debug: @_");
    print("debug: @_");
}


sub da {
	return unless $DEBUG == 1;
	print('debug array:');
	print Dumper (@_);
}

sub conway {
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
1;		# loaded OK
