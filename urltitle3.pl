#
# Created 25/08/2010
# by Will Storey
#
# continued by LAama1.
# Requirements:
#  - LWP::UserAgent (libwww-perl)
#  - HTML::Entities (decoding html characters)
#
# Settings:
#  /set urltitle_enabled_channels #channel1 #channel2 ...
#  Enables url fetching on these channels
#
#


use warnings;
use strict;
use Irssi;
use LWP::UserAgent;
use HTTP::Cookies;
#use Time::HiRes qw(time);
use HTML::Entities qw(decode_entities);
use utf8;
#use open ':std', ':encoding(UTF-8)';
binmode(STDIN,  ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
#binmode STDOUT, ":encoding(utf8)";
#binmode STDIN, ":encoding(utf8)";
#binmode STDERR, ":encoding(utf8)";
#binmode FILE, ':utf8';
#use open ':std', ':encoding(utf8)';

use DBI;
use DBI qw(:sql_types);

use Data::Dumper;

use Digest::MD5 qw(md5_hex);		# LAama1 28.4.2017
#use Encode qw(encode_utf8);
use Encode;

#use lib '/home/laama/Mount/kiva/.irssi/scripts';
#use lib '/usr/lib64/perl5/vendor_perl/';
use KaaosRadioClass;				# LAama1 13.11.2016

use vars qw($VERSION %IRSSI);
$VERSION = "20171226";
%IRSSI = (
	authors     => "Will Storey, LAama1",
	contact     => "LAama1",
	name        => "urltitle",
	description => "Fetches urls and prints their title and does other shit also.",
	license     => "Fublic Domain",
	url         => "http://kaaosradio.fi",
	changed     => $VERSION
);

my $tsfile = Irssi::get_irssi_dir()."/scripts/ts";
my $logfile = Irssi::get_irssi_dir()."/scripts/urllog_v2.txt";
my $cookie_file = Irssi::get_irssi_dir() . '/scripts/urltitle3_cookies.dat';
my $db = Irssi::get_irssi_dir(). "/scripts/links_fts.db";
my $debugfile = Irssi::get_irssi_dir()."/scripts/urlurldebug.txt";

my $howManyDrunk = 0;

my $DEBUG = 1;
my $DEBUG1 = 0;
my $DEBUG_decode = 0;
my $myname = "urltitle3.pl";

# Data type

my $newUrlData = {};
$newUrlData->{nick} = "";
$newUrlData->{date} = "";
$newUrlData->{url} = "";
$newUrlData->{title} = "";
$newUrlData->{desc} = "";
$newUrlData->{chan} = "";
$newUrlData->{md5} = "";
$newUrlData->{fetchurl} = "";
$newUrlData->{shorturl} = "";

my $shortModeEnabled = 0;
=pod
my @urlData;
$urlData[0] = "";		# nick
$urlData[1] = 0;		# date
$urlData[2] = "";		# url
$urlData[3] = "";		# title
$urlData[4] = "";		# description from the HTML to save to DB
$urlData[5] = "";		# channel
$urlData[6] = "";		# md5hash, hex
$urlData[7] = "";		# url to fetch from internet after conversions
$urlData[8] = "";		# shortened URL
=cut

unless (-e $db) {
	unless(open FILE, '>:utf8',$db) {
		Irssi::print("$myname: Unable to create or write file: $db");
		die;
	}
	close FILE;
	#createDB();
	createFstDB();
	Irssi::print("$myname: Database file created.");
}


my $cookie_jar = HTTP::Cookies->new(
	file => $cookie_file,
	autosave => 1,
);

my $max_size = 262144;		# bytes
my $useragent = "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.1.11) Gecko/20100721 Firefox/3.0.6";
#my $useragent = "Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:57.0) Gecko/20100101 Firefox/57.0";
my @headers = (
	'agent' => $useragent,
	'max_redirect' => 6,							# default 7
	'max_size' => $max_size,
	#'ssl_opts' =>
	'protocols_allowed' => ['http', 'https', 'ftp'],
	'protocols_forbidden' => [ 'file', 'mailto'],
	'timeout' => 5,									# default 180 seconds
	'cookie_jar' => $cookie_jar,
	'requests_redirectable' => ['GET', 'HEAD'],		# defaults GET HEAD
);

my $ua = LWP::UserAgent->new(@headers);


# Try to disable cert checking (lwp versions > 5.837)
eval {
	$ua->ssl_opts('verify_hostname' => 0);
	#$ua->proxy(['http', 'ftp'], 'http://proxy.....fi:8080/');
	1;
} or do {
};


# Strip and html-decode title or get size from url. Params: url
sub fetch_title {
	# TODO: add soundcloud etc. parsers here.
	my ($url, @rest) = @_;

	my $page = "";						# page source
	my $diffpage = "";
	my $size = 0;						# content size
	my $md5hex = "";					# md5 of the page

	#my $responsetime = Time::HiRes::time();
	my $response = $ua->get($url);
	#$responsetime = Time::HiRes::time() - $responsetime;
	#my $responseString = sprintf("%.3f",$responsetime);
	#Irssi::print("$myname: Response time: ${responseString}s");
	dd("fetch_title: content charset: " .($response->content_charset || "none"));		# utf8 or ISO-8859-1
	#da($response);

	if ($response->is_success) {
		Irssi::print("$myname: Successfully fetched $url, ".$response->content_type.", ".$response->status_line.", size: ".$size.", redirects: ".$response->redirects);
		my $finalURI = $response->request()->uri() || "";
		if ($finalURI ne "" && $finalURI ne $url) {
			$url = $finalURI;
		}

		$diffpage = $response->decoded_content();
		#$diffpage = $response->decoded_content(charset => 'none');
		#$page = $response->decoded_content(charset => 'none');
		$page = $response->decoded_content(charset => 'UTF-8');
		my $datasize = length($page);
		if ($page ne $diffpage) {
			dd("fetch_title: Different charsets presumably not UTF-8!");
		} else {
			dd("fetch_title: Same charset / content!");
		}

		if ($datasize > $max_size) {
			dp("fetch_title: DIFFERENT SIZES!! data: $datasize, max: $max_size");
			$page = substr($page, 0, $max_size);
			$datasize = length($page);
			dp("fetch_title: NEW SIZE data: $datasize") if $DEBUG1;
		}

		$size = $response->content_length || 0;
		
		if ($datasize > 0) {
			$md5hex = md5_hex(encode_utf8($page));
		} else {
			Irssi::print("$myname warning: Couldn't get size of the document!");
		}
		
		if ($size / (1024*1024) > 1) {
			$size = "size: " .sprintf("%.2f", $size / (1024*1024))."MiB";
		} elsif ($size / 1024 > 1) {
			$size = "size: " .sprintf("%.2f", $size / 1024) . "KiB";
		} elsif ($size > 0) {
			$size = "size: ".$size."B";
		} elsif ($size == 0) {
			$size = "";
		}

	} else {
		Irssi::print("$myname: Failure ($url): " . $response->code() . ", " . $response->message() . ", " . $response->status_line);
		
		# return nothing.
		return 0, 0,0, $md5hex;

		# return failure?
		return $response->status_line, 0,0, $md5hex;
	}
	
	if ($response->content_type !~ /(text)|(xml)/) {
		if ($shortModeEnabled == 1) {
			dd("Short mode enabled??");
			return "", 0 , 0, $md5hex;
		} else {
			return $response->content_type.", $size", 0, 0, $md5hex;		# not text, but some other file
		}
		
	}

	my ($titteli, $description, $titleInUrl) = getTitle($response, $url);
	
	return $titteli, $description, $titleInUrl, $md5hex;
}

# getTitle params. useragent response
sub getTitle {
	my ($response, $url, @rest) = @_;
	dp("getTitle") if $DEBUG1;
	my $countWordsUrl = $url;
	$countWordsUrl =~ s/^http(s)?:\/\/(www\.)?//g;		# strip https://www.
	
	# get Charset
	my $testcharset = $response->header('charset') || $response->content_charset || "";
	dd("getTitle response header charset: $testcharset");
	
	# get Title and Description
	my $newtitle = $response->header('title') || "";
	my $newdescription = $response->header('x-meta-description') || $response->header('Description') || "";
	dd("newtitle: $newtitle, newdescription: $newdescription");

	# HACK:
	my $temppage = $response->decoded_content;
	while ($temppage =~ s/<script.*?>(.*?)<\/script>//si) {	# g = all matches
		dp("script filtered..") if $DEBUG1;
	}
	while ($temppage =~ s/<style.*?>(.*?)<\/style>//si) {
		dp ("style filtered..") if $DEBUG1;
	}
	while ($temppage =~ s/<!--(.*?)-->//si) {
		dp("comment filtered..") if $DEBUG1;
	}
	KaaosRadioClass::writeToFile($debugfile . "2", $temppage) if $DEBUG1;

	#da($response);
	if ($temppage =~ /charset="utf-8"/i && falseUtf8Pages($url)) {
		dd("iltis!");
		$newtitle = checkAndEtu($newtitle, $testcharset) if $newtitle;
		$newdescription = checkAndEtu($newdescription, $testcharset) if $newdescription;
	} elsif ($temppage =~ /charset="utf-8"/i) {
		dd("getTitle utf-8 meta charset tag found manually from source!");
		# LAama 29.12.2017 $newtitle = checkAndEtu($newtitle, $testcharset) if $newtitle;
		#$newdescription = checkAndEtu($newdescription, $testcharset) if $newdescription;

	} elsif ($testcharset !~ /UTF8/i && $testcharset !~ /UTF-8/i) {
		
		dd("getTitle testcharset not UTF-8: ". $testcharset);
		dd("getTitle newtitle again: ". $newtitle);
		$newtitle = checkAndEtu($newtitle, $testcharset);
		$newdescription = checkAndEtu($newdescription, $testcharset);
	}

	my $title = "";
	
	if ($newtitle eq "") {
		if ($temppage =~ /<title\s?.*?>(.*?)<\/title>/si) {
			# TODO chomp linefeeds ?
			$title = $1;
			dp("getTitle backup titlematch: ". $title);
		}

	} elsif ($newtitle) {
		dd("getTitle: title = newtitle! $newtitle");
		$title = $newtitle;
	}

	my $titleInUrl = 0;
	if ($title ne "") {
		dd("getTitle undecoded title: $title") if $DEBUG1;
		#$title = KaaosRadioClass::replaceWeird($title);
		$titleInUrl = checkIfTitleInUrl($countWordsUrl, $title);
	}
	return decode_entities($title), decode_entities($newdescription), $titleInUrl;
}

### Encode to UTF8. Params. $string, $charset
sub etu {
	my ($string, $charset, @rest) = @_;
	dd("etu function. charset: $charset string before: $string");
	#return encode("UTF-8", $string);
	#return encode("UTF8", $string);
	Encode::from_to($string, $charset, 'utf8') if $charset && $string;
	dd("etu function, string after: $string");
	return $string;
}

### Check if charset is utf8 or not, and convert. Params: 1) String to convert 2) source charset.
sub checkAndEtu {
	my ($string, $charset, @rest) = @_;
	dp("checkAndEtu, charset: $charset, string: $string");
	my $returnString = "";
	if ($charset !~ /utf-8/i && $charset !~ /utf8/i) {
		dd("charset reported as different from utf8");
		if ($string =~ /Ã/) {
			dd("most likely ISO CHARS INSTEAD OF UTF8, converting from ${charset}");
			$returnString = etu($string, $charset);
		} elsif ($string =~ /[ÄäÖöÅå]/) {
			dd("UTF-8 CHARS FOUND, most likely NOT correct! (reported as ${charset})");
			#$returnString = etu($string, $charset);
			$returnString = $string;
		} else {
			dd("Didn't found any special characters. Converting..'");
			$returnString = etu($string, $charset);
		}
	} elsif ($charset =~ /UTF8/i || $charset =~ /UTF-8/i) {
		dd("charset reported as utf8");
		if ($string =~ /[Ã]/) {
			dd("ISO CHARS FOUND, INCORRECT! (reported as $charset)");
			$returnString = etu($string, $charset) || "";		
		} elsif ($string =~ /[ÄäÖöÅå]/) {
			dd("UTF-8 CHARS FOUND, CORRECT! (reported as $charset)");
			$returnString = $string;
		} else {
			dd("Didn't find any special characters. Not converting.");
			$returnString = $string;
		}
	}
	return $returnString;
}

### Check if title is allready found in URL. Params: $url, $title. Return 1/0
sub checkIfTitleInUrl {
	my ($url, $title, @rest) = @_;

	my ($samewords, $titlewordCount) = countSameWords($url, $title);
	dp("checkIfTitleInUrl titlewords: $titlewordCount, samewords: $samewords");

	if ($samewords >= 4 && ( $titlewordCount / $samewords) > (0.83 * $titlewordCount)) {
		dp("checkIfTitleInUrl bling1! title wordcount: $titlewordCount same words: $samewords");
		return 1;
	} elsif ($samewords == $titlewordCount) {
		dp("checkIfTitleInUrl bling2! samewords = title words = $samewords");
		return 1;
	}
	dp("checkIfTitleInUrl great news for the title!");
	return 0;

}

## Count words from sentence after special chars are removed. Params.
sub countWords {
	my ($row,@rest) = @_;
	
	my @array = split_row_to_array($row);
	my $count = 0;
	foreach my $val (@array) {
		$count++;
		dd("countWords: $val, count: $count") if $DEBUG1;
	}
	return $#array +1;
}


sub countSameWords {
	my ($url, $title, @rest) = @_;
	dd("countSameWords url: $url, \ntitle: $title");
	my @rows1 = split_row_to_array($url);	# url
	my @rows2 = split_row_to_array($title);	# title
	my $titlewordCount = $#rows2 + 1;
	my $count1 = 0;
	dd("countSameWords titlewordCount: $titlewordCount");
	foreach my $item (@rows2) {
		#dd("countSameWords: $item, count: $count1") if $DEBUG1;
		if ($item ~~ @rows1) {
		#if (grep /^$item/, @rows1 ) {
			$count1++;
			dd("countSameWords: $item, count: $count1");
			if ($count1 == $titlewordCount) {
				dd("countSameWords: bingo!");
				return $count1, $titlewordCount;
			}
			
		}
	}
	dd("   same words: $count1");
	return $count1, $titlewordCount;
}

# lowercase, remove weird chars. return formatted words
sub split_row_to_array {
	my ($row, @rest) = @_;
	dd("split_row_to_array before: $row");
	print ("poks") if $row =~ /\”/;
	print ("poks2") if $row =~ /\–/;
	print ("poks3") if $row =~ /\+/;
	#$row =~ s/[”\|:\"\+\,\!\(\)\–]//g;

	$row = replace_non_url_chars($row);
	$row =~ s/[^\w\s\-\.\/\+\#]//g;
	$row =~ s/\s+/ /g;
	$row = lc($row);
	
	dd("split_row_to_array after: $row");
	#my @returnArray = split(/[\s\&\|\+\-\–\–\_\.\/\=\?\#]+/, $row);
	my @returnArray = split(/[\s\&\+\-\–\–\_\.\/\=\?\#]+/, $row);
	dd("split_row_to_array words: " . ($#returnArray+1));

	return @returnArray;
}

sub replace_non_url_chars {
	my ($row, @rest) = @_;
	#dd("replace non url chars row: $row");

	my $debugString = "";
	if ($DEBUG1 == 1) {
		foreach my $char (split //, $row) {
			$debugString .= " " .ord($char) . Encode::encode_utf8(":$char");
		}
		dd("replace_non_url_chars debugstring: ".$debugString) if $DEBUG1;
	}
	

	#if ($row) {
	$row =~ s/ä/a/g;
	$row =~ s/Ä/a/g;
	$row =~ s/ö/o/g;
	$row =~ s/Ö/o/g;
	$row =~ s/Ã¤/a/g;
	$row =~ s/Ã¶/o/g;
	#$row =~ s/\s+/ /gi;
	#$row =~ s/\’//g;
	#}
	dd("replace non url chars row after: $row") if $DEBUG1;
	return $row;
}

sub shortenURL {
	my ($url, @rest) = @_;
    my $ua2 = new LWP::UserAgent;
    $ua2->agent($useragent . $ua->agent);
	$ua2->max_size(32768);
	$ua2->timeout(3);
    my $request = new HTTP::Request GET => "http://42.pl/url/?auto=1&url=$url";
    my $s = $ua2->request($request);
    my $content = $s->content();
	if ($content =~ /RATE-LIMIT/) { return "(error, rate-limit)"; }
	if ($content =~ /(http\:\/\/[^\s]+)/) {
		dp("shortenurl: $url, short: $1");
		return $1;
	}
	return "";
}
# Create FTS4 table (full text search)
sub createFstDB {
    #my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;
	my $dbh = KaaosRadioClass::connectSqlite($db);

	# Using FTS (full-text search)
	my $stmt = qq(CREATE VIRTUAL TABLE LINKS
			    using fts4(NICK,
							PVM,
							URL,
							TITLE,
							DESCRIPTION,
							CHANNEL,
							MD5HASH););

	my $rv = $dbh->do($stmt);
	if($rv < 0) {
   		Irssi::print ("$myname: DBI Error: ". DBI::errstr);
	} else {
   		Irssi::print("$myname: Table $db created successfully");
	}
	$dbh->disconnect();
}

# Create DB and table links
sub createDB {

    my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;

	my $stmt = qq(CREATE TABLE LINKS
      (NICK         TEXT,
       PVM          INT,
       URL        	TEXT,
       TITLE        TEXT,
	   DESCRIPTION  TEXT,
	   CHANNEL		TEXT,
	   MD5HASH		TEXT););
	
	my $rv = $dbh->do($stmt);
	if($rv < 0) {
   		Irssi::print ("$myname: DBI Error: ". DBI::errstr);
	} else {
   		Irssi::print("$myname: Table $db created successfully");
	}
	$dbh->disconnect();
}

# Save to sqlite DB
sub saveToDB {
	my ($nick, $url, $title, $description, $channel, $md5hex, @rest) = @_;
	dp("saveToDB") if $DEBUG1;
	my $pvm = time();
	my @dontsave = split(/ /, Irssi::settings_get_str('urltitle_dont_save_urls_channels'));
    return -1 if $channel ~~ @dontsave;
    
	KaaosRadioClass::addLineToFile($logfile, $pvm . "; " . $nick . "; " . $url . "; " . $title . "; " .$description);
	
	if ($DEBUG1) { Irssi::print("$myname-debug saveToDB: $db, pvm: $pvm, nick: $nick, url: $url, title: $title, description: $description, channel: $channel, md5: $md5hex"); }
	
	my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;
	my $sth = $dbh->prepare("INSERT INTO links VALUES(?,?,?,?,?,?,?)") or die DBI::errstr;
	$sth->bind_param(1, $nick);
	$sth->bind_param(2, $pvm, { TYPE => SQL_INTEGER });
	$sth->bind_param(3, $url);
	$sth->bind_param(4, $title);
	$sth->bind_param(5, $description);
	$sth->bind_param(6, $channel);
	$sth->bind_param(7, $md5hex);
	$sth->execute;
	$sth->finish();
	$dbh->disconnect();
	if ($DEBUG1) { Irssi::print("Tsilirimpsis!3"); }
	Irssi::print("$myname: URL $url from $channel saved to database.");
	return 0;
}

# Check from DB if old
sub checkForPrevEntry {
	my ($url, $newchannel, $md5hex, @rest) = @_;
	dp("checkForPrevEntry") if $DEBUG1;
	my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;
	#my $sth = $dbh->prepare("SELECT * FROM links WHERE url = ? AND channel = ?") or die DBI::errstr;
	my $sth = $dbh->prepare("SELECT * FROM LINKS WHERE (MD5HASH = ? or URL = ?) AND channel = ?") or die DBI::errstr;
	#my $sth = $dbh->prepare("SELECT * FROM LINKS WHERE (MD5HASH = ? and URL = ?) AND channel = ?") or die DBI::errstr;
	$sth->bind_param(1, $md5hex);
	$sth->bind_param(2, $url);
	$sth->bind_param(2, $newchannel);
	$sth->execute;

	# build elements into array
	my @elements;
	while(my ($nick, $pvm, $url, $title, $description, $channel) = $sth->fetchrow_array) {
		push (@elements, [$nick, $pvm, $url, $title, $channel]);
		if ($DEBUG1) { Irssi::print("urltitle3-debug: nick: $nick, pvm: $pvm, url: $url, channel: $channel"); }
	}
	$sth->finish();
	$dbh->disconnect();
	my $count = @elements;
	dp("$count elements found!") if $DEBUG1;
	if ($count == 0)	{ return; }
	else { return @elements };
}

sub apiConversion {
	my ($param, @rest) = @_;
	dp("apiConversion") if $DEBUG1;
	# spotify conversion
	$param =~ s/\:\/\/play\.spotify.com/\:\/\/open.spotify.com/;
		
	# soundcloud conversion, example: https://soundcloud.com/oembed?url=https://soundcloud.com/shatterling/shatterling-different-meanings-preview
	$param =~ s/\:\/\/soundcloud.com/\:\/\/soundcloud.com\/oembed\?url\=http\:\/\/soundcloud\.com/;
		
	# kuvaton conversion
	$param =~ s/\:\/\/kuvaton\.com\/browse\/[\d]{1,6}/\:\/\/kuvaton.com\/kuvei/;
	
	# imgur conversion
	if ($param =~ /\:\/\/imgur\.com\/gallery\/([\d\w\W]{2,8})/) {
		#$title .= "$url, ";
		# TODO: imgur-api
		my $image = $1;
		Irssi::print("imgur-klick! img: $image");
	}
	return $param;

}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	return if ($nick eq $server->{nick});   # self-test
	
	# Check we have an enabled channel
	my $enabled_raw = Irssi::settings_get_str('urltitle_enabled_channels');
	my @enabled = split(/ /, $enabled_raw);
	#return unless grep(/$target/, @enabled);
	
	# TODO if searching for old link..
	if ($msg =~ /\!url (.*)$/i) {
		return if KaaosRadioClass::floodCheck() > 0;
		my $searchWord = $1;
		my $sayline = findUrl($searchWord);
		dp("sig_msg_pub: found some results from $searchWord on channel $target. $sayline");
		$server->command("msg -channel $target $sayline") if grep(/$target/, @enabled);
		clearUrlData();
		return;
	}

	# ttp://
	if ($msg =~ /h?(ttps?:\/\/\S+)/i) {
		$newUrlData->{url} = "h${1}";
	} elsif ($msg =~ /(www\.\S+)/i) {
		$newUrlData->{url} = "http://" . $1;
	} else { 
		clearUrlData();
		return;
	}
	
	$newUrlData->{fetchurl} = $newUrlData->{url};
	
	# check if flooding too fast
	if (KaaosRadioClass::floodCheck() > 0) {
		clearUrlData();
		return;
	}
	
	$newUrlData->{nick} = $nick;
	$newUrlData->{chan} = $target;
	
	# check if flooding too many times in a row
	my $drunk = KaaosRadioClass::Drunk($nick);

	my $title = "";			# url title to print to channel
	my $description = "";	# url description to print to channel
	my $isTitleInUrl = 0;		# title or file
	my $md5hex = "";		# MD5 of requested page


	if (dontPrintThese($newUrlData->{url}) == 1) {
		($newUrlData->{title}, $newUrlData->{desc}, $isTitleInUrl, $newUrlData->{md5}) = fetch_title($newUrlData->{fetchurl});
		saveToDB($newUrlData->{nick}, $newUrlData->{url}, $newUrlData->{title}, $newUrlData->{desc}, $newUrlData->{chan}, $newUrlData->{md5});
		clearUrlData();
		return;
	}
	my @short_raw = split(/ /, Irssi::settings_get_str('urltitle_shortmode_channels'));
	if ($target ~~ @short_raw) {
		$shortModeEnabled = 1;
	} else {
		$shortModeEnabled = 0;
	}

	# kuvaton conversion
	if ($newUrlData->{fetchurl} =~ s/:\/\/kuvaton\.com\/browse\/[\d]{1,6}/:\/\/kuvaton.com\/kuvei/) {
		#$urlData[3] .= "$urlData[7] ";
		dp("kuvaton-klik!");
	}

	$newUrlData->{fetchurl} = apiConversion($newUrlData->{url});	#
		
	($newUrlData->{title}, $newUrlData->{desc}, $isTitleInUrl, $newUrlData->{md5}) = fetch_title($newUrlData->{fetchurl});
	my $newtitle = "";
	$newtitle = $newUrlData->{title} if $newUrlData->{title};

	my $oldOrNot = checkIfOld($server, $newUrlData->{url}, $newUrlData->{chan}, $newUrlData->{md5});
	
	print "$myname: Shortening url a bit..." if ($newtitle =~ s/(.{220})(.*)/$1.../);
	print "$myname: NOT JEE" if ($newtitle eq "0");
	$title = $newtitle;
	
	dp("sig_msg_pub: title: ".$newUrlData->{title}. ", description: ".$newUrlData->{desc});
	
	if ($newUrlData->{desc} && $newUrlData->{desc} ne "" && $newUrlData->{desc} ne "0" && length($newUrlData->{desc}) > length($newUrlData->{title})) {
		Irssi::print "Shortening description a bit..." if length($newUrlData->{desc}) > 220;
		if ($newUrlData->{desc} =~ /(.{220}).*/) {
			$description = $1 . "...";
		} else {
			$description = $newUrlData->{desc};
		}
		$title = $description unless noDescForThese($newUrlData->{url});
		Irssi::print "Lenght of new title: ". length($title) if $DEBUG1;
		#dp("sig_msg_pub found description: $description");
		dp("sig_msg_pub new title.");
	}

	my $sayline = "Title: $title" if $title;
	if (length($newUrlData->{url}) >= 70) {
		# my @short_raw = split(/ /, Irssi::settings_get_str('urltitle_shortmode_channels'));
		if ($shortModeEnabled == 0) {
			dp("Short mode enabled: " .$1);
			$newUrlData->{shorturl} = shortenURL($newUrlData->{url});
			$title .= " -> $newUrlData->{shorturl}" if ($newUrlData->{shorturl} ne "");			
		}
	}
		
	if ($drunk == 1 && $isTitleInUrl == 0 && $howManyDrunk < 2 && $title ne "" && $isTitleInUrl == 0) {
		$server->command("msg -channel $target tldr;") if grep(/$target/, @enabled);;
		$howManyDrunk++;
	} elsif ($title ne "" && $isTitleInUrl == 0) {
		$server->command("msg -channel $target $sayline") if grep(/$target/, @enabled);;
		$howManyDrunk = 0;
	}
	# save links from every channel
	saveToDB($newUrlData->{nick}, $newUrlData->{url}, $newUrlData->{title}, $newUrlData->{desc}, $newUrlData->{chan}, $newUrlData->{md5});
	clearUrlData();
	return;
}

# wanha
sub checkIfOld {
	my ($server, $url, $target, $md5hex) = @_;
	my $wanhadisabled = Irssi::settings_get_str('urltitle_wanha_disabled');
	dp("checkIfOld") if $DEBUG1;
	if ($wanhadisabled == 1) {
		dp("Wanha is disabled.");
		return 0;
	}
	
	my @prevUrls = checkForPrevEntry($url, $target, $md5hex);
	my $count = @prevUrls;
	#dp("checkIfOld count: $count");

	if ($count != 0 && $wanhadisabled != 1 && $howManyDrunk == 0) {
		my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($prevUrls[0][1]);
		$year += 1900;
		$mon += 1;
		$server->command("msg -channel $target w! ($prevUrls[0][0] @ $mday.$mon.$year ". sprintf("%02d", $hour).":".sprintf("%02d", $min).":".sprintf("%02d", $sec)." ($count)");
		return 1;
	}
	return 0;
}

sub findUrl {
	my ($searchword, @rest) = @_;
	Irssi::print("$myname: etsi request: $searchword");
	dp("findUrl") if $DEBUG1;
	my $returnstring;
	my $temp = "";
	if ($searchword =~ s/^id:? ?//i) {
		my @results;
		if ($searchword =~ /(\d+)/) {
			$searchword = $1;
			@results = searchIDfromDB($searchword);
		} else {
			my @results = searchDB($searchword);
		}
		#$returnstring .=
		dp("id search result dump: ");
		da(@results);
		#$temp = createAnswerFromResults(@results);
		return createAnswerFromResults(@results);
	} elsif ($searchword =~ s/^kaikki:? ?//i || $searchword =~ s/^all:? ?//i) {
		# print all found entries
		my @results = searchDB($searchword);
		$returnstring .= "Loton oikeat numerot: ";
		dp("Loton oikeat numerot");
		foreach my $line (@results) {
			# TODO: Limit to 3-5 results
			#$returnstring .= createAnswerFromResults(@$line)
			$returnstring .= createShortAnswerFromResults(@$line) .", ";
		}
	} else {
		# print 1st found item
		my @results = searchDB($searchword);
		my $amount = @results;
		#dp("results:");
		#da(@results);

		if ($amount > 1) {
			$returnstring = "Löytyi $amount, ID: ";
			my $i = 0;
			foreach my $id (@results) {
				$returnstring .= $results[$i][0].", ";	# collect ID's from results
				$i++;
			}
		} elsif ($amount == 1) {
			$returnstring .= "Löytyi 1, ";
			$returnstring .= "ID: $results[0][0], ";
			$returnstring .= "url: $results[0][3], ";
			$returnstring .= "title: $results[0][4], ";
			$returnstring .= "desc: $results[0][5]";
			#$temp = createAnswerFromResults(@{$results[0]});
			#dp("temp: ". $temp);
			#$returnstring .= $temp;
		} elsif ($amount == 0) {
			$returnstring = "Ei tuloksia.";
		}
	}
	$returnstring = $returnstring.$temp,
	dp("findUrl returnstring: $returnstring");
	dp("temp:". $temp);
	return $returnstring;
}

sub searchDB {
	my ($searchWord, @rest) = @_;
	dp("searchDB: $searchWord");
	my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;
	my $sqlString = "SELECT rowid,* from LINKS where rowid = ? or URL like ? or TITLE like ? or description LIKE ?";
	my $sth = $dbh->prepare($sqlString) or die DBI::errstr;
	$sth->bind_param(1, "%$searchWord%");
	$sth->bind_param(2, "%$searchWord%");
	$sth->bind_param(3, "%$searchWord%");
	$sth->bind_param(4, "%$searchWord%");
	$sth->execute();
	my @resultarray = ();
	my @line = ();
	my $index = 0;
	#dp("Results: ");
	while(@line = $sth->fetchrow_array) {
		dp("Line $index:");
		da(@line);
		push @{ $resultarray[$index]}, @line;
		$index++;
	}
	dp("searchDB '$searchWord' Dump:");
	da(@resultarray);
	dp("searchDB dump end.");
	return @resultarray;	
}

# search rowid = artist ID from database
sub searchIDfromDB {
	my ($id, @rest) = @_;
	my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;
	my $sth = $dbh->prepare("SELECT rowid,* FROM links where rowid = ?") or die DBI::errstr;
	$sth->bind_param(1, $id);
	$sth->execute();
	my @result = ();
	@result = $sth->fetchrow_array();
	$sth->finish();
	$dbh->disconnect();
	dp("SEARCH ID Dump:");
	da(@result);
	return @result;
}

sub createShortAnswerFromResults {
	my @resultarray = @_;
	my $amount = @resultarray;
	dp("create short answer fom results.. how many values: $amount");
	if ($amount == 0) {
		return "Ei tuloksia.";
	}

	my $returnstring = "";
	my $rowid = $resultarray[0];
	$returnstring = "ID: $rowid, ";
	my $nick = $resultarray[1];					# who added
	my $when = $resultarray[2];					# when added
	my $url = $resultarray[3];					# url
	$returnstring .= "url: $url";
	my $title = $resultarray[4];				# title
	my $desc = $resultarray[5];					# description
	my $channel = $resultarray[6];				# channel

	if ($rowid) {
		Irssi::print("$myname: Found: id: $rowid, nick: $nick, when: $when, title: $title, description: $desc, channel: $channel, url: $url");
		#Irssi::print("$myname: return string: $returnstring");
	}

	dp("stringi: $returnstring");
	#dp($string);
	return $returnstring;

}

# Create one line from one result!
sub createAnswerFromResults {
	dp("createAnswerFromResults");
	my @resultarray = @_;

	my $amount = @resultarray;
	dp(" #### create answer from results.. how many values: $amount");
	da(@resultarray);
	if ($amount == 0) {
		return "Ei tuloksia.";
	}

	my $returnstring = "";
	my $rowid = $resultarray[0];
	$returnstring = "ID: $rowid, ";
	my $nick = $resultarray[1];					# who added
	my $when = $resultarray[2];					# when added
	my $url = $resultarray[3];					# url
	$returnstring .= "url: $url, ";
	my $title = $resultarray[4];
	$returnstring .= "title: $title, ";
	dp("title: $title");
	my $desc = $resultarray[5];
	$returnstring .= "desc: $desc, ";
	my $channel = $resultarray[6];
	#$returnstring .= "kanava: $channel"; }
	my $md5hash = [7];
	#my $md5hash = "";
	#my $deleted = [8] || "";
	
	#if ($nick ne "") { $string .= "nick: $nick"; }

	if ($rowid) {
		Irssi::print("$myname: Found: id: $rowid, nick: $nick, when: $when, title: $title, description: $desc, channel: $channel, url: $url, md5: $md5hash");
		Irssi::print("$myname: return string: $returnstring");
	}

	dp("string: $returnstring");
	#dp($string);
	return $returnstring;

}

# Dont spam these domains.
sub dontPrintThese {
	my ($text, @rest) = @_;
	#return 1 if $text =~ /http:\/\/(m\.)?(www\.)*aamulehti\.fi/i;
	#return 1 if $text =~ /http:\/\/(m\.)?(www\.)*kuvaton\.com/i;
	#return 1 if $text =~ /http:\/\/(m\.)?(www\.)*explosm\.net/i;
	
	return 0;
}

sub falseUtf8Pages {
	my ($text, @rest) = @_;
	return 1 if $text =~ /iltalehti\.fi/i;
	
	return 0;
}

sub noDescForThese {
	my ($url, @rest) = @_;
	return 1 if $url =~ /youtube\.com/i;
	return 1 if $url =~ /youtu\.be/i;
	return 1 if $url =~ /imdb\.com/i;
	return 1 if $url =~ /dropbox\.com/i;
	return 1 if $url =~ /mixcloud\.com/i;
	return 1 if $url =~ /flightradar24\.com/i;
	#return 1 if $url =~ /bandcamp\.com/i;

	return 0;
}

sub clearUrlData {
	$newUrlData->{nick} = "";		# nick
	$newUrlData->{date} = 0;		# date
	$newUrlData->{url} = "";		# url
	$newUrlData->{title} = "";		# title
	$newUrlData->{desc} = "";		# desc
	$newUrlData->{chan} = "";		# channel
	$newUrlData->{md5} = "";		# md5hash
	$newUrlData->{fetchurl} = "";	# url to fetch
	$newUrlData->{shorturl} = "";	# short url
}


# debug print
sub dp {
	my ($string, @rest) = @_;
	if ($DEBUG == 1) {
		print("\n$myname debug: ".$string);
	}
}

sub dd {
	my ($string, @rest) = @_;
	if ($DEBUG_decode == 1) {
		print("\n$myname debug: ".$string);
	}
}

# debug print array
sub da {
	Irssi::print("debugarray: ");
	Irssi::print(Dumper(@_)) if ($DEBUG == 1 || $DEBUG_decode == 1);
}


sub sig_msg_pub_own {
	my ($server, $msg, $target) = @_;
	dp("own public");
	sig_msg_pub($server, $msg, $server->{nick}, "", $target);
}

Irssi::settings_add_str('urltitle', 'urltitle_enabled_channels', '');
Irssi::settings_add_str('urltitle', 'urltitle_wanha_disabled', '0');
Irssi::settings_add_str('urltitle', 'urltitle_shortmode_channels', '');
Irssi::settings_add_str('urltitle', 'urltitle_dont_save_urls_channels', '');
Irssi::settings_add_str('urltitle', 'urltitle_enable_descriptions', '0');

Irssi::signal_add('message public', 'sig_msg_pub');
#Irssi::signal_add('message own_public', 'sig_msg_pub_own');
Irssi::print("$myname v. $VERSION loaded.");
Irssi::print("\nNew commands:");
Irssi::print('/set urltitle_enabled_channels #1 #2');
Irssi::print('/set urltitle_wanha_disabled 0/1');
Irssi::print('/set urltitle_dont_save_urls_channels #1 #2');
Irssi::print('/set urltitle_shortmode_channels #1 #2');
Irssi::print('/set urltitle_enable_descriptions 0/1.');
