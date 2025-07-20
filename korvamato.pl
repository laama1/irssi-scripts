use Irssi;
use warnings;
use strict;
use utf8;
binmode(STDOUT, ':utf8');
binmode(STDIN, ':utf8');
#use open ':std', ':encoding(UTF-8)';
#use Irssi::Irc;
use DBI;
use DBI qw(:sql_types);
use Encode;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;		# LAama1 30.12.2016
use Data::Dumper;


use vars qw($VERSION %IRSSI);
$VERSION = '20200818';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'korvamato.pl',
	description => 'Lisää ja etsii korvamatoja.',
	license     => 'Public Domain',
	url         => '#kaaosradio',
	changed     => $VERSION,
);


#my $tiedosto = $ENV{HOME}.'/public_html/korvamadot.txt';
my $db = Irssi::get_irssi_dir(). '/scripts/korvamadot.db';
my @channels = ('#salamolo2', '#kaaosradio');
my $myname = 'korvamato.pl';
my $DEBUG = 0;
my $DEBUG1 = 0;

#my $helptext = 'Lisää korvamato: !korvamato: <tähän korvamatosanotukset>. Muokkaa korvamatoa: !korvamato id # <del> <lyrics:|artist:|title:|url:|link2:|info1:|info2:> <lisättävä tieto>. Etsi korvamato: !korvamato etsi: <hakusana tähän>. !korvamato id #.';
my $helptext = 'Korvamato help: https://bot.8-b.fi/#korvamato';

unless (-e $db) {
	unless(open FILE, '>:utf8'.$db) {
		prindw("Unable to create database file: $db");
		die;
	}
	close FILE;
	CREATEDB();
	prind("Database file created.");
} else {
	prind("Database file found!");
}

sub print_help {
	my ($server, $target) = @_;
	sayit($server, $target, $helptext);
	sayit($server, $target, get_statistics());
	return;
}

sub msgit {
	my ($server, $nick, $text, @rest) = @_;
	$server->command("msg $nick $text");
	return;
}

sub get_statistics {
	my $query = 'SELECT count(*) from korvamadot where DELETED = 0';
	my @result = KaaosRadioClass::readLineFromDataBase($db, $query);
	dp(__LINE__.':Results:');
	da(@result);
	if (@result > 0) {
		return "Minulla on $result[0] korvamatoa päässäni.";
	} else {
		return 'Ei vielä korvamatoja päässä.';
	}
}

# Say it public to a channel. Params: $server, $target, $saywhat
sub sayit {
	my ($server, $target, $saywhat) = @_;
	$server->command("MSG $target $saywhat");
	return;
}

sub find_mato {
	my ($searchword, @rest) = @_;
	prind("etsi request: {$searchword}.");
	my $returnstring = '';
	if ($searchword =~ s/kaikki: //gi || $searchword =~ s/all: //gi) {
		dp(__LINE__.': find_mato 1');
		# print all found entries
		my @results = search_from_db($searchword);
		$returnstring .= 'Loton oikeat numerot: ';
		foreach my $line (@results) {
			# TODO: Limit to 3-5 results
			$returnstring .= createAnswerFromResultsor(@$line)
		}
	} else {
		# print 1st found item
		my @results = search_from_db($searchword);
		my $amount = @results;
		dp(__LINE__.': find_mato 2') if $DEBUG1;
		da(@results) if $DEBUG1;

		if ($amount > 1) {
			$returnstring = "Löytyi $amount, ID: ";
			my $i = 0;
			foreach my $result_element (@results) {
				$returnstring .= $results[$i][0].', ';
				$i++;
				if ($i > 10) {
					$returnstring .= '...';
					last;
				}
			}
		} else {
			$returnstring = "Löytyi $amount: ";
			$returnstring .= createAnswerFromResultsor(@{$results[0]});
		}
	}
	dp(__LINE__.":         #### returrrrrrrn : $returnstring");
	return $returnstring;
}

# search URL from DB if URL found from word and return count..
sub IFURL {
	my ($word, @rest) = @_;
	my $url = '';
	my $urlsfound = 0;
	if ($word =~ /(https?\:\/\/[\S]*)\s/gi) {
		$url = $1;
		dp(__LINE__.": $myname debug IFURL: $url");
		my @results = search_url_from_db($url);
		$urlsfound = @results;					# count, how many
	}
	return $urlsfound;
}

# delete korvamato or one info
sub del_mato {
	my ($searchword, $id, @rest) = @_;
	my $string;
	dp(__LINE__.": del_mato searchword: $searchword");
	if ($searchword =~ /link1/gi || $searchword =~ /url/gi) {
		$string = "UPDATE korvamadot set LINK1 = '' where rowid = $id";
	} elsif ($searchword =~ /link2/gi) {
		$string = "UPDATE korvamadot set LINK2 = '' where rowid = $id";
	} elsif ($searchword =~ /info1/gi) {
		$string = "UPDATE korvamadot set INFO1 = '' where rowid = $id";
	} elsif ($searchword =~ /info2/gi) {
		$string = "UPDATE korvamadot set INFO2 = '' where rowid = $id";
	} elsif ($searchword =~ /artist/gi) {
		$string = "UPDATE korvamadot set ARTIST = '' where rowid = $id";
	} elsif ($searchword =~ /title/gi) {
		$string = "UPDATE korvamadot set TITLE = '' where rowid = $id";
	} else {
		$string = "UPDATE korvamadot set DELETED = 1 where rowid = $id";
	}

	if ($string ne '') {
		return updateDB($string);
	}
	return;
}

sub check_if_delete {
	my ($command, $id) = @_;
	return -1 unless $id > 0;
	if ($command =~ s/ ([0-9]{1,4})//gi) {
		$id = $1;
	}
	if ($command =~ /(poista|del|delete) (.*)/gi && $id >= 0) {
		# FIXME: Del by ID
		my $searchword = $2;
		if (del_mato($searchword, $id) == 0) {
			# TODO: Print old info?
			return 1;
		}
	} elsif ($command =~ /(poista|del|delete)/gi && $id >= 0) {
		if (del_mato('', $id) == 0) {
			# TODO: Print old info?
			return 1;
		}
	}
	return 0;
}

sub parse_keyword_run_sql {
	my ($id, $command, @rest) = @_;
	my $updatestring = '';			#$server->command("msg -channel $target $title") if grep /$target/, @enabled;
	my $selectoldstring = '';
	return ($updatestring, $selectoldstring) unless $id > 0;
			# TODO: sanitize with bind_param
			# Don't delete deleted.
	if ($command =~ /.*link1:? ?(.*)/gi || $command =~ /.*url:? ?(.*)/gi) {
		my $link1 = $1;
		prind("Add link1: $link1");
		$updatestring = "UPDATE korvamadot set link1 = \"$link1\" where rowid = $id and DELETED = 0;";
		$selectoldstring = "SELECT link1 from korvamadot where rowid = $id";
	} elsif ($command =~ /link2:? ?(.*)/gi) {
		my $link2 = $1;
		prind("Add link2: $link2");
		$updatestring = "UPDATE korvamadot set link2 = \"$link2\" where rowid = $id and DELETED = 0;";
		$selectoldstring = "SELECT link2 from korvamadot where rowid = $id";
	} elsif ($command =~ /info1?:? ?(.*)/gi) {
		my $info1 = $1;
		prind("Add info1: $info1");
		$updatestring = "UPDATE korvamadot set info1 = \"$info1\" where rowid = $id and DELETED = 0;";
		$selectoldstring = "SELECT info1 from korvamadot where rowid = $id";
	} elsif ($command =~ /info2:? ?(.*)/gi) {
		my $info2 = $1;
		prind("Add info2: $info2");
		$updatestring = "UPDATE korvamadot set info2 = \"$info2\" where rowid = $id and DELETED = 0;";
		$selectoldstring = "SELECT link2 from korvamadot where rowid = $id";
	} elsif ($command =~ /artisti?:? ?(.*)/gi) {
		my $artist = $1;
		prind("Add Artist: $artist");
		$updatestring = "UPDATE korvamadot set artist = \"$artist\" where rowid = $id and DELETED = 0;";
		$selectoldstring = "SELECT artist from korvamadot where rowid = $id";
	} elsif ($command =~ /title:? ?(.*)/gi) {
		my $title = $1;
		prind("Add title: $title");
		$updatestring = "UPDATE korvamadot set title = \"$title\" where rowid = $id and DELETED = 0;";
		$selectoldstring = "SELECT title from korvamadot where rowid = $id";
	} elsif ($command =~ /lyrics:? ?(.*)/gi) {
		my $lyrics = $1;
		prind("Add lyrics: $lyrics");
		$updatestring = "Update korvamadot set quote = \"$lyrics\" where rowid = $id and DELETED = 0;";
		$selectoldstring = "SELECT quote from korvamadot where rowid = $id";
	}

	return ($updatestring, $selectoldstring);
}

sub get_position {
    my ($regex, $string) = @_;
    return if not $string =~ /$regex/;
    return (@-);
}

sub UPDATECOLUMN {
	my ($id, $column, $value, @rest) = @_;
	my $returnstring;
	my $oldvalue;
	my $sqlstr1 = "SELECT $column from korvamadot where rowid = ?";		# get old value first
	my $sqlstr2 = "UPDATE korvamadot SET $column = ? WHERE rowid = ?";
	my $dbh = KaaosRadioClass::connectSqlite($db);

	my $sth1 = $dbh->prepare($sqlstr1) or return; #die DBI::errstr;
	$sth1->bind_param(1, $id, { TYPE => SQL_INTEGER });
	$sth1->execute();
	if($oldvalue = decode_utf8($sth1->fetchrow_array)) {
		dp(__LINE__.': --fetched a result-- '. $oldvalue);
	} else {
		$oldvalue = '<tyhjä>';
	}
	$sth1->finish();

	my $sth2 = $dbh->prepare($sqlstr2) or die DBI::errstr;
	$sth2->bind_param(1, $value);
	$sth2->bind_param(2, $id, { TYPE => SQL_INTEGER });
	$sth2->execute();
	$sth2->finish();
	$dbh->disconnect();

	if ($oldvalue ne '') {
		return "Päivitetty. Oli: $oldvalue";
	}
	return 1;
}

sub IFUPDATE {
	my ($id, $command, @rest) = @_;
	my $updatestring = '';			#$server->command("msg -channel $target $title") if grep /$target/, @enabled;
	my $selectoldstring = '';
	return ($updatestring, $selectoldstring) unless $id > 0;
			# TODO: sanitize with bind_param
			# Don't delete deleted.
	my $suffix = 'UPDATE korvamadot set';
	if ($command =~ /link1:? ?(.*)/gi || $command =~ /url:? ?(.*)/gi) {
		my $link1 = $1;
		prind("Add link1: $link1");
		return UPDATECOLUMN($id, 'link1', $1);
	} elsif ($command =~ /link2:? ?(.*)/gi) {
		my $link2 = $1;
		prind("Add link2: $link2");
		return UPDATECOLUMN($id, 'link2', $1);
	} elsif ($command =~ /info1?:? ?(.*)/gi) {
		my $info1 = $1;
		prind("Add info1: $info1");
		return UPDATECOLUMN($id, 'info1', $1);
	} elsif ($command =~ /info2:? ?(.*)/gi) {
		my $info2 = $1;
		prind("Add info2: $info2");
		return UPDATECOLUMN($id, 'info2', $1);
	} elsif ($command =~ /artisti?:? ?(.*)/gi) {
		my $artist = $1;
		prind("Add Artist: $artist");
		return UPDATECOLUMN($id, 'artist', $1);
	} elsif ($command =~ /title:? ?(.*)/gi) {
		prind("Add title: $1");
		return UPDATECOLUMN($id, 'title', $1);
	} elsif ($command =~ /lyrics:? ?(.*)/gi) {
		prind("Add lyrics: $1");
		return UPDATECOLUMN($id, 'quote', $1);
	}

	if ($updatestring ne '') {
		my $oldvalue = KaaosRadioClass::readLineFromDataBase($selectoldstring);
		# HACK:
		dp(__LINE__.': oldvalue: '. $oldvalue.' oldstring: '.$selectoldstring);

		if (not $oldvalue) {
			$oldvalue = '<tyhjä>';
		}
		#my $returnvalue = updateDB($string);
		#if ($returnvalue == 0) {
			return "Päivitetty. Oli: $oldvalue";
		#}
	}

	return;
}

sub check_if_exists {
	my ($searchword, @rest) = @_;
	#dp(__LINE__.': check_if_exists');
	my @results = search_from_db($searchword);
	my $amount = @results;		# count
	my $returnstring = '';
	if ($amount > 0) {
		# TODO: print all ID's with artist - title maybe?
		my $idstring;
		my @idarray = ();
		foreach my $result (@results) {
			$idstring .= @$result[0] .", ";	# add result rowid
			push @idarray, @$result[0];
		}
		if ($amount == 1) {
			#my @results = search_id_from_db($idarray[0]);
			my $string;
			#dp(__LINE__.": string:: $string");
			$string = createAnswerFromResultsor(@{$results[0]});
			
			$returnstring = 'Löytyi '.$string;
			#dp(__LINE__.": return .. string: $returnstring");
		} else {
			$idstring .= 'Valitse jokin näistä kirjoittamalla !korvamato id: <id>';
			$returnstring = "Löydettiin $amount tulosta. ID: ".$idstring;
		}
	} elsif ($amount == 0) {
		# TODO: add korvamato
		prind("Korvamato not found yet, adding new.");
		$returnstring = 'Uusi korvamato.';
	}
	
	return ($returnstring, $amount);
}

sub insert_into_db {
	my ($command, $nick, $info1, $info2, $target, $artist, $title, $link1, $link2, @rest) = @_;

	my $pituus = length $command;
	#dp(__LINE__.": insert_into_db Pituus: $pituus");
	if ($pituus < 470 && $pituus > 5)
	{
		saveToDB($nick, $command, $info1, $info2, $target, $artist, $title, $link1, $link2);
		prind("\"$command\" request from $nick\n");
		my @resultarray = search_from_db($command);
		my $newid;		# HACK:
		foreach my $line (@resultarray) {
			$newid = @$line[0];
		}
		return ("Korvamato lisätty! ID: $newid");
	} elsif ($pituus > 470) {
		return "Teksti liiian pitkä ($pituus)! max. about 470 merkkiä!";
	} elsif ($pituus <= 5) {
		return "Teksti liiian lyhyt ($pituus)! Minimipituus on 6 merkkiä!";
	} else {
		return 'Jotain muuta tapahtui. Tarkista syöte!';
	}
	return;

}

sub if_korvamato {
	my ($msg, $nick, $target, @rest) = @_;

	if($msg =~ /^!korvamato disable/) {
		my $enabled = Irssi::settings_get_str('korvamato_enabled_channels');
		my @enabled = split / /, $enabled;
		my $newenabled = '';
		foreach my $channel (@enabled) {
			next if ($channel eq $target);
			$newenabled .= $channel.' ';
		}
		$newenabled = KaaosRadioClass::ktrim($newenabled);
		Irssi::settings_set_str('korvamato_enabled_channels', $newenabled);
		return 'Korvamato disabloitu tällä kanavalla: '.$target;
	} elsif($msg =~ /^!korvamato:?\s(.{1,470})/ugi || $msg =~ /^!km:?\s(.{1,470})/ugi)
	{
		my $command = $1;		# command the user has entered
		my $url = '';			# song possible url
		my $id = -1;			# korvamato ID (rowid in DB)
		my $searchword = '';

		if (IFURL($command) > 0) {
			return "URL löytyi $1 kertaa. Koita !korvamato etsi <url>";
			# TODO: print ID's
		}
		#dp(__LINE__.': command: '. $command);

		if ($command =~ s/^id:? (\d+)\b//gi || $command =~ s/^(\d+)$//gi) {			# search and replace from $command
			$id = $1;
			#dp(__LINE__.': id: '.$id);
		} elsif ($command =~ /^id\:?/gi) {
			return 'En tajunnut! Kokeile esim. !korvamato id: 123';
		} elsif ($command =~ /^etsi:?\s(.*)$/gi) {
			$searchword = $1;
			my $sayline = find_mato($searchword);
			if ($sayline ne '') {
				return substr $sayline, 0, 370;
			}
			return 'En tajunnut! Kokeile !korvamato etsi: <hakusana>';
		} elsif ($command =~ /^etsi/gi) {
			return 'En tajunnut! Kokeile !korvamato etsi: <hakusana>';
		}

		if (my $updated = IFUPDATE($id, $command)) {
			return $updated;
		}

		if (check_if_delete($command, $id) > 0) {
			return "Deletoitu. ID: $id";
		}

		my $amount = 0;
		my $returnstring = '';
		my ($link1, $link2, $info1, $info2, $artist, $title, $lyrics) = '';

		if ($command =~ /(.*)/gi && $id == -1) {
			my $newcommand = $1;
			if ($newcommand =~ /\bartisti?\:? (.*)/i) {
				$artist = parseAwayKeywords($1);
			} elsif ($newcommand =~ /\btitle\:? (.*)/i) {
				$title = parseAwayKeywords($1);
			} elsif ($newcommand =~ /\burl\:? (.*)/i) {
				$url = parseAwayKeywords($1);
			} elsif ($newcommand =~ /\binfo1\:? (.*)/i) {
				$info1 = parseAwayKeywords($1);
			} elsif ($newcommand =~ /\binfo2\:? (.*)/i) {
				$info2 = parseAwayKeywords($1);
			} elsif ($newcommand =~ /\blink1\:? (.*)/i) {
				$link1 = parseAwayKeywords($1);
			} elsif ($newcommand =~ /\blink2\:? (.*)/i) {
				$link2 = parseAwayKeywords($1);
			} elsif ($newcommand =~ /\blyrics\:? (.*)/i) {
				$lyrics = parseAwayKeywords($1);
			}

			# Do a search from database
			$searchword = lc($title) || lc($lyrics) || lc($newcommand);
			dp(__LINE__.": Searchword: $searchword");
			if ($searchword eq '') {
				return 'Nyt skarppiutta! Ei mennyt ihan oikein.';
			} else {
				($returnstring, $amount) = check_if_exists($searchword);
			}

			prind("\"$searchword\" request from $nick.");

		} elsif ($id != -1) {
			# TODO: search korvamato '!korvamato id 55'
			my @results = search_id_from_db($id);
			$returnstring = createAnswerFromResultsor(@results);
			return 'Löytyi '.$returnstring;
		}

		if ($amount == 0) {
			#dp(__LINE__.': insert into db next');
			$returnstring = insert_into_db($command, $nick, $info1, $info2, $target, $artist, $title, $link1, $link2);
		}
		return $returnstring;
	}
	return '';
}

# parse away other keywoards that our sloppy regexp caught
sub parseAwayKeywords {
	my ($parsa, @rest) = @_;
	dp(__LINE__.": parseAwayKeywords from: $parsa");
	$parsa =~ s/artisti?:? .*//;
	$parsa =~ s/title:? .*//;
	$parsa =~ s/url:? .*//;
	$parsa =~ s/info1:? .*//;
	$parsa =~ s/info2:? .*//;
	$parsa =~ s/link1:? .*//;
	$parsa =~ s/link2:? .*//;
	$parsa =~ s/lyrics:? .*//;
	return $parsa;
}

sub event_privmsg {
	my ($server, $msg, $nick, $address) = @_;

    my $mynick = quotemeta $server->{nick};
	return if ($nick eq $mynick);   #self-test

	if ($msg =~ /^!help korv/i || $msg =~ /^\!korvamato$/i || $msg =~ /^\!km$/i) {
		msgit($server, $nick, $helptext);
		msgit($server, $nick, get_statistics());
		return;
	} elsif ($msg =~ /^!korvamato random/i || $msg =~ /^!km random/i) {
		#dp(__LINE__.': random!');
		my $sayline = search_random_from_db();
		msgit($server, $nick, $sayline);
		return;
	}

	if ($msg =~ /^!korvamato/ || $msg =~ /^!km/) {
		my $newReturnString = if_korvamato($msg, $nick, "PRIV");
		if ($newReturnString ne '') {
			#dp(__LINE__.": YES priv");
			msgit($server, $nick, $newReturnString);
			return;
		} else {
			#dp(__LINE__.": NO priv");
			return;
		}
	}
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;

    my $enabled_raw = Irssi::settings_get_str('korvamato_enabled_channels');
    my @enabled = split / /, $enabled_raw;
	if($msg =~ /^!korvamato enable/) {
		if (grep /^$target$/i, @enabled) {
			sayit($server, $target, 'Korvamato on jo enabloitu kanavalla: '.$target);
			return;
		} else {
			$enabled_raw .= ' '.$target;
			Irssi::settings_set_str('korvamato_enabled_channels', $enabled_raw);
			return;
		}
	}
    return unless grep /^$target$/i, @enabled;

	if ($msg =~ /^[\.\!]help korvamato\b/i || $msg =~ /^!korvamato$/i || $msg =~ /^!km$/i) {
		print_help($server, $target);
		return;
	} elsif ($msg =~ /^!korvamato random/i || $msg =~ /^!km random/i) {
		dp(__LINE__.': random!');
		my $sayline = search_random_from_db();
		sayit($server, $target, $sayline);
		return;
	}

	#my $newReturnString = encode_utf8(if_korvamato($msg, $nick, "PUB"));
	my $newReturnString = if_korvamato($msg, $nick, $target);
	if ($newReturnString ne '') {
		sayit($server, $target, $newReturnString);
		return;
	} else {
		return;
	}
}

sub CREATEDB {
	# Using FTS (full-text search)
	my $sql = 'CREATE VIRTUAL TABLE korvamadot using fts4(NICK,PVM,QUOTE,INFO1,INFO2,CHANNEL,ARTIST,TITLE,LINK1,LINK2,DELETED)';
	KaaosRadioClass::writeToDB($db, $sql);
	return;
}

# Save new item to sqlite DB
sub saveToDB {
	my ($nick, $quote, $info1, $info2, $channel, $artist, $title, $link1, $link2, @rest) = @_;
	my $pvm = time;
	dp(__LINE__.': saveToDB');
	my $newdbh = DBI->connect("dbi:SQLite:dbname=$db", '', '', { RaiseError => 1 },) or die DBI::errstr;
	my $sth = $newdbh->prepare("INSERT INTO korvamadot VALUES(?,?,?,?,?,?,?,?,?,?,0)") or die DBI::errstr;
	$sth->bind_param(1, $nick);
	$sth->bind_param(2, $pvm, { TYPE => SQL_INTEGER });
	$sth->bind_param(3, $quote);
	$sth->bind_param(4, $info1);
	$sth->bind_param(5, $info2);
	$sth->bind_param(6, $channel);
	$sth->bind_param(7, $artist);
	$sth->bind_param(8, $title);
	$sth->bind_param(9, $link1);
	$sth->bind_param(10, $link2);
	$sth->execute;
	$sth->finish();
	$newdbh->disconnect();
	prind("Lyrics saved to database: $quote");
}

# Update value of existing item in DB
sub updateDB {
	my ($string, @rest) = @_;
	return KaaosRadioClass::writeToDB($db, $string);
}

# Create one line from one result!
sub createAnswerFromResultsor {
	my @resultarray = @_;
	my $amount = @resultarray;
	if ($amount == 0) {
		return 'Ei tuloksia.';
	}

	my $string;
	my $rowid = $resultarray[0] || '';
	if ($rowid ne '') { $string .= "ID ${rowid}: "; }

	my $nickster = $resultarray[1] || '';									# who added
	my $when = $resultarray[2] || '';										# when added
	#my $quote = KaaosRadioClass::replaceWeird($resultarray[3]) || '-';		# lyrics
	my $quote = decode_utf8($resultarray[3]) || '-';		# lyrics
	if ($quote ne '-') { $string .= "Lyrics: $quote, "; }
	else { return 'Ei löytynyt'; }

	#my $info1 = KaaosRadioClass::replaceWeird($resultarray[4]) || '';
	my $info1 = decode_utf8($resultarray[4]) || '';
	if ($info1 ne '') { $string .= "Info1: $info1, "; }

	#my $info2 = KaaosRadioClass::replaceWeird($resultarray[5]) || '';
	my $info2 = decode_utf8($resultarray[5]) || '';
	if ($info2 ne '') { $string .= "Info2: $info2, "; }

	my $channelresult = $resultarray[6] || '';

	#my $artist = KaaosRadioClass::replaceWeird($resultarray[7]) || '-';
	my $artist = decode_utf8($resultarray[7]) || '-';
	if ($artist ne '-') { $string .= "Artist: $artist, "; }

	#my $title = KaaosRadioClass::replaceWeird($resultarray[8]) || '-';
	my $title = decode_utf8($resultarray[8]) || '-';
	if ($title ne '-') { $string .= "Title: $title, "; }

	my $link1 = $resultarray[9] || '-';
	if ($link1 ne '-') { $string .= "URL: $link1, "; }

	my $link2 = $resultarray[10] || '';
	if ($link2 ne '') { $string .= "Link2: $link2"; }

	my $deleted = $resultarray[11];

	if ($rowid) {
		# commented out for debugging other functions.. Irssi::print("$myname: Found: ID: $rowid, nick: $nickster, when: $when, Lyrics: $quote, info1: $info1, info2: $info2, channel: $channelresult, artist: $artist, title: $title link1: $link1, link2: $link2, deleted: $deleted");
	}

	if (defined($deleted) && $deleted == 0) {
		#dp(__LINE__.": String: $string");
		return $string;
	}
	return 'Poistettu.';

}

# search rowid = korvamato ID from database
sub search_id_from_db {
	my ($id, @rest) = @_;
	my $sql = "SELECT rowid,* FROM korvamadot where rowid = $id and DELETED = 0";
	my @result = KaaosRadioClass::readLineFromDataBase($db, $sql);
	return @result;
}

sub search_from_db {
	my ($searchword, @rest) = @_;
	if ($searchword eq '') {
		return;
	}
	my $newdbh = DBI->connect("dbi:SQLite:dbname=$db", '', '', { RaiseError => 1 },) or die DBI::errstr;
	my $sth = $newdbh->prepare('SELECT rowid,* FROM korvamadot where (quote LIKE ? or info1 LIKE ? or info2 LIKE ? or artist LIKE ? or title LIKE ?) and DELETED = 0 order by rowID ASC') or die DBI::errstr;
	$sth->bind_param(1, "%$searchword%");
	$sth->bind_param(2, "%$searchword%");
	$sth->bind_param(3, "%$searchword%");
	$sth->bind_param(4, "%$searchword%");
	$sth->bind_param(5, "%$searchword%");
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

sub search_url_from_db {
	my ($searchword, @rest) = @_;
	prind("Search Url From Database: $searchword");

	my $newdbh = DBI->connect("dbi:SQLite:dbname=$db", '', '', { RaiseError => 1 },) or die DBI::errstr;
	my $sth = $newdbh->prepare('SELECT rowid,* FROM korvamadot where link1 LIKE ? or link2 LIKE ? order by rowID ASC') or die DBI::errstr;
	$sth->bind_param(1, "%$searchword%");
	$sth->bind_param(2, "%$searchword%");
	$sth->execute();

	my @line = ();
	my $index = 0;
	my @resultarray = ();
	while(@line = $sth->fetchrow_array) {
		push @{ $resultarray[$index]}, @line;
		$index++;
		last if $index > 10;
	}

	dp(__LINE__.': URL Search Dump:');
	da(@resultarray);
	# TODO: Return ID(s) and their artist if found
	return @resultarray;
}

sub search_random_from_db {
	my $sql = 'SELECT rowid,* FROM korvamadot WHERE rowid IN (SELECT rowid FROM korvamadot WHERE deleted = 0 ORDER BY RANDOM() LIMIT 1)';
	return createAnswerFromResultsor(KaaosRadioClass::readLineFromDataBase($db, $sql));
}


sub prind {
	my ($text, @rest) = @_;
	print "\0039" . $IRSSI{name} . ">\003 " . $text;
}

sub prindw {
	my ($text, @rest) = @_;
	print "\0034" . $IRSSI{name} . ">\003 " . $text;
}

sub da {
	return unless $DEBUG;
	print("$myname-debug array>");
	print Dumper (@_);
	return;
}

sub dp {
	return unless $DEBUG;
	print("$myname-debug> @_");
	return;
}

Irssi::settings_add_str('korvamato', 'korvamato_enabled_channels', '');
Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::signal_add_last('message private', 'event_privmsg');
prind("korvamato.pl v. $VERSION -- New commands: /set korvamato_enabled_channels #1 #2\n");
