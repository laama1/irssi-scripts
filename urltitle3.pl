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

#	/set urltitle_wanha_channels #channel1 #channel2
#	/set urltitle_wanha_disabled 0/1
#	/set urltitle_dont_save_urls_channels #channel1 #channel2 -- keep these channels in secret
#	/set urltitle_shorten_url_channels #channel1 #channel2		-- print limited amount of info to channel
#	/set urltitle_enable_descriptions 0/1.
#
#


use warnings;
use strict;
use Irssi;
use POSIX;
use LWP::UserAgent;
use HTTP::CookieJar::LWP;
use HTTP::Response;
use HTML::Entities qw(decode_entities);
use utf8;
use Date::Parse;
use DBI;
use DBI qw(:sql_types);

use Data::Dumper;

use Digest::MD5 qw(md5_hex);		# LAama1 28.4.2017
#use Encode qw(encode_utf8);
use Encode;
use Time::Piece;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;				# LAama1 13.11.2016

use vars qw($VERSION %IRSSI);
$VERSION = '2024-06-12';
%IRSSI = (
	authors     => 'Will Storey, LAama1',
	contact     => 'LAama1',
	name        => 'urltitle',
	description => 'Fetches urls and prints their title and does other shit also.',
	license     => 'Fublic Domain',
	url         => 'http://kaaosradio.fi',
	changed     => $VERSION,
);

my $DEBUG = 1;
my $DEBUG1 = 0;
my $DEBUG_decode = 0;

my $logfile = Irssi::get_irssi_dir().'/scripts/urllog_v2.txt';
my $cookie_file = Irssi::get_irssi_dir() . '/scripts/urltitle3_cookies.dat';
my $db = Irssi::get_irssi_dir(). '/scripts/links_fts.db';
my $debugfile = Irssi::get_irssi_dir().'/scripts/urlurldebug.txt';
my $apikeyfile = Irssi::get_irssi_dir(). '/scripts/youtube_apikey';
my $apikey = KaaosRadioClass::readLastLineFromFilename($apikeyfile);
my $howDrunk = 0;
my $dontprint = 0;
my $imgurUrl = 'farside.link/rimgo';
#my $invidiousUrl = 'https://invidious.private.coffee';
my $invidiousUrl = 'https://farside.link/invidious';
#my $invidiousUrl ='https://invidious.protokolla.fi';
#my $twitterurl = 'https://xcancel.com';
my $twitterurl = 'https://farside.link/nitter';
my $instaurl = 'https://farside.link/proxigram';
my $redditUrl = 'farside.link/libreddit';
my $hsUrl = 'https://archive.is/newest/';

my $myname = 'urltitle3.pl';

# Data type

my $newUrlData = {};
$newUrlData->{nick} = '';			# who posted url
$newUrlData->{date} = '';			# when
$newUrlData->{url} = '';			# what was the original url
$newUrlData->{title} = '';			# what is the title of the final url
$newUrlData->{desc} = '';			# what is the description
$newUrlData->{chan} = '';			# on which channel
$newUrlData->{md5} = '';			# hash of the page that was fetched
$newUrlData->{fetchurl} = '';		# which url to actually fetch
$newUrlData->{shorturl} = '';		# shortened url for the link
$newUrlData->{responsecode} = '';
$newUrlData->{extra} = '';

my $shortModeEnabled = 0;			# if enabled, reduces garbage sent to channel
my $shorturlEnabled = 0;			# enable short url

unless (-e $db) {
	unless(open FILE, '>:utf8',$db) {
		prindw("Stop. Unable to create or write file: $db");
		die;
	}
	close FILE;
	createFstDB();
	prind("Database file created.");
}


#my $cookie_jar = HTTP::Cookies->new(
my $cookie_jar = HTTP::CookieJar::LWP->new (
	file => $cookie_file,
	autosave => 1,
);
my $max_size = 262144;		# bytes
#my $useragentOld_en = 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.1.11) Gecko/20100721 Firefox/3.0.6';
my $useragentOld = 'Mozilla/5.0 (X11; U; Linux i686; fi-FI; rv:1.9.1.11) Gecko/20100721 Firefox/3.0.6';
my $useragentNew = 'Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:96.0) Gecko/20100101 Firefox/96.0';
my $useragentBot = 'URLPreviewBot 1.0';
my %headers = (
	'agent' => $useragentOld,
	'max_redirect' => 6,							# default 7
	'max_size' => $max_size,
	#'ssl_opts' => ['verify_hostname' => 0],			# disable cert checking. Ei toimi jos LWP::Useragent käytössä.
	'protocols_allowed' => ['http', 'https', 'ftp', 'gopher'],
	'protocols_forbidden' => [ 'file', 'mailto'],
	'timeout' => 4,									# default 180 seconds
	'cookie_jar' => $cookie_jar,
	#'default_headers' => 
	#'requests_redirectable' => ['GET'],		# defaults GET HEAD
	#'parse_head' => 1,
);

my $ua = LWP::UserAgent->new(%headers);
$ua->ssl_opts('verify_hostname' => 0);
# Try to disable cert checking (lwp versions > 5.837)
eval {
	$ua->ssl_opts('verify_hostname' => 0);
	#$ua->proxy(['http', 'ftp'], 'http://10.7.0.4:3128/');
	1;
} or do {
};
print(%headers) if $DEBUG1;

# new headers for youtube and mixcloud etc.
sub set_useragent {
	my ($choice, @rest) = @_;
	if ($choice == 1) {
		$ua->agent($useragentOld);
	} elsif ($choice == 2) {
		$ua->agent($useragentNew);
	} elsif ($choice == 3) {
		$ua->agent($useragentBot);
	}
	return;
}

sub add_header {
	my ($name, $value, @rest) = @_;
	#$headers{$name} = $value;
}

# format youtube timestamp
sub format_time {
	my ($value, @rest) = @_;
	my $time_object = Time::Piece->strptime($value, "%Y-%m-%dT%H:%M:%SZ");	# ISO8601
	my $local_time = localtime;
	my $diff = $local_time - $time_object;
	print(__LINE__ . ': diff in seconds: ' . $diff . ', years: ' . floor($diff / 29030400) . 'y, months: ' . floor($diff / 2419200) . 'mon, weeks: ' . floor($diff / 604800) . 'wk, days: ' . floor($diff / 86400) . 'days, hours: ' . floor($diff / 3600) . 'h, minutes: ' . floor($diff / 60) . 'min');	# debug
	my $result = '';
	if ($diff >= 29030400) {
    	$result = sprintf("%.1f", ($diff / 29030400)) . 'y';
	} elsif ($diff >= 2419200) {
		$result = sprintf("%.1f", ($diff / 2419200)) . 'mon';
	} elsif ($diff >= 604800) {
		$result = sprintf("%.1f", ($diff / 604800)) . 'wk';
	} elsif ($diff > 86400) {
		$result = sprintf("%.1f", ($diff / 86400)) . 'days';
	} elsif ($diff > 3600) {
		$result = sprintf("%.1f", ($diff / 3600)) . 'h';
	} elsif($diff > 60) {
		$result = sprintf("%.f", $diff / 60) . 'mins';
	} else {
		$result .= 's';
	}
	$result .= ' ago';
	return $result;
}

# Strip and html-decode title or get size from url. Params: url
sub fetch_title {
	my ($url, $method, $content, @rest) = @_;
	dp(__LINE__.' url: ' . $url . ', method: ' . $method . ', content: ' . $content) if $DEBUG1;
	my $page = '';						# page source decoded to utf8
	my $diffpage = '';					# page source decoded
	my $size = 0;						# content size
	my $md5hex = '';					# md5 of the page

	my $response = $ua->get($url);
	#my $response = $ua->request(HTTP::Request->new($method, $url, \%headers, $content));
	if ($response->is_success) {
		prind("Successfully fetched $url, ".$response->content_type.', '.$response->status_line.', size: '.$size.', redirects: '.$response->redirects);
		my $finalURI = $response->request()->uri() || '';
		if ($finalURI ne '' && $finalURI ne $url) {
			# save redirect url
			$url = $finalURI;
		}

		$diffpage = $response->decoded_content();
		#$diffpage = $response->decoded_content(charset => 'none');
		#$page = $response->decoded_content(charset => 'none');
		$page = $response->decoded_content(charset => 'UTF-8');
		my $datasize = length $page;
		if ($page ne $diffpage) {
			dd(__LINE__.':fetch_title: Different charsets presumably not UTF-8!') if $DEBUG1;
		} else {
			dd(__LINE__.':fetch_title: Same charset / content as reported!') if $DEBUG1;
		}

		if ($datasize > $max_size) {
			#dd(__LINE__.": fetch_title: DIFFERENT SIZES!! data: $datasize, max: $max_size") if $DEBUG1;
			$page = substr $page, 0, $max_size;
			$datasize = length $page;
			#dd(__LINE__.": fetch_title: NEW SIZE data: $datasize") if $DEBUG1;
		}

		$size = $response->content_length || 0;
		
		if ($datasize > 0) {
			$md5hex = md5_hex(Encode::encode_utf8($page));
		} else {
			prindw("Couldn't get size of the document!");
		}
		
		if ($size / (1024*1024) > 1) {
			$size = 'size: ' .sprintf("%.2f", $size / (1024*1024)) . 'MiB';
		} elsif ($size / 1024 > 1) {
			$size = 'size: ' .sprintf("%.2f", $size / 1024) . 'KiB';
		} elsif ($size > 0) {
			$size = "size: ${size}B";
		} elsif ($size == 0) {
			$size = '';
		}

	} else {
		prindw("Failure ($url): code: " . $response->code() . ', message: ' . $response->message() . ', status line: ' . $response->status_line);
		$newUrlData->{responsecode} = $response->code();
		#da(__LINE__, $response);
		#return 'Error: '.$response->status_line, 0,0, $md5hex;
		return '',0,0,'';
	}

	if ($response->content_type !~ /(text)|(xml)/) {
		# if not text or xml
		if ($shortModeEnabled == 1) {
			dp(__LINE__.': Short mode enabled = 1') if $DEBUG1;
			return '', 0 , 0, $md5hex;
		} else {
			return 'Mimetype: '.$response->content_type.", $size", 0, 0, $md5hex;		# not text, but some other type of file
		}
	}

	my ($titteli, $description, $titleInUrl) = getTitle($response, $url);

	if (length $titteli > 0) {
		return 'Title: '.$titteli, $description, $titleInUrl, $md5hex;
	} else {
		return '', $description, $titleInUrl, $md5hex;
	}
}

# getTitle params. useragent response
sub getTitle {
	my ($response, $url, @rest) = @_;
	my $countWordsUrl = $url;
	$countWordsUrl =~ s/^http(s)?\:\/\/(www\.)?//g;		# strip https://www. # FIXME 2024-02-13
	#$countWordsUrl =~ s/\.[\w\d]{1.5}$//g;				# strip .html or .net from the end (dangerous)
	
	# get Charset
	my $headercharset = $response->header('charset') || '';
	my $contentcharset = $response->content_charset || '';

	my $ogtitle = ''; #$response->header('og:title') || '';		# open graph title
	#my $ogdescription = $response->header('og:description') || '';		# open graph desc
	
	my $testcharset = $response->header('charset') || $response->content_charset || '';
	#dd(__LINE__.": \ngetTitle: response header charset: $testcharset\nheader charset: ".$headercharset.', content charset: '.$contentcharset);
	#dd('og:title: '.$ogtitle.', og:description: '.$ogdescription);

	# get Title and Description
	my $newtitle = $response->header('title') || '';
	my $newdescription = $response->header('x-meta-description') || $response->header('Description') || $ogtitle || '';

	# HACK:
	my $temppage = KaaosRadioClass::ktrim($response->decoded_content);
	while ($temppage =~ s/<script.*?>(.*?)<\/script>//si) {
		dp(__LINE__.':getTitle script tags filtered..') if $DEBUG1;
	}
	while ($temppage =~ s/<style.*?>(.*?)<\/style>//si) {
		dp(__LINE__.':getTitle style tags filtered..') if $DEBUG1;
	}
	while ($temppage =~ s/\<\!--(.*?)--\>//si) {
		dp(__LINE__.':getTitle comment tags filtered..') if $DEBUG1;
	}
	KaaosRadioClass::writeToFile($debugfile . '2', $temppage) if $DEBUG1;
	

	if ($temppage =~ /property="og\:description" content="(.*?)"/si) {
		# open graph title, high priority
		$newdescription = $1;
		dd(__LINE__.' og description found! '. $newdescription);
	}

	if ($temppage =~ /charset="utf-8"/i && falseUtf8Pages($url)) {
		$newtitle = checkAndEncode($newtitle, $testcharset) if $newtitle;
		$newdescription = checkAndEncode($newdescription, $testcharset) if $newdescription;
	} elsif ($temppage =~ /charset="utf-8"/i) {
		dd(__LINE__.':getTitle utf-8 meta charset tag found manually from source!');
		# LAama 29.12.2017 $newtitle = checkAndEncode($newtitle, $testcharset) if $newtitle;
		#$newdescription = checkAndEncode($newdescription, $testcharset) if $newdescription;

	} elsif ($testcharset !~ /UTF8/i && $testcharset !~ /UTF-8/i) {
		dd(__LINE__.':getTitle testcharset not UTF-8: '. $testcharset);
		dd(__LINE__.':getTitle newtitle again: '. $newtitle);
		$newtitle = checkAndEncode($newtitle, $testcharset);
		$newdescription = checkAndEncode($newdescription, $testcharset);
	}

	my $title = '';
	
	if ($newtitle eq '') {
		if ($temppage =~ /<title\s?.*?>(.*?)<\/title>/si) {
			$title = decode_entities($1);
			dp(__LINE__.':getTitle backup titlematch: '. $title) if $DEBUG1;
		}

	} elsif ($newtitle) {
		dd(__LINE__.": getTitle: title equals newtitle! $newtitle") if $DEBUG1;
		$title = decode_entities($newtitle);
	}

	my $titleInUrl = 0;
	if ($title ne '') {
		dd(__LINE__.": getTitle undecoded title: $title") if $DEBUG1;
		$titleInUrl = checkIfTitleInUrl($countWordsUrl, $title);
	}
	return $title, decode_entities($newdescription), $titleInUrl;
}

sub get_channel_topic {
	my ($server, $channel) = @_;
	my $chanrec = $server->channel_find($channel);
	return '' unless defined $chanrec;
	return $chanrec->{topic};
}

### Encode to UTF8. Params: $string, $charset
sub e2U {
	my ($string, $charset, @rest) = @_;
	return $string if !$charset || !$string;
	dd(__LINE__.": e2U charset: $charset string before: $string");
	Encode::from_to($string, $charset, 'utf8');
	dd(__LINE__.": e2U string after conversion to utf8: $string");
	return $string;
}

### Check if charset is utf8. if not, convert to utf8. Params: 1) String to convert 2) source charset.
sub checkAndEncode {
	my ($string, $charset, @rest) = @_;
	dd(__LINE__.": checkAndEncode, charset given: $charset, string given: $string");
	my $returnString = "";
	if ($charset !~ /utf-8/i && $charset !~ /utf8/i) {
		dd(__LINE__.": charset was not reported at utf8");
		if ($string =~ /Ã/) {
			dd(__LINE__.": most likely ISO CHARS INSTEAD OF UTF8, converting from ${charset}");
			$returnString = e2U($string, $charset);
		} elsif ($string =~ /[ÄäÖöÅå]/u) {
			dd(__LINE__.": UTF-8 CHARS FOUND, most likely NOT correct! (reported as ${charset})");
			$returnString = $string;
		} else {
			dd(__LINE__.": Didn't found any special characters. Converting..'");
			$returnString = e2U($string, $charset);
		}
	} elsif ($charset =~ /utf-8/i || $charset =~ /utf8/i) {
		dd(__LINE__.": charset was reported as utf8");
		if ($string =~ /Ã/) {
			dd(__LINE__.": ISO CHARS FOUND, INCORRECT! (reported as $charset)");
			$returnString = e2U($string, $charset) || "";		
		} elsif ($string =~ /[ÄäÖöÅå]/u) {
			dd(__LINE__.": UTF-8 CHARS FOUND, report was CORRECT! (reported as $charset)");
			$returnString = $string;
		} else {
			dd(__LINE__.": Didn't find any special characters. Not converting to utf8.");
			$returnString = $string;
		}
	}
	return $returnString;
}

### Check if title is allready found in URL. Params: $url, $title. Return 1/0
sub checkIfTitleInUrl {
	my ($url, $title, @rest) = @_;

	my ($samewords, $titlewordCount) = count_same_words($url, $title);
	dd(__LINE__.": checkIfTitleInUrl titlewordCount: $titlewordCount, samewords: $samewords");
	#dd(__LINE__.': checkIfTitleInUrl number1: '. ($samewords / $titlewordCount));
	dd(__LINE__.': checkIfTitleInUrl number2: '. (0.83 * $titlewordCount));

	#if ($samewords >= 4 && ( $titlewordCount / $samewords) > (0.83 * $titlewordCount)) {
	if ($samewords >= 4 && ($samewords) > (0.83 * $titlewordCount)) {
		dd(__LINE__.": checkIfTitleInUrl bling1!");
		return 1;
	} elsif ($samewords == $titlewordCount) {
		dd(__LINE__.": checkIfTitleInUrl bling2!");
		return 1;
	}
	dd(__LINE__.':checkIfTitleInUrl: title not found from url!');
	return 0;
}

## Count words from sentence after special chars are removed. Param: string
sub count_words {
	my ($row,@rest) = @_;
	my @array = split_row_to_array($row);
	#my $count = 0;
	#foreach my $val (@array) {
	#	$count++;
	#}
	return $#array +1;
}

sub count_same_words {
	my ($url, $title, @rest) = @_;
	dp(__LINE__.": count_same_words url: $url, title: $title");
	my @rows1 = split_row_to_array($url);	# url
	my @rows2 = split_row_to_array($title);	# title
	my $titlewordCount = $#rows2 + 1;
	my $count1 = 0;
	#dd(__LINE__.": count_same_words titlewordCount: $titlewordCount");
	foreach my $item (@rows2) {
		if ($item ~~ @rows1) {
		    #if (grep /^$item/, @rows1 ) {
			$count1++;
			dp(__LINE__.": count_same_words item found: $item, total count: $count1");
			#if ($count1 == $titlewordCount) {
			#	dd(__LINE__.": count_same_words: bingo!") if $DEBUG1;
			#	return $count1, $titlewordCount;
			#}
		} elsif (length $item > 1 && $url =~ /\Q$item\E/g) {
			$count1++;
			dp(__LINE__.": $item found from url.");
		}
        if ($count1 == $titlewordCount) {
	        dp(__LINE__.": count_same_words: bingo!");
    	    return $count1, $titlewordCount;
        }
	}
	#dd(__LINE__.": >   same words: $count1");
	return $count1, $titlewordCount;
}

# lowercase, remove weird chars. return formatted words
sub split_row_to_array {
	my ($row, @rest) = @_;

	$row = replace_non_url_chars($row);
	#$row =~ s/[^\w\s\-\.\/\+\#]//g;
	$row =~ s/\s+/ /g;
	#$row = KaaosRadioClass::ktrim($row);
	$row = lc($row);

	dd(__LINE__.": split_row_to_array after: $row") if $DEBUG1;
	my @returnArray = split(/[\s\&\|\+\-\–\–\_\.\/\=\?\#,]+/, $row);
	dd('split_row_to_array word count: ' . ($#returnArray+1)) if $DEBUG1;
	da(@returnArray) if $DEBUG1;
	return @returnArray;
}

sub replace_non_url_chars {
	my ($row, @rest) = @_;
	dd(__LINE__.": replace_non_url_chars row: $row");

	my $debugString = '';
	if ($DEBUG_decode == 1 && 1) {
		foreach my $char (split //, $row) {
			$debugString .= " " .ord($char) . Encode::encode_utf8(":$char");
		}
		dd(__LINE__.": replace_non_url_chars debugstring: ".$debugString);
	}

	$row =~ s/ä/a/ug;
	$row =~ s/Ä/a/ug;
	$row =~ s/ö/o/ug;
	$row =~ s/Ö/o/ug;
	$row =~ s/Ã¤/a/g;
	$row =~ s/Ã¶/o/g;

	$row =~ s/\(/ /g;
	$row =~ s/\)/ /g;
	$row =~ s/"/ /g;

	$row =~ s/ / /g;		# no-break space nbsp
	$row =~ s/\*//g;		# * char

	dd(__LINE__.": replace non url chars row after: $row");
	return $row;
}

sub shortenURL {
	my ($url, @rest) = @_;
	#dp(__LINE__.":shortenUrl: $url");
	return '';		# FIXME, not in use currently, causes timeouts
    my $ua2 = new LWP::UserAgent;
    $ua2->agent($useragentOld);
	$ua2->max_size(32768);
	$ua2->timeout(5);
    my $request = new HTTP::Request GET => "http://42.pl/url/?auto=1&url=$url";
	#my $request = new HTTP::Request GET => "http://42.pl/u/?auto=1&url=$url";
    my $s = $ua2->request($request);
    my $content = $s->content();
	if ($content =~ /RATE-LIMIT/s) { return '(error, rate-limit)'; }
	if ($content =~ /(http\:\/\/[^\s]+)/) {
		dp(__LINE__.": short: $1");
		return $1;
	} else {
		dp(__LINE__.":shortenURL url: http://42.pl/u/?auto=1&url=$url content: $content");
	}
	return '';
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
   		prindw("DBI Error> ". DBI::errstr);
	} else {
   		prind("Table $db created successfully");
	}
	$dbh->disconnect();
}

# Save to sqlite DB
sub saveToDB {
	my (@rest) = @_;
	my $pvm = time;
	#my @dontsave = split(/ /, Irssi::settings_get_str('urltitle_shorten_url_channels'));
    #return if $channel ~~ @dontsave;
    
	KaaosRadioClass::addLineToFile($logfile, $pvm.'; '.$newUrlData->{nick}.'; '.$newUrlData->{chan}.'; '.$newUrlData->{url}.'; '.$newUrlData->{title}.'; '.$newUrlData->{desc});
	
	dp(__LINE__.": saveToDB: $db, pvm: $pvm, nick: $newUrlData->{nick}, url: $newUrlData->{url}, title: $newUrlData->{title}, description: $newUrlData->{description}, channel: $newUrlData->{chan}, md5: $newUrlData->{md5}") if $DEBUG1;
	
	my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;
	my $sth = $dbh->prepare("INSERT INTO links VALUES(?,?,?,?,?,?,?)") or die DBI::errstr;
	$sth->bind_param(1, $newUrlData->{nick});
	$sth->bind_param(2, $pvm, { TYPE => SQL_INTEGER });
	$sth->bind_param(3, $newUrlData->{url});
	$sth->bind_param(4, $newUrlData->{title});
	$sth->bind_param(5, substr $newUrlData->{desc}, 0, 350);
	$sth->bind_param(6, $newUrlData->{chan});
	$sth->bind_param(7, $newUrlData->{md5});
	$sth->execute;
	$sth->finish();
	$dbh->disconnect();

	prind("URL from $newUrlData->{chan} saved to database.");
	clearUrlData();
	return;
}

# Check from DB if old entry is found
sub checkForPrevEntry {
	my ($url, $newchannel, $md5hex, @rest) = @_;
	dp(__LINE__.":checkForPrevEntry channel: $newchannel, url: $url, md5: $md5hex");
	my $dbh = DBI->connect("dbi:SQLite:dbname=$db", '', '', { RaiseError => 1 },) or die DBI::errstr;

	#my $sth = $dbh->prepare("SELECT * FROM LINKS WHERE (MD5HASH = ? or URL = ?) AND channel = ? order by rowid asc") or die DBI::errstr;
	#my $sth = $dbh->prepare("SELECT * FROM LINKS WHERE URL = ? AND channel = ?") or die DBI::errstr;
	my $sth = $dbh->prepare('SELECT * FROM LINKS WHERE MD5HASH = ? AND channel = ? order by rowid asc') or die DBI::errstr;

	$sth->bind_param(1, $md5hex);
	#$sth->bind_param(2, $url);
	$sth->bind_param(2, $newchannel);

	$sth->execute();

	# build elements into array
	my @elements;
	my @row = ();

	while (@row = $sth->fetchrow_array()) {
		push @elements, [@row];
	}

	$sth->finish();
	$dbh->disconnect();
	my $count = @elements;
	dp(__LINE__.": $count previous elements found!") if $DEBUG1;
	return @elements;		# return all rows
	#return $elements[0];	# return first row
}

sub api_conversion {
	my ($param, $server, $target, @rest) = @_;
	#https://www.youtube.com/shorts/apSq3ZC3Sc8
	if ($param =~ /youtube\.com\/.*[\?\&]v=([^\&]*)/ || 
		$param =~ /youtu\.be\/([^\?\&]*)\b/ || 
		#$param =~ /invidious*\/.*[\?\&]v=([^\&]*)/ || 
		#$param =~ /invidious.*\/.*[\?\&]v=([^\&]*)/ ||
		$param =~ /watch\?v=([^\&]*)/ ||
		$param =~ /youtube\.com\/shorts\/([^\?\&]*)/
	) {
		dp(__LINE__ . ' youtube url found! id: ' . $1);
		# youtube api
		my $videoid = $1;
		
		my $apiurl = "https://www.googleapis.com/youtube/v3/videos?part=snippet%2CcontentDetails%2Cstatistics&id=".$videoid."&key=".$apikey;
		my $ytubeapidata_json = KaaosRadioClass::getJSON($apiurl);
		if ($ytubeapidata_json eq '-1' || $ytubeapidata_json eq '-2') {
			dp(__LINE__ . ' youtube api failed!');
			return 0;
		}
		#dp(__LINE__ . ' going strong');
		#da($ytubeapidata_json->{items});
		my $len = scalar $ytubeapidata_json->{items};
		if (not defined $ytubeapidata_json->{items}[0]) {
			dp(__LINE__ . ' video not found from API...');
			$newUrlData->{title} = "Video not found from API...";
			return 1;
		}
		
		my $likes = '👍'.$ytubeapidata_json->{items}[0]->{statistics}->{likeCount};
		my $commentcount = $ytubeapidata_json->{items}[0]->{statistics}->{commentCount};
		my $title = $ytubeapidata_json->{items}[0]->{snippet}->{title};
		my $description = $ytubeapidata_json->{items}[0]->{snippet}->{description};
		my $chantitle = $ytubeapidata_json->{items}[0]->{snippet}->{channelTitle};
		my $published = $ytubeapidata_json->{items}[0]->{snippet}->{publishedAt};
		$published = format_time($published);
		$newUrlData->{title} = "\0030,5 ▶ \003 " . $title .' ['.$chantitle.', '.$published.', '.$likes . ']';
		$newUrlData->{desc} = $description;
		dp(__LINE__ . ' video found from API... title: ' . $newUrlData->{title});
		return 1;
	}

	# TODO: imgur API-conversion
	if ($param =~ /\:\/\/imgur\.com\/gallery\/([\d\w\W]{2,8})/) {
		my $image = $1;
		prind("imgur-klick! img: $image");
	}

	# google drive
	if ($param =~ /\:\/\/drive\.google\.com\/file\/d\/([a-zA-Z0-9_-]*)/) {
		# gdrive api
		my $fileid = $1;
		my $apiurl = "https://www.googleapis.com/drive/v3/files/".$fileid."?key=".$apikey;
		prind("gdrive api! fileid: $fileid, apiurl: $apiurl");
		my $gdriveapidata_json = KaaosRadioClass::getJSON($apiurl);
		#dp($gdriveapidata_json);
		if ($gdriveapidata_json eq '-1') {
			print "FAK!";
			return 0;
		}
		da($gdriveapidata_json) if $DEBUG1;
		$newUrlData->{title} = 'Mimetype: '.$gdriveapidata_json->{mimeType}.', name: '.$gdriveapidata_json->{name};
		$newUrlData->{desc} = '';
		return 1;
	}

	# instagram API
	if ($param =~ /www.eitoimi.instagram.com/) {
		# instagram conversion, example: https://api.instagram.com/oembed/?url=https://www.instagram.com/p/CFKNRqNhW32/
		prind('Instagram url detected!');
		my $instapiurl = 'https://api.instagram.com/instagram_oembed/?url=' . $param;
		dp('instapi url:'.$instapiurl);
		my $instajson = KaaosRadioClass::getJSON($instapiurl);
		if ($instajson eq '-1') {
			print "FUUK!";
			return 0;
		}
		dp($instajson->{title});
		$newUrlData->{title} = KaaosRadioClass::ktrim($instajson->{title} . ' ['. $instajson->{author_name}.']');
		return 1;
	}
	return 0;
}

sub signal_emitters {
	my ($param, $server, $target, @rest) = @_;
	return 0 if $dontprint == 1;

	if ($param =~ /twitter.com(.*)\/status\/(.*)/i ||
		$param =~ /x.com(.*)\/status\/(.*)/i || 
		$param =~ /fixupx.com(.*)\/status\/(.*)/i) {
		# twitter status
		Irssi::signal_emit('twitter_search_id', $server, $target, $2);
		prind("Twitter signal emited!! $2");
		# Irssi::signal_stop();
		return 1;
	}
	if ($param =~ /imdb\.com\/title\/(tt[\d]+)/i) {
		# sample: https://www.imdb.com/title/tt2562232/
		Irssi::signal_emit('imdb_search_id', $server, 'tt-search', $target, $1);
		prind("IMDB signal emited!! $1");
		# Irssi::signal_stop();
		return 1;
	}

	# taivaanvahti id
	if ($param =~ /www.taivaanvahti.fi\/observations\/show\/(\d+)/gi) {
		Irssi::signal_emit('taivaanvahti_search_id', $server, 'HAVAINTOID', $target, $1);
		prind("Taivaanvahti signal emited!! $1");
		# Irssi::signal_stop();
		return 1;

	} elsif ($param =~ /(https?.*areena\.yle\.fi.*)/) {
		Irssi::signal_emit('yle_url', $server, $target, $1);
		prind("Yle_url signal emited!! $1");
		return 1;
	}
	return 0;	# not emitting signal
}

sub url_conversion {
	my ($param, $server, $target, @rest) = @_;
	dp(__LINE__.": url_conversion, param: $param") if $DEBUG1;
	
	# soundcloud conversion, example: https://soundcloud.com/oembed?url=https://soundcloud.com/shatterling/shatterling-different-meanings-preview
	$param =~ s/\:\/\/soundcloud.com/\:\/\/soundcloud.com\/oembed\?url\=http\:\/\/soundcloud\.com/;

	# kuvaton conversion
	$param =~ s/\:\/\/kuvaton\.com\/browse\/[\d]{1,6}/\:\/\/kuvaton.com\/kuvei/;

	# set more recent request headers if mixcloud or other known website
	if ($param =~ /mixcloud\.com/i || $param =~ /k-ruoka\.fi/i || $param =~ /drive\.google\.com/i) {
		set_useragent(2);
	}

	if ($param =~ /youtube\.com/i || $param =~ /youtu\.be/i || $param =~ /maps\.google\.com/i || 
		$param =~ /google\.com\/maps/i || $param =~ /watch\?v=/) {
		dp(__LINE__.": google service detected!");
		set_useragent(3);
		if ($param =~ /youtube\.com(.*)/i || $param =~ /(\/watch\?v=.*)/i) {
			dp(__LINE__ . ": youtube.com detected!");
			if (length $1 > 0) {
				my $newurl = $invidiousUrl . $1;
				#my $newurl = 'https://invidious.protokolla.fi' . $1;
				#my $newurl = 'https://invidious.private.coffee' . $1;
				$newUrlData->{extra} = " -- proxy: $newurl";
			}
		} elsif ($param =~ /youtu\.be\/(.*)/i) {
			if (length $1 > 0) {
				my $newurl = $invidiousUrl . '/watch?v=' . $1;
				#my $newurl = 'https://invidious.protokolla.fi/watch?v=' . $1;
				#my $newurl = 'https://invidious.private.coffee/watch?v=' . $1;
				$newUrlData->{extra} = " -- proxy: $newurl";
			}
		}
	}

	# spotify conversion
	if ($param =~ /spotify\.com/i) {
		$param =~ s/\:\/\/play\.spotify\.com/\:\/\/open\.spotify\.com/;
		set_useragent(3);
	}

	if ($param =~ /twitter\.com/i) {
		# TODO: test mobile m.twitter.com
		# nitter instances: https://github.com/zedeus/nitter/wiki/Instances
		$param =~ s/https\:\/\/twitter\.com/$twitterurl/i;
		# nitter.42l.fr nitter.pussthecat.org nitter.eu nitter.net nitter.dark.fail nitter.cattube.org nitter.actionsack.com
		# nitter.mailstation.de nitter.namazso.eu nitter.himiko.cloud nitter.domain.glass nitter.unixfox.eu
		$newUrlData->{extra} = " -- proxy: $param";
	}

	if ($param =~ /yle\.fi/i) {
		# add header x-forwarded-for to circumvent geo-blocking
		# print($IRSSI{'name'}.'> yle.fi detected!');
		# does not seem to work yet.. add_header('X-Forwarded-For', '54.192.99.2');
	}

	if ($param =~ /eitoimi.instagram\.com/i) {
		$param =~ s/https\:\/\/(www\.)?instagram.com/$instaurl/i;
		$newUrlData->{extra} = " -- proxy: $param";
	}

	if ($param =~ /imgur\.com\/(.*)/i) {
		
		my $proxyurl = $param;
		$proxyurl =~ s/i\.imgur\.com/$imgurUrl/i;
		$proxyurl =~ s/imgur\.com/$imgurUrl/i;
		$newUrlData->{extra} = " -- proxy: $proxyurl";
		dp(__LINE__.": imgur.com detected! proxyurl: $proxyurl");
		# needed for now:
		$param =~ s/i\.imgur\.com/$imgurUrl/i;
		$param =~ s/imgur\.com/$imgurUrl/i;

		#if ($param =~ /i\.imgur\.com/i) {
			# if direct link to a image/video, must use proxy
		#	$param =~ s/i\.imgur\.com/$imgurUrl/i;
		#}
		
	}

	if ($param =~ /reddit\.com/i) {
		$param =~ s/reddit\.com/$redditUrl/i;
		$newUrlData->{extra} = " -- proxy: $param";
		dp(__LINE__ . " reddit url detected! proxyurl: $param")
	}

	if ($param =~ /hs.fi/i) {
		my $proxyurl = $hsUrl. $param;
		$newUrlData->{extra} = " -- proxy: $proxyurl";
	}

	return $param;
}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
    my $mynick = quotemeta $server->{nick};
	return if ($nick eq $mynick);   #self-test
	return if ($nick eq 'kaaosradio');
	#return if ($nick eq 'mx');
	#return if ($nick eq 'k-disco' || $nick eq 'kd' || $nick eq 'kd2');

	$dontprint = 0;
	# TODO if searching for old link..
	if ($msg =~ /\!url (.*)$/i) {
		return if KaaosRadioClass::floodCheck() > 0;
		my $searchWord = $1;
		my $sayline = findUrl($searchWord);
		dp(__LINE__.": sig_msg_pub: Shortening sayline a bit...") if ($sayline =~ s/(.{260})(.*)/$1 .../);
	
		msg_to_channel($server, $target, $sayline);
		#clearUrlData();
		return;
	}

	# ttp://
	if ($msg =~ /h?(ttps?:\/\/\S+)/i) {
		$newUrlData->{url} = "h${1}";
	} elsif ($msg =~ /(www\.\S+)/i) {
		$newUrlData->{url} = "http://$1";
	} else {
		return;
	}
	
	# check if flooding too fast
	if (KaaosRadioClass::floodCheck() > 0) {
		clearUrlData();
		return;
	}
	set_useragent(1);			# set default user agent
	$newUrlData->{url} = url_conversion($newUrlData->{url});
	$newUrlData->{fetchurl} = $newUrlData->{url};	# this variable will be the url that will be executed
	$newUrlData->{nick} = $nick;
	$newUrlData->{chan} = $target;
	
	# check if flooding too many times in a row
	my $isDrunk = KaaosRadioClass::Drunk($nick);

	# check if sombody playing (now playing) in radio
	if ($target =~ /kaaosradio/i || $target =~ /salamolo/i) {
		if (get_channel_topic($server, $target) =~ /npv?\:/i) {
			# disabled 2023-11-01 $dontprint = 1;
			$dontprint = 0;
		}
	}
	my $title = '';			# url title to print to channel
	my $description = '';	# url description to print to channel
	my $isTitleInUrl = 0;	# title or file
	my $md5hex = '';		# MD5 of requested page

	# if we want to censor
	if (dontPrintThese($newUrlData->{url}) == 1) {
		($newUrlData->{title}, $newUrlData->{desc}, $isTitleInUrl, $newUrlData->{md5}) = ($newUrlData->{fetchurl});
		saveToDB();
		return;
	}
	my @short_raw = split / /, Irssi::settings_get_str('urltitle_shorten_url_channels');
	if ($target ~~ @short_raw) {
		$shorturlEnabled = 1;
		dp(__LINE__.': shorten url enabled!');
	} else {
		$shorturlEnabled = 0;
	}

	#$newUrlData->{fetchurl} =  ($newUrlData->{url}, $server, $target);
	
	return if signal_emitters($newUrlData->{fetchurl}, $server, $target);

	if (api_conversion($newUrlData->{fetchurl})) {
	} else {
		($newUrlData->{title}, $newUrlData->{desc}, $isTitleInUrl, $newUrlData->{md5}) = fetch_title($newUrlData->{fetchurl}, 'GET');
		dp(__LINE__. ' Response code: ' . $newUrlData->{responsecode} . ', fetchURl: ' . $newUrlData->{fetchurl});
		if ($newUrlData->{responsecode} ne '') {
			msg_to_channel($server, $target, 'Error: ' . $newUrlData->{responsecode});
			clearUrlData();
			return;
		}
	}
	
	my $newtitle = '';
	$newtitle = $newUrlData->{title} if $newUrlData->{title};
	dp(__LINE__ . ' newtitle: ' . $newtitle);
	# if exact page was sent before on the same chan
	my $oldOrNot = checkIfOld($server, $newUrlData->{url}, $newUrlData->{chan}, $newUrlData->{md5});

	# shorten output message
	prind("Shortening url info a bit...") if ($newtitle =~ s/(.{260})(.*)/$1.../);
	dp(__LINE__.": NOT JEE") if ($newtitle eq "0");
	$title = $newtitle;
	
	# if description would suit better than title, use description instead
	if ($newUrlData->{desc} && $newUrlData->{desc} ne '' && $newUrlData->{desc} ne '0' && length($newUrlData->{desc}) > length($newUrlData->{title})) {
		$title = 'Desc: '.$newUrlData->{desc} unless noDescForThese($newUrlData->{url});
	}

	# if original url longer than 70 characters, do "shorturl"
	if ($shortModeEnabled == 0 && length $newUrlData->{url} >= 70) {
		$newUrlData->{shorturl} = shortenURL($newUrlData->{url});
		$title .= " -> $newUrlData->{shorturl}" if ($newUrlData->{shorturl} ne '');
	}

	# imgur stuff
	$title .= $newUrlData->{extra};
	# increase $howDrunk if necessary
	if ($dontprint == 0 && $isTitleInUrl == 0 && $title ne '') {
		if ($isDrunk && $howDrunk < 1) {
			msg_to_channel($server, $target, 'tl;dr');
			$howDrunk++;
		} elsif ($isDrunk == 0 && $title ne '') {
			dp(__LINE__ . ' congrts, title found!, title: ' . $title);
			msg_to_channel($server, $target, $title);
			$howDrunk = 0;
		}
	}

	# save links from every channel
	saveToDB();
	return;
}

sub msg_to_channel {
	my ($server, $target, $title, @rest) = @_;
	if ($dontprint == 1) {return;}
	my $enabled_raw = Irssi::settings_get_str('urltitle_enabled_channels');
	my @enabled = split / /, $enabled_raw;

	if ($title =~ /(.{260}).*$/s) {
		$title = $1 . '...';
	}
	$server->command("msg -channel $target $title") if grep /$target/i, @enabled;	# poor mans check
	return;
}

# wanha
sub checkIfOld {
	my ($server, $url, $target, $md5hex) = @_;
	my $wanhadisabled = Irssi::settings_get_str('urltitle_wanha_disabled');
	if ($wanhadisabled == 1) {
		return 0;
	}
	my @wanha_raw = split / /, Irssi::settings_get_str('urltitle_wanha_channels');
	if ($target ~~ @wanha_raw) {
	} else {
		return 0;
	}

	my @prevUrls = checkForPrevEntry($url, $target, $md5hex);
	my $count = @prevUrls;
	dp(__LINE__.":checkIfOld count: $count, howDrunk: $howDrunk");
	if ($count != 0 && $howDrunk == 0) {
		my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime $prevUrls[0][1];
		$year += 1900;
		$mon += 1;
		msg_to_channel($server, $target, "w! ($prevUrls[0][0] @ $mday.$mon.$year ". sprintf("%02d", $hour).":".sprintf("%02d", $min).":".sprintf("%02d", $sec)." ($count)");
		dp(__LINE__.": w! ($prevUrls[0][0] @ $mday.$mon.$year ". sprintf("%02d", $hour).":".sprintf("%02d", $min).":".sprintf("%02d", $sec)." ($count)");
		return 1;
	}
	return 0;
}

# find with keywords comma-separated list
sub find_keywords {
	my ($keywords, @rest) = @_;
	prind("find_keywords request: $keywords");
	my $returnString;
	my @words = split /, ?/, $keywords;
	my $search_sql = 'SELECT rowid,* from links where ';
	my $counter = 0;
	foreach my $searchword (@words) {
		if ($counter > 0) {
			$search_sql += ' or ';
		}
		$search_sql += "(URL like ? or TITLE like ? or DESCRIPTION like ?)";
	}
}

# find URL from database
sub findUrl {
	my ($searchword, @rest) = @_;
	prind("etsi request: $searchword");
	dp(__LINE__.":findUrl") if $DEBUG1;
	my $returnstring;
	if ($searchword =~ s/^id:? ?//i) {
		my @results;
		if ($searchword =~ /(\d+)/) {
			$searchword = $1;
			@results = searchIDfromDB($searchword);
		} else {
			@results = searchDB($searchword);
		}
		return createAnswerFromResults(@results);
	} elsif ($searchword =~ s/^kaikki:? ?//i || $searchword =~ s/^all:? ?//i) {
		# print all found entries
		my @results = searchDB($searchword);
		$returnstring .= 'Loton oikeat numerot: ';
		my $in = 0;
		foreach my $line (@results) {
			# TODO: Limit to 3-5 results
			#$returnstring .= createAnswerFromResults(@$line)
			$returnstring .= createShortAnswerFromResults(@$line) .', ';
			$in++;
		}
	} else {
		# print 1st found item
		my @results = searchDB($searchword);
		my $amount = @results;
		if ($amount > 1) {
			$returnstring = "Löytyi $amount, ID: ";
			my $i = 0;
			foreach my $id (@results) {
				$returnstring .= $results[$i][0].", ";	# collect ID's from results
				$i++;
				last if ($i > 13);						# max 13 items..
			}
		} elsif ($amount == 1) {
			$returnstring .= 'Löytyi 1, ';
			$returnstring .= "ID: $results[0][0], ";
			$returnstring .= "url: $results[0][3], ";
			$returnstring .= "title: $results[0][4], ";
			$returnstring .= "desc: $results[0][5]";
		} elsif ($amount < 1) {
			$returnstring = 'Ei tuloksia.';
		}
	}
	return $returnstring;
}

# TODO: limit number of search results
sub searchDB {
	my ($searchWord, @rest) = @_;
	dp(__LINE__.":searchDB: $searchWord");
	my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;
	my $sqlString = 'SELECT rowid,* from LINKS where rowid = ? or URL like ? or TITLE like ? or description LIKE ? ORDER BY rowid desc';
	my $sth = $dbh->prepare($sqlString) or die DBI::errstr;
	$sth->bind_param(1, "%$searchWord%");
	$sth->bind_param(2, "%$searchWord%");
	$sth->bind_param(3, "%$searchWord%");
	$sth->bind_param(4, "%$searchWord%");
	$sth->execute();
	my @resultarray = ();
	my @line = ();
	my $index = 0;
	while(@line = $sth->fetchrow_array) {
		push @{ $resultarray[$index]}, @line;
		$index++;
	}
	return @resultarray;
}

# search rowid = url ID from database
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
	return @result;
}

sub count_db {
	my $sql = 'SELECT COUNT(*) from links';
	my $dbh = KaaosRadioClass::connectSqlite($db);
	return KaaosRadioClass::closeDB($dbh);
}

# param: resultset (line) from DB.
sub createShortAnswerFromResults {
	my @resultarray = @_;
	my $amount = @resultarray;
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
		prind("Found: id: $rowid, nick: $nick, when: $when, title: $title, description: $desc, channel: $channel, url: $url");
	}

	return $returnstring;

}

# Create one line from one resultset (from DB)!
sub createAnswerFromResults {
	my @resultarray = @_;

	my $amount = @resultarray;
	if ($amount == 0) {
		return "Ei tuloksia.";
	}

	my $returnstring = '';
	my $rowid = $resultarray[0];
	$returnstring = "ID: $rowid, ";
	my $nick = $resultarray[1];					# who added
	my $when = $resultarray[2];					# when added
	my $url = $resultarray[3];					# url
	$returnstring .= "url: $url, ";
	my $title = $resultarray[4];
	$returnstring .= "title: $title, ";

	my $desc = $resultarray[5];
	$returnstring .= "desc: $desc, ";
	my $channel = $resultarray[6];
	my $md5hash = $resultarray[7];

	if ($rowid) {
		prind("Found: id: $rowid, nick: $nick, when: $when, title: $title, description: $desc, channel: $channel, url: $url, md5: $md5hash");
		prind("return string: $returnstring");
	}

	return $returnstring;
}

# Dont spam these domains.
sub dontPrintThese {
	my ($url, @rest) = @_;
	#return 1 if $url =~ /aamulehti\.fi/i;
	#return 1 if $text =~ /kuvaton\.com/i;
	#return 1 if $text =~ /explosm\.net/i;
	return 1 if $url =~ /apina\.biz/i;
	return 1 if $url =~ /ircz\.de/i;
	return 1 if $url =~ /explosm\.net\/comics/i;
	return 0;
}

# sites that report utf8 encoding falsely
sub falseUtf8Pages {
	my ($text, @rest) = @_;
	return 1 if $text =~ /iltalehti\.fi/i;
	return 1 if $text =~ /puhelinvertailu\.com/i;	# 19.7.2021
	#return 1 if $text =~ /lidl\.fi/i;
	
	return 0;
}

# we dont want to show description for these
sub noDescForThese {
	my ($url, @rest) = @_;
	return 1 if $url =~ /youtube\.com/i;
	return 1 if $url =~ /invidious/i;
	return 1 if $url =~ /youtu\.be/i;
	return 1 if $url =~ /imdb\.com/i;
	return 1 if $url =~ /dropbox\.com/i;
	return 1 if $url =~ /mixcloud\.com/i;
	return 1 if $url =~ /flightradar24\.com/i;
	return 1 if $url =~ /github\.com/i;
	return 1 if $url =~ /gurushots\.com/i;
	return 1 if $url =~ /streamable\.com/i;
	return 1 if $url =~ /imgur\.com\/gallery/i;
	return 1 if $url =~ /watch\?v=/i;
	#return 1 if $url =~ /bandcamp\.com/i;

	return 0;
}

sub clearUrlData {
	$newUrlData->{nick} = '';		# nick
	$newUrlData->{date} = 0;		# date
	$newUrlData->{url} = '';		# url
	$newUrlData->{title} = '';		# title
	$newUrlData->{desc} = '';		# desc
	$newUrlData->{chan} = '';		# channel
	$newUrlData->{md5} = '';		# md5hash
	$newUrlData->{fetchurl} = '';	# url to fetch
	$newUrlData->{shorturl} = '';	# short url
	$newUrlData->{responsecode} = '';	# response code if error
	$newUrlData->{extra} = '';
	#KaaosRadioClass::floodCheck();	# write current timestamp to flood file
}


# debug print
sub dp {
	my ($string, @rest) = @_;
	if ($DEBUG == 1) {
		print($IRSSI{name}." debug> ".$string);
	}
}

# debug decode messages
sub dd {
	my ($string, @rest) = @_;
	if ($DEBUG_decode == 1) {
		print($IRSSI{name}." debugdecode> ".$string);
	}
}

# debug print array
sub da {
	print($IRSSI{name}." debugarray> ");
	print(Dumper(@_)) if ($DEBUG == 1 || $DEBUG_decode == 1);
}

sub sig_msg_pub_own {
	my ($server, $msg, $target) = @_;
	dp(__LINE__.':own public');
	sig_msg_pub($server, $msg, $server->{nick}, '', $target);
}

sub prind {
	my ($text, @test) = @_;
	print("\0038" . $IRSSI{name} . ">\003 ". $text);
}
sub prindw {
	my ($text, @test) = @_;
	print("\0034" . $IRSSI{name} . " warning>\003 ". $text);
}

Irssi::settings_add_str('urltitle', 'urltitle_enabled_channels', '');
Irssi::settings_add_str('urltitle', 'urltitle_wanha_channels', '');
Irssi::settings_add_str('urltitle', 'urltitle_wanha_disabled', '0');
Irssi::settings_add_str('urltitle', 'urltitle_shorten_url_channels', '');
Irssi::settings_add_str('urltitle', 'urltitle_dont_save_urls_channels', '');
#Irssi::settings_add_str('urltitle', 'urltitle_enable_descriptions', '0');

# to change signal params, restart irssi
my $signal_config_hash = { 'taivaanvahti_search_id' => [ qw/iobject string string string/ ] };
Irssi::signal_register($signal_config_hash);

my $signal_config_hash2 = { 'imdb_search_id' => [ qw/iobject string string string/ ] };
Irssi::signal_register($signal_config_hash2);

my $signal_config_hash3 = { 'yle_url' => [ qw/iobject string string/ ] };
Irssi::signal_register($signal_config_hash3);

my $signal_config_hash4 = { 'twitter_search_id' => [ qw/iobject string string/ ] };
Irssi::signal_register($signal_config_hash4);

Irssi::signal_add('message public', 'sig_msg_pub');
#Irssi::signal_add('message own_public', 'sig_msg_pub_own');
prind("v. $VERSION loaded.");
prind("New commands:");
prind('/set urltitle_enabled_channels #channel1 #channel2');
prind('/set urltitle_wanha_channels #channel1 #channel2');
prind('/set urltitle_wanha_disabled 0/1');
prind('/set urltitle_dont_save_urls_channels #channel1 #channel2');
prind('/set urltitle_shorten_url_channels #channel1 #channel2');
#prind('/set urltitle_enable_descriptions 0/1.');
prind('Urltitle enabled channels: '. Irssi::settings_get_str('urltitle_enabled_channels'));
