#  /set elisaviihde_enabled_channels #channel1 #channel2 ...
#  Enables url fetching on these channels.
#  If debian: apt-get install libjson-perl

use warnings;
use strict;
use Irssi;
use JSON;
use Data::Dumper;
use utf8;
use Time::Piece;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;		# LAama1 20.10.2016

use vars qw($VERSION %IRSSI);
$VERSION = "20180107";
%IRSSI = (
	authors     => "LAama1",
	contact     => "ircnet: LAama1",
	name        => "tv-skripta, elisaviihde",
	description => "Fetch info from elisaviihde program guide",
	license     => "Public Domain",
	url         => "#kaaosleffat",
	changed     => $VERSION
);
#print "trying...\n";

my $myname = "elisavihihi3.pl";
my $DEBUG = 0;
my $DEBUG1 = 0;
my $DEBUG_decode = 0;
my $DEBUGT = 0;
my $lastupdated = 0;
my @allmovies;
my @allprograms;
my @tvChannels = getChannels();			# init available @tvChannels once
if (@tvChannels < 0) {
	return 1;
}

my @leffalinet;

my $loadtime = localtime;
my $tzoffset = $loadtime->tzoffset;

if ($DEBUGT) {
	Irssi::print("Timezone offset is: $tzoffset\n");
}

sub dp {
	my ($printString, @rest) = @_;
	return unless $DEBUG;
	print("$myname-debug: $printString");
}

sub dd {
	print("$myname-decode: @_") if $DEBUG_decode;
}


sub print_help {
	my ($server, $target) = @_;
	my $helpmessage = "!leffat: tulosta tämän illan tulevat leffat, !leffat <hakusana>: tulosta leffan kuvaus, !leffat nyt: tulosta nyt pyörivät leffat";
	msg_channel($server, $target, $helpmessage);
}

sub getChannels {
	#http://api.elisaviihde.fi/etvrecorder/ajaxprograminfo.sl?channels
	my $ownjson = fetch_elisaviihde_url('ajaxprograminfo', 'channels');
	if ($ownjson eq "-1") {
		Irssi::print("$myname: error fetching channels!");
		return -1;
	}
	
	my @returnArray = ();
	my @newTvChannels = ();

	foreach my $chann (@{$ownjson->{channels}}) {
		if ($chann =~ /\bHD/ || $chann =~ /sport/i || $chann =~ /Prime/ ||
			$chann =~ /Nappula/ || $chann =~ /NHL/ || $chann =~ /Pro / || $chann =~ /MTV / ||
			$chann =~ /Viasat / || $chann =~ /C More/ || $chann =~ /Ruutu\+/) {
				# parse away HD-channels and eurosport, etc.
			}  
		else {
			Irssi::print("Channel: $chann") if $DEBUGT;
			push @returnArray, $chann;	# push to global variable
		}
	}
	Irssi::print("$myname getChannels:") if $DEBUG1;
	Irssi::print Dumper (@returnArray) if $DEBUG1;
	my $count = @returnArray;                                                # count channels
	Irssi::print("$myname: fetched $count channels.");                # at script load
	return @returnArray;
}

sub fetch_elisaviihde_url {
	my ($param1, $param2, @rest) = @_;
	my $url = "http://api.elisaviihde.fi/etvrecorder/${param1}.sl?${param2}";
	dp("fetch_elisaviihde_url: $url") if $DEBUGT;

	my $response = KaaosRadioClass::fetchUrl($url, 0);
	if ($response && $response eq "-1") {
		Irssi::print("$myname: error fetching url!");
		return -1;
	}
	return -2 unless $response;
	
	my $json = JSON->new->utf8;
	$json->convert_blessed(1);

	$json = decode_json($response);
	if ($DEBUG1) {
		Irssi::print("$myname: fetch_elisaviihde_url, json:");
		Irssi::print Dumper ($json);
	}
	return $json;
}

sub getProgramInfo {
	my ($searchword, @rest) = @_;
	my @pids;
	Irssi::print("$myname: search word: ".$searchword);
	if ($#allprograms <= 2) {
		dp("no programs yet. Getting movies next.");
		@leffalinet = getMovies();
	} else {
		dp("we have some programs allready.");
	}
	foreach my $movie (@allprograms) {			#look for all instances
		if (@$movie[0] =~ /$searchword/i) {
			# $pid = @$movie[1];
			Irssi::print Dumper $movie if $DEBUG;
			push(@pids, @$movie[1]);
		}
		dp("movie: @$movie[0]") if $DEBUGT;
	}
	dp("pids amount: ".$#pids);
	Irssi::print Dumper @pids if $DEBUG;
	if (@pids) {
		my @descriptions;
		#my $localjson = fetch_elisaviihde_url('ajaxprograminfo', "programid=$pid");
		#fetch_elisaviihde_url('program', "programid=$pid");

		my $count = 0;
		my $localtime = time();
		while($count < $#pids +1) {
			my $localjson = fetch_elisaviihde_url('ajaxprograminfo', "programid=$pids[$count]");
			dp("infoz: ");
			dp(Dumper($localjson));
			
			next unless $localjson->{'name'};

			my $startDate = $localjson->{'start_time'} || 0;
			# 'start_time' => '7.1.2018 19:30:00'
			if ($startDate =~ /^(\d{1,2}\.\d{1,2}\.)\d{4} (\d{1,2}\:\d{1,2})\:\d{1,2}/) {
				# 7.1. 19:30
				$startDate = "$1 $2";
			}
			my $simplestarttime = $localjson->{'simple_start_time'} || 0;
			my $channel = KaaosRadioClass::replaceWeird($localjson->{'channel'}) || 0;
			my $name = KaaosRadioClass::replaceWeird($localjson->{'name'}) || 0;
			my $desci = KaaosRadioClass::replaceWeird($localjson->{'description'}) || 0;


			push @descriptions, "\002($startDate $channel)\002 $name: $desci" if elisatimeToUnix($localjson->{'end_time'}) > $localtime;
			dp("start time: " . elisatimeToUnix($localjson->{'start_time'}));
			dp("end time:". elisatimeToUnix($localjson->{'end_time'}));
			dp("localtime: " .$localtime);
			
			$count++;
		}

		return @descriptions;
	} else {
		dp("$myname-debug: not found!");
		return 0;
	}
}

sub getMovies {									# get all movies and programs!
	#http://api.elisaviihde.fi/etvrecorder/ajaxprograminfo.sl?channels
	dp("$myname: getting movies next");
	
	
	my @returnArray;
	my @localtime = localtime(time);
	my $hour = $localtime[2];
	my $day = $localtime[3];
	my $leffarimpsu = "";
	undef @allmovies;
	undef @allprograms;
	
	foreach my $current (@tvChannels) {
		my $singlejson = fetch_elisaviihde_url('ajaxprograminfo', "24h=$current");
		dp("getMovies: Current channel: $current") if $DEBUGT;
		next if ($singlejson < 0);
		my @programs = @{ $singlejson->{'programs'} };
		my $rimpsu = "";
		#if ($DEBUG1) {Irssi::print("Programs: "); Irssi::print Dumper(@programs);}
		foreach my $c (@programs) {
			my $moviename = "";
			if ($c->{'name'} =~ /(.*Elokuva.*)/ || $c->{'name'} =~ /(.*) \(elokuva\)/i ||
			 $c->{'name'} =~ /(Docventures.*)/ || $c->{'name'} =~ /(Kino Klassikko.*)/i ||
			 $c->{'name'} =~ /(Uusi Kino.*)/i || $c->{'name'} =~ /(Kino\%20)/i) {
				
				$moviename = grep_name(KaaosRadioClass::replaceWeird($1)); # x

				my $starttime = $c->{'simple_start_time'} || "0";
				my $endtime = $c->{'end_time'} || "0";

				push @allmovies, [$moviename, $c->{'id'}, $starttime, $c->{'start_time'}, $endtime, $current, $c->{'simple_end_time'}];
				push @allprograms, [$moviename, $c->{'id'}, $starttime, $c->{'start_time'}, $endtime, $current, $c->{'simple_end_time'}];
				my $moviestarthour = 0;					# movie start hour
				if ($starttime =~ /^(\d{1,2})\:/) {
					$moviestarthour = $1;
				}
				
				my $moviestart = $c->{'start_time'};			# movie start date + hour
				my $moviestartday = 0;
				if ($moviestart =~ /^(\d{1,2})\./) {
					$moviestartday = $1;
				}

				last if ($moviestartday > $day && $moviestarthour >= 5);
				last if ($moviestarthour >= 5 && $moviestartday == 1 && $day >= 28);
				
				my $simpleendtime = $c->{'simple_end_time'};
				
				$moviename = "${starttime}-${simpleendtime} ${moviename}";
				$rimpsu .= "${moviename}, ";
				dp("kanavaE2: $current, movie: $moviename id: $c->{'id'} ");

			} elsif ($c->{'name'} =~ /\([\d]{1,2}\)/ ) {	#jos esim: jotain_leffan_nimenä_ja (16)
				$moviename = $c->{'name'};
				$moviename = grep_name(KaaosRadioClass::replaceWeird($moviename));
				Irssi::print("kanava: $current, movie: $moviename, id: $c->{'id'}, start time: $c->{'simple_start_time'}, end time: $c->{'simple_end_time'}") if $DEBUG1;
				#push @allmovies, [$moviename, $c->{'id'}, $c->{'simple_start_time'}, $c->{'start_time'}, $c->{'end_time'}, $current, $c->{'simple_end_time'}];
				push @allprograms, [$moviename, $c->{'id'}, $c->{'simple_start_time'}, $c->{'start_time'}, $c->{'end_time'}, $current, $c->{'simple_end_time'}];

				my $startUnix = elisatimeToUnix($c->{'start_time'});
				my $endUnix = elisatimeToUnix($c->{'end_time'});

				my $difference = $endUnix - $startUnix;				# program length in seconds
				
				if ($difference >= 5300) {
					push @allmovies, [$moviename, $c->{'id'}, $c->{'simple_start_time'}, $c->{'start_time'}, $c->{'end_time'}, $current, $c->{'simple_end_time'}];
					Irssi::print("difference: $difference") if $DEBUG1;
					my $starttime = $c->{'simple_start_time'};
					my $moviestarthour = 0;
					if ($starttime =~ /^(\d{1,2})\:/) {
						$moviestarthour = $1;
					}

					my $moviestart = $c->{'start_time'};
					my $moviestartday = 0;
					if ($moviestart =~ /^(\d{1,2})\./) {
						$moviestartday = $1;
					}
					last if ($moviestartday > $day && $moviestarthour >= 5);
					last if ($moviestarthour >= 5 && $moviestartday == 1 && $day >= 28);
                
					my $endtime = $c->{'simple_end_time'};
	
					$moviename = "${starttime}-${endtime} ${moviename}";
					$rimpsu .= "${moviename}, ";
					dp("kanava2: $current, $moviename, id: $c->{'id'}");
				} else {
					Irssi::print("bogus hit, difference: $difference") if $DEBUG1;
				}
			} else {
				my $moviename = KaaosRadioClass::replaceWeird($c->{'name'});
				push @allprograms, [$moviename, $c->{'id'}, $c->{'simple_start_time'}, $c->{'start_time'}, $c->{'end_time'}];	# add to array
				if ($DEBUG1) { Irssi::print("kanavaD: $current, ohjelma: $moviename, id: $c->{'id'}, start time: $c->{'simple_start_time'}, end time: $c->{'simple_end_time'}") ;}
			}
		} # end of foreach

		if ($rimpsu) {
			$rimpsu = "\002${current}\002: " . $rimpsu;
			dp("rimpsu: $rimpsu") if $DEBUGT;
			$leffarimpsu .= $rimpsu;
			#my $len = length($leffarimpsu);
			if (length($leffarimpsu) > 150) {				# limit line length a little
				push @returnArray, $leffarimpsu;
				$leffarimpsu = "";
			}
		}
	}	# end of foreach(?)

	if ($leffarimpsu ne "") {
		push @returnArray, $leffarimpsu;
		$leffarimpsu = "";
	}
	$lastupdated = time();
	return @returnArray;

}

sub elisatimeToUnix {
	my ($timeString, @rest) = @_;
	# for example: 21.11.2015 19:40:00
	# or 'start_time' => '7.1.2018 19:30:00'
	Irssi::print("elisavihihi.pl-debug: Timestring: $timeString <<<") if $DEBUG1;
	my $timePiece = "";
	if ($timeString =~ /(\d{1,2}\.\d{1,2}\.\d{4} \d{1,2}\:\d{2}\:\d{2})/) {
		$timePiece = Time::Piece->strptime($timeString, '%d.%m.%Y %H:%M:%S');
		dp("timePiece next: ".$timePiece) if $DEBUGT;
	}
	#Irssi::print Dumper $timePiece if $DEBUGT;
	
	return $timePiece->epoch if $timePiece;
	dp("elisatimeToUnix Error.");
	return 0;
}

=pod
sub unixtimeToElisa {
	my ($unixtime, @rest) = @_;
	my $returnString = localtime($unixtime);
	Irssi::print("returnString: $returnString") if $DEBUGT;
	return $returnString;
}
=cut


sub grep_name {
	my ($param, @rest) = @_;
	return 0 unless $param;
	Irssi::print("$myname param before: $param") if $DEBUG1;

	$param =~ s/Elokuva\: //g;
	Irssi::print("$myname param after: $param") if $DEBUG1;
	return $param;
	
}

sub msg_channel ($$@) {
	Irssi::print("in msg_channel!") if $DEBUG1;
	Irssi::print Dumper @_ if $DEBUG1;
	my ($server, $target, @arraym, @rest) = @_;
	foreach my $newline (@arraym) {
		$server->command("msg -channel $target $newline");
	}

}

sub search_word {
	my ($searchWord, @rest) = @_;
	dd("$myname searching: $searchWord");
	$searchWord = KaaosRadioClass::replaceWeird($searchWord);
	dd("searchword after: $searchWord");
	if ((time() - $lastupdated) > 60*60*2) {          #2 hours
		Irssi::print("$myname: last update was more than 2 hours ago..");
		@leffalinet = getMovies();
	}
	my @programinfos = getProgramInfo($searchWord);
	return @programinfos;
}

sub moviesNow {
	getMovies() unless @allmovies;
	#$ENV{TZ} = 'Europe/Helsinki';
	my $timeNow = time();
	if (($timeNow - $lastupdated) > 60*60*2) {          # more than 2 hours ago
		Irssi::print("$myname: more than 2 hours ago..") if $DEBUGT;
		@leffalinet = getMovies();
	}
	my @programsNow;
	Irssi::print("$myname.pl: Time now: $timeNow") if $DEBUGT;
	foreach my $movie (@allmovies) {
		Irssi::print Dumper $movie if $DEBUG1;
		my $movieEndTime = elisatimeToUnix(@$movie[4]);
		my $movieStartTime = elisatimeToUnix(@$movie[3]);
		Irssi::print("start time: $movieStartTime endtime: $movieEndTime timenow: $timeNow tzoffset: $tzoffset") if $DEBUGT;
		if ($movieEndTime > $timeNow && $DEBUGT) {Irssi::print("match end time") };
		if (($movieStartTime - $tzoffset) < $timeNow && $DEBUGT) {Irssi::print("match start time")};
		if (($movieEndTime - $tzoffset) > $timeNow && ($movieStartTime - $tzoffset) < $timeNow) {
			push @programsNow, ["\002@$movie[5]:\002 ".@$movie[2]."-".@$movie[6]." @$movie[0]"];
		}
	}
	Irssi::print("End ..") if $DEBUGT;
	Irssi::print Dumper @programsNow if $DEBUGT;

	return @programsNow;
}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	my $mynick = quotemeta $serverrec->{nick};
	return if ($nick eq $mynick);   #self-test
	# Check we have an enabled channel
	my $enabled_raw = Irssi::settings_get_str('elisaviihde_enabled_channels');
	my @enabled = split(/ /, $enabled_raw);
	return unless grep(/$target/i, @enabled);
	
	# Check for keywords
	if ($msg =~ /^[\.\!]help\b/i) {
		print_help($server, $target);
		return;
	}
	return unless ($msg =~ /[\.\!]leffat\b/i);
	Irssi::print("$myname: $nick requested !leffat on channel $target");
	dp("$myname nick: $nick, self: ".$server->{nick});
	my @programinfos;

	if (KaaosRadioClass::floodCheck() == 1) {				# return if flooding
		$server->command("msg -channel $target flood..");
		return;
	}
	
	if ((time() - $lastupdated) > 60*60*2) {				# 2 hours
		Irssi::print("$myname: more than 2 hours ago..") if $DEBUGT;
		@leffalinet = getMovies();
	}
	
	if ($msg =~ /leffat nyt$/) {
		my @rimpsan = moviesNow();
		my $rimpsu = "";
		foreach my $line (@rimpsan) {
			$rimpsu .= @$line[0];
			$rimpsu .= ", ";
		}
		@programinfos = $rimpsu;
		
	} elsif ($msg =~ /\bleffat kaikki (.{3,100})/i) {
		my $searchWord = $1;
		@programinfos = search_word($searchWord);
	} elsif ($msg =~ /leffat (.{3,100})/i) {			#search movie
		my $searchWord = $1;
		@programinfos = search_word($searchWord);
		my $count = @programinfos;
		if ($count > 1) {
			@programinfos = $programinfos[0]." <$count l�ytyi>";	

		}
	} else {
		foreach my $newline (@leffalinet) {
			$server->command("msg -channel $target $newline");
		}
	}
	Irssi::print Dumper @programinfos if $DEBUG1;
	#msg_channel($server, $target, @programinfos);
	
	foreach my $newline (@programinfos) {
		$server->command("msg -channel $target $newline");
	}


	#foreach my $newline (@leffalinet) {
	#	$server->command("msg -channel $target $newline");
	#}
	if ($DEBUG1) { Irssi::print("elisavihihi3.pl done!"); }
	
}

sub sig_msg_pub_own {
	my ($server, $msg, $target) = @_;
	return unless ($msg =~ /^[\!\.]leffat\b[^\:]/i);
 	# Check we have an enabled channel
 	my $enabled_raw = Irssi::settings_get_str('elisaviihde_enabled_channels');
 	my @enabled = split(/ /, $enabled_raw);
 	return unless grep(/$target/i, @enabled);
	if ($DEBUG1) {
		Irssi::print("Server data:");
		Irssi::print Dumper $server;
	}
	sig_msg_pub($server, $msg, $server->{wanted_nick}, "", $target);
}

Irssi::settings_add_str('elisaviihde', 'elisaviihde_enabled_channels', 'Kaaos-komennot');
Irssi::signal_add('message public', 'sig_msg_pub');
Irssi::signal_add('message own_public', 'sig_msg_pub_own');

