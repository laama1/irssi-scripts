#omdb api http://omdbapi.com/
use Irssi;
use strict;
use warnings;
use LWP::UserAgent;
#use URI::Escape qw( uri_escape );
#use URI::Encode;
use Data::Dumper;
use JSON; 
use vars qw($VERSION %IRSSI);
use Data::Dumper;
use KaaosRadioClass;		# LAama1 26.10.2016


$VERSION = '2019-01-22';
%IRSSI = (
        authors     => 'LAama1',
        contact     => "LAama1 #kaaosleffat",
        name        => "IMDB/OMDB",
        description => "Fetch info from omdbapi or theimdbapi.org",
        license     => "Fublic Domain",
        url         => "http://kaaosradio.fi",
        changed     => $VERSION
);

my $DEBUG = 1;
my $DEBUG1 = 0;
my $debugfilename = Irssi::get_irssi_dir(). '/scripts/urldebuglog.txt';
my $json = JSON->new();
$json->allow_blessed(1);
#my $ua = LWP::UserAgent->new(timeout => '4');

# OMDB api
my $apikey = 'a06b4d3f';

sub print_help {
	my ($server, $target, $is_enabled) = @_;
	my $helpmessage = '!imdb <hakusana> <leffa|sarja|episodi> <vuosi>: Hae leffoja OMDB:stä hakusanalla, muut parametrit auttavat tarkentamaan hakua. Tulostaa ensimmäisen osuman.'.
	' Käytössä: '.$is_enabled;
	if ($is_enabled) {
		$helpmessage .= '. Deaktivoi skripti kirjoittamalla: !imdb off.';
	} else {
		$helpmessage .= '. Aktivoi skripti kirjoittamalla: !imdb on.';
	}
	sayit($server, $target, $helpmessage);
	return 0;
}

sub do_imdb {
	my ($server, $msg, $nick, $address, $target) = @_;
	return if ($nick eq $server->{nick});   #self-test
    my $enabled_raw = Irssi::settings_get_str('imdb_enabled_channels');
    my @enabled = split / /, $enabled_raw;
    
	my $is_enabled = grep /^$target$/, @enabled;
	if ($msg =~ /!help imdb/i || $msg =~ /!imdb$/i) {
		print_help($server, $target, $is_enabled);
		return;
	}
	
	return unless ($msg =~ /!imdb\b/i);
	return if KaaosRadioClass::floodCheck() == 1;

	if ($msg eq "!imdb on") {
		if ($is_enabled) {
			sayit($server, $target, 'Aktivoitu jo!');
			return;
		} else {
			Irssi::settings_set_str('imdb_enabled_channels', $enabled_raw . ' '. $target);
			sayit($server, $target, 'Aktivoitiin IMDB-skripti kanavalla: ' . $target);
			return;
		}
	} elsif ($msg eq "!imdb off") {
		if (!$is_enabled) {
			sayit($server, $target, 'Deaktivoitu jo!');
			return;
		} else {
			my $index = 0;
			$index++ until $enabled[$index] eq $target;
			splice(@enabled, $index, 1);
			Irssi::settings_set_str('imdb_enabled_channels', join(' ',@enabled));
			sayit($server, $target, 'Deaktivoitiin IMDB-skripti kanavalla: '.$target);
			return;
		}
	}
	return unless $is_enabled;
	
	my $param = 't';		# title search
	my $query;				# search query
	my $year;				# year search

	if ($msg =~ /\!imdb (.*)$/) {		# if search words found
		$query = lc $1;
	} else {
		return 0;
	}
	
	Irssi::print("!imdb request on $target from nick $nick: $msg");

	if ($query =~ /\b(19|20)(\d{2})\b/) {
		# FIXME: if movie has year in it's name
		$year = $1.$2;
		$query =~ s/ $year$//;	#remove year from title query
		dp("year query! query. $query, year: $year after: $msg");
	}
	if ($query =~ /(\s?search\s?)/i) {
		$param = 's';
		$query =~ s/$1//;
	} elsif ($query =~ /(tt\d{4,10})/) {
		$param = 'i';
		$query = $1;
	} elsif ($query =~ /(\s?leffa\s?|\s?movie\s?)/i) {
		$query.='&type=movie';
		$query =~ s/$1//;
	} elsif ($query =~ /(\s?sarja\s?|\s?series\s?)/i) {
		$query.='&type=series';
		$query =~ s/$1//;
	} elsif ($query =~ /(\s?episodi\s?|\s?episode\s?)/i) {
		$query.='&type=episode';
		$query =~ s/$1//;
	}

	return imdb_fetch($server, $target, $query, $param, $year);
	#return 0;

}

# Signal received from another function. URL as parameter
sub sig_imdb_search {
	my ($server, $searchparam, $target, $searchword) = @_;
	# 'imdb_search_id', $server, 'tt-search', $target, $1
	#return unless $target ~~ Irssi::settings_get_str('imdb_enabled_channels');
    my $enabled_raw = Irssi::settings_get_str('imdb_enabled_channels');
    my @enabled = split / /, $enabled_raw;
	return unless grep /^$target$/, @enabled;

	Irssi::print($IRSSI{name}.", signal received: $searchparam, $searchword");
	my $param = 'i';
	imdb_fetch($server, $target, $searchword, $param);

}

sub imdb_fetch {
	my ($server, $target, $query, $param, $year, @rest) = @_;
	unless ($query) {
		sayit($server, $target, 'En älynnyt..');
		return 0;
	}
	my $url = "http://www.omdbapi.com/?${param}=${query}&apikey=$apikey" if $param and $query;
	#my $url = "http://www.theimdbapi.org/api/find/movie?title=${query}";

	$url .= "&y=${year}" if $year;
	
	my $imdb = do_search($url);
	#Irssi::print Dumper $imdb if $DEBUG1;
	if (!defined($imdb)) {
		my $saystring = search_omdb($query);
		dp("Saystring: $saystring");
		#my $saystring = search_theimdb($query);
		#my $saystring = search_theimdb($url);
		if (defined($saystring)) {
			sayit($server, $target, $saystring);
		} else {
			#sayit($server, $target, "$nick, try harder?");
			sayit($server, $target, "try harder?");
		}
		return;
	}

	# OMDB-API koodia
	if ($imdb->{Response} =~ /True/ ) {
		dp("imdb->Response = TRUE");
		my $saystring = print_line_from_search_result($imdb);
		sayit($server, $target, $saystring);
		return 0;
	}
	if ($imdb ne '1' && $imdb->{totalResults} && $imdb->{totalResults} > 1) {
		dp('imdb total results more than one!');
		my $manyfound = $imdb->{totalResults};
		my $sayline;

		my $i = 0;
		while ($i < $manyfound && $i < 6) {
			dp("Search ${i}:");
			dp(Dumper $imdb->{"Search"}[$i]);
			$sayline .= $imdb->{"Search"}[$i]->{Title}. " ".$imdb->{"Search"}[$i]->{Year}." (".$imdb->{"Search"}[$i]->{Type}."), ";
			dp('Sayline: '.$sayline);
			$i++;
		}
		sayit($server, $target, "$sayline <$manyfound found>");
		return 0;
	} #elsif ($imdb eq "1" || $imdb->{totalResults} eq undef) {
		else {
		dp('imdb no results found');
		sayit($server, $target, 'Nothing found :P');
		return 0;
	}
 
	return 1;
}

# use option "s" to search $query instead.
sub search_omdb {
	my ($query, @rest) = @_;
	my $url = "http://www.omdbapi.com/?s=${query}&apikey=${apikey}";
	#my $url = "http://www.theimdbapi.org/api/find/movie?${query}";
	my $got = KaaosRadioClass::fetchUrl($url, 0);
	dp('search_omdb url: '.$url);
	my $imdb = eval {$json->utf8->decode($got)};
	
	return if $@;
	#return -1 unless $imdb;
	
	if ($imdb ne "0" && $imdb->{totalResults} && $imdb->{totalResults} > 1) {
		dp("search-omdb: More than one total results.");
		my $manyfound = $imdb->{totalResults};
		my $sayline = "";
		my $i = 0;
		while ($i < $manyfound && $i < 6) {			# max 6 items
			dp("Search ${i}:");
			dp(Dumper $imdb->{'Search'}[$i]);
			#$sayline .= $imdb->{"Search"}[$i]->{Title}. " ".$imdb->{"Search"}[$i]->{Year}." (".$imdb->{"Search"}[$i]->{Type}."), ";
			print_line_from_search_result($imdb->{'Search'}[$i]);
			$i++;
		}
		return $sayline ." <$manyfound found>";
	} elsif ($imdb->{totalResults} && $imdb->{totalResults} == 1) {
		
		dp("search_omdb imdb dumber: ");
		dp(Dumper $imdb);
		my $imdbID = $imdb->{'Search'}[0]->{imdbID};
		dp("imdbID: $imdbID");
		
		$imdb = do_search("http://omdbapi.com/?i=".$imdbID."&apikey=${apikey}");
		#$imdb = do_search("http://theimdbapi.com/api/find/movie?movie_id=".$imdbID);
		dp("search-omdb imdb duber after:");
		dp(Dumper $imdb);
		return print_line_from_search_result($imdb);
	}
	return;
}

=pod
sub search_theimdb {
	#my ($query, @rest) = @_;
	my ($url, @rest) = @_;
	Irssi::print("url: ".$url) if $DEBUG;
	#my $url = "http://www.theimdbapi.org/api/find/movie?${query}";
	#http://www.theimdbapi.org/api/find/movie?title=terminator&year=1984
	my $got = KaaosRadioClass::fetchUrl($url, 0);
	Irssi::print("imdb3.pl debug search_theimdb: ".$url) if $DEBUG;
	my $imdb = $json->utf8->decode($got);
	
	return -1 unless $imdb;
	
	my $ind = 0;
	foreach my $result (@$imdb) {
		#Irssi::print("result: ". Dumper $result);
		#Irssi::print("end of result ".$i);
		Irssi::print("rating: ". $result->{rating});
		Irssi::print("title: ". $result->{original_title});
		Irssi::print("title2: ". $result->{title});
		Irssi::print("IMDB ID: ". $result->{imdb_id});
		Irssi::print("director: ". $result->{director});
		Irssi::print("URL: ". $result->{url}->{url});
		Irssi::print("Description: ". $result->{description});
		$ind++;
	}


	if ($ind > 0) {
		my $manyfound = $ind;
		my $sayline = "";
		my $i = 0;
		if ($manyfound > 1) {
			$sayline = "Results: ";
			while ($i < $manyfound && $i < 6) {			# max 6 items
				Irssi::print("Search ${i}:") if $DEBUG;
				Irssi::print Dumper @$imdb[$i] if $DEBUG;
				#$sayline .= $imdb->{"Search"}[$i]->{Title}. " ".$imdb->{"Search"}[$i]->{Year}." (".$imdb->{"Search"}[$i]->{Type}."), ";
				$sayline .= print_short_line_from_multiple_results(@$imdb[$i]);
				$i++;
			}
			return $sayline ."<$manyfound found>";
		} elsif ($manyfound == 1) {
			my $imdbID = @$imdb[0]->{imdb_id};
			Irssi::print("imdbid: ".$imdbID) if $DEBUG;
			#$sayline = ""
			#$imdb = do_search("http://theimdbapi.org/api/find/movie?movie_id=".$imdbID);
			return print_line_from_search_result(@$imdb[0]);
		}
	} else {
		return "No results!";
	}

	} elsif ($imdb->{totalResults} && $imdb->{totalResults} == 1) {
		
		Irssi::print("imdb3.pl debug search_theimdb imdb dumber: ") if $DEBUG;
		Irssi::print Dumper $imdb if $DEBUG;
		
		#Irssi::print("imdbID: $imdbID") if $DEBUG;
		
		
		Irssi::print("imdb3.pl debug imdb duber after:") if $DEBUG;
		Irssi::print Dumper $imdb if $DEBUG;
		return print_line_from_search_result($imdb);
	}

	return 1;
}
=cut

sub print_short_line_from_multiple_results {
	my ($param, @rest) = @_;
	my $sayline = $param->{title} . " (" .$param->{year}. "), ";
	return $sayline; 
}

=pod
sub print_line_from_search_result {
	# theimdbapi
	my (@param, @rest) = @_;
	Irssi::print("imdb3.pl debug print_line_from_search_result param dumper: ") if $DEBUG;
	Irssi::print Dumper @param if $DEBUG;
	
	my ($link, $title, $title2, $actors, $plot, $rating) = "";

	$link = "http://www.imdb.com/title/" . $param[0]->{imdb_id};
	#$link = $param[0]->{url}->{url};
	$title = "\002".$param[0]->{title}." [".$param[0]->{year}."]\002";
	$title2 = "";
	#Irssi::print "genre: ". Dumper $param[0]->{genre};
	Irssi::print "genre: ". $param[0]->{genre};
	foreach my $genre (@{$param[0]->{genre}}) {
		Irssi::print "genre123: ". $genre;
		$title2 .= "$genre, ";
	}

	$title2 .= "\002Directed by\002 ".$param[0]->{director} if ($param[0]->{director} ne 'N/A');
	$actors = "\002Actors:\002 ";
	Irssi::print "actors: ". Dumper $param[0]->{'stars'};
	#Irssi::print "actors: ". $param[0]->{'stars'};
	foreach my $actor (@{$param[0]->{stars}}) {
		Irssi::print "actor123: ". $actor;
		$actors .= "$actor, "
	}

	$plot = "\002Plot:\002 ".$param[0]->{storyline}. " " if ($param[0]->{storyline} ne 'N/A');
	$rating = "\002Rate:\002 ".$param[0]->{rating}." (".$param[0]->{rating_count}.")" if ($param[0]->{rating} ne 'N/A');
	return "$title $title2, ${actors}${plot}${rating}, $link";
}
=cut

# OMDB-api
sub print_line_from_search_result {
	my ($param, @rest) = @_;
	my ($link, $title, $title2, $actor, $plot, $rating) = "";

	$link = "http://www.imdb.com/title/" . $param->{imdbID};
	$title = "\002".$param->{Title}." [".$param->{Year}."]\002";
	$title2 = $param->{Genre};
	$title2 .= " \002Directed by\002 ".$param->{Director} if ($param->{Director} ne 'N/A');
	$actor = "\002Actors:\002 ".$param->{Actors}. " ";
	$plot = "\002Plot:\002 ".$param->{Plot}. " " if ($param->{Plot} ne 'N/A');
	$rating = "\002Rate:\002 ".$param->{imdbRating}." (".$param->{imdbVotes}.")" if ($param->{imdbRating} ne 'N/A');
	return "$title $title2, ${actor}${plot}${rating}, $link";
}

# first search
sub do_search {
	my ($url, @rest) = @_;
	dp("do_search url: $url");
	my $got = KaaosRadioClass::fetchUrl($url, 0);
	#Irssi::print("do_search got: $got") if $DEBUG;
	KaaosRadioClass::writeToFile($debugfilename, $got) if $DEBUG;
	if ($got eq '-1') {
		dp("imdb3.pl do_search error");
		return;
	}

	my $imdb = eval {$json->utf8->decode($got)};
	#my $imdb = $json->decode($got);
	return if $@;
	Irssi::print "do_search IMDB: ".Dumper $imdb if $DEBUG1;
	#if ($imdb->{Response} !~ /True/ ) {
	#	Irssi::print("imdb3.pl debug do_search: Not found, try harder!");
	#	return 1;
	#}
	return $imdb;
}

sub dp {
	return unless $DEBUG;
	my $sayline = shift;
	Irssi::print("debug: $sayline");
}

sub sayit {
	my ($server, $target, $msg) = @_;
	$server->command("MSG $target $msg");
}

sub sig_msg_pub_own {
	my ($server, $msg, $target) = @_;
	do_imdb($server, $msg, $server->{wanted_nick}, "", $target);
}

Irssi::signal_add('imdb_search_id', 'sig_imdb_search');
Irssi::settings_add_str('imdb', 'imdb_enabled_channels', 'Kaaos-komennot');
Irssi::signal_add('message public', 'do_imdb');
Irssi::signal_add('message own_public', 'sig_msg_pub_own');
