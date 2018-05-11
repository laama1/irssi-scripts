use warnings;
use strict;
use Irssi;
#use LWP::UserAgent;
#use HTTP::Cookies;
#use Time::HiRes qw(time);
#use HTML::Entities qw(decode_entities);
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

#use Digest::MD5 qw(md5_hex);		# LAama1 28.4.2017
#use Encode qw(encode_utf8);
use Encode;

#use lib '/home/laama/Mount/kiva/.irssi/scripts';
#use lib '/usr/lib64/perl5/vendor_perl/';
use KaaosRadioClass;				# LAama1 13.11.2016

use vars qw($VERSION %IRSSI);
$VERSION = "20190424";
%IRSSI = (
	authors     => "LAama1",
	contact     => "LAama1",
	name        => "weathers",
	description => "Fetches weather data from DB.",
	license     => "Fublic Domain",
	url         => "http://kaaosradio.fi",
	changed     => $VERSION
);

my $tsfile = Irssi::get_irssi_dir()."/scripts/ts";
#my $logfile = Irssi::get_irssi_dir()."/scripts/urllog_v2.txt";
#my $cookie_file = Irssi::get_irssi_dir() . '/scripts/urltitle3_cookies.dat';
my $db = "/home/laama/scripts/weathers.db";
#my $debugfile = Irssi::get_irssi_dir()."/scripts/urlurldebug.txt";

my $howManyDrunk = 0;

my $DEBUG = 0;
my $DEBUG1 = 0;
my $DEBUG_decode = 1;
my $myname = "weathers.pl";

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

unless (-e $db) {
	unless(open FILE, '>:utf8',$db) {
		Irssi::print("$myname: Unable to create or write file: $db");
		die;
	}
	close FILE;
	#createDB();
	#createFstDB();
	#Irssi::print("$myname: Database file created.");
}

	
	return $titteli, $description, $titleInUrl, $md5hex;
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
		if ($DEBUG1) { Irssi::print("weathers3-debug: nick: $nick, pvm: $pvm, url: $url, channel: $channel"); }
	}
	$sth->finish();
	$dbh->disconnect();
	my $count = @elements;
	dp("$count elements found!") if $DEBUG1;
	if ($count == 0)	{ return; }
	else { return @elements };
}

# wanha
sub checkIfOld {
	my ($server, $url, $target, $md5hex) = @_;
	my $wanhadisabled = Irssi::settings_get_str('weathers_wanha_disabled');
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

sub findWeather {
	my ($searchword, @rest) = @_;
	Irssi::print("$myname: etsi request: $searchword");
	my $searchtime = time() - (2*60*60);
	dp("findWeather") if $DEBUG1;
	my $returnstring;
	my $temp = "";

	my $sql = "SELECT * from weathers where city like '%$city%' and pvm >= $searchtime";
	



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
		my $in = 0;
		foreach my $line (@results) {
			# TODO: Limit to 3-5 results
			#$returnstring .= createAnswerFromResults(@$line)
			$returnstring .= createShortAnswerFromResults(@$line) .", ";
			$in++;
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
				last if ($i > 13);						# max 13 items..
			}
		} elsif ($amount == 1) {
			$returnstring .= "Löytyi 1, ";
			$returnstring .= "ID: $results[0][0], ";
			$returnstring .= "url: $results[0][3], ";
			$returnstring .= "title: $results[0][4], ";
			$returnstring .= "desc: $results[0][5]";
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
	my $md5hash = $resultarray[7];
	#my $md5hash = "";
	#my $deleted = $resultarray[8] || "";
	
	#if ($nick ne "") { $string .= "nick: $nick"; }

	if ($rowid) {
		Irssi::print("$myname: Found: id: $rowid, nick: $nick, when: $when, title: $title, description: $desc, channel: $channel, url: $url, md5: $md5hash");
		Irssi::print("$myname: return string: $returnstring");
	}

	dp("string: $returnstring");
	#dp($string);
	return $returnstring;

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


sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	return if ($nick eq $server->{nick});   # self-test
	
	# Check we have an enabled channel
	my $enabled_raw = Irssi::settings_get_str('weathers_enabled_channels');
	my @enabled = split(/ /, $enabled_raw);

	if ($msg =~ /\!(sää|saa) (.*)$/i) {
		return if KaaosRadioClass::floodCheck() > 0;
		my $searchWord = $1;
		my $city = $2;
		my $sayline = findWeather($city);
		dp("sig_msg_pub: found some results from '$city' on channel '$target'. '$sayline'");
		$server->command("msg -channel $target $sayline") if grep(/$target/, @enabled);
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
	my @short_raw = split(/ /, Irssi::settings_get_str('weathers_shortmode_channels'));
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


sub sig_msg_pub_own {
	my ($server, $msg, $target) = @_;
	dp("own public");
	sig_msg_pub($server, $msg, $server->{nick}, "", $target);
}

Irssi::settings_add_str('weathers', 'weathers_enabled_channels', '');
Irssi::settings_add_str('weathers', 'weathers_wanha_disabled', '0');
Irssi::settings_add_str('weathers', 'weathers_shortmode_channels', '');
Irssi::settings_add_str('weathers', 'weathers_dont_save_urls_channels', '');
Irssi::settings_add_str('weathers', 'weathers_enable_descriptions', '0');

Irssi::signal_add('message public', 'sig_msg_pub');
#Irssi::signal_add('message own_public', 'sig_msg_pub_own');
Irssi::print("$myname v. $VERSION loaded.");
Irssi::print("\nNew commands:");
Irssi::print('/set weathers_enabled_channels #1 #2');
Irssi::print('/set weathers_wanha_disabled 0/1');
Irssi::print('/set weathers_dont_save_urls_channels #1 #2');
Irssi::print('/set weathers_shortmode_channels #1 #2');
Irssi::print('/set weathers_enable_descriptions 0/1.');
