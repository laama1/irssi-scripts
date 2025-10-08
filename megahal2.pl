#!perl
#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Lataa koodit osoitteesta https://github.com/laama1/AI-MegaHAL
# dnf install perl-CPAN


use warnings;
use strict;
use Irssi;
#use lib $ENV{HOME}."/code/AI-MegaHAL/blib";
use AI::MegaHAL;
use vars qw($VERSION %IRSSI);
use File::Copy;
use POSIX;
use Data::Dumper;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;      # LAama1 8.11.2017
use utf8;
use Encode;

$VERSION = '0.26';
%IRSSI = (
	'authors' => 'Craig Andrews, LAama1',
	'contact' => 'craig@simplyspiffing.com',
	'name'    => 'MegaHAL Irssi - 2.0',
	'description' => 'Donut Monkies AI',
	'license' => 'GNU General Public License 3.0',
	'version' => $VERSION
);


# Initialise the AI
my $charset = 'iso-8859-1';
my $megahal = undef;
my $megahal_path = '';
my $ignore = {};
my $flood = {};
my $lastwords = {};
my $ratio_posts;
my $ratio_seconds;
my $ignore_timeout;
my $prevent_flood;
my @valid_targets = ();
my @ignores = (
	'That %s is a noisy bugger.',
	'I don\'t want to talk to %s any more.',
	'What is %s blathering on about?',
	'I do with %s would shut up.',
	'Is anybody else listening to %s?',
);

# react to these
my @wordlist = (
	'tietokone',
	'paskat',
	'moik',
	'terve',
	'niinist',
	'trump',
	'biden',
	'hytty',
);

my @ignorenicks = (
	'kaaosradio',
	'ryokas',
	'KD_Butt',
	'micdrop',
	'KD_Bat',
);

my @channelnicks = ();               # value of nicks from the current channel
my $currentchan = '';						# used in flood protect
my $currentnetwork = '';						# used in flood protect

my $DEBUG = 0;
my $myname = 'megahal2.pl';


sub irssi_log {
	my $msg = shift;
	print("MegaHAL:: $msg");
}

##
# Attempt to load the brain from the specified directory if it is
# not already loaded, or reset the brain to undef if no path supplied
##
sub populate_brain {
	my $brain = shift;
	dp(__LINE__." Brain path: ".$brain);
	unless (length $brain && -d $brain) {
		$megahal = undef;
	}

	# If we've never loaded an instance for this channel before, 
	# or if the path has changed, reload it
	if (!defined $megahal || $megahal_path ne $brain) {

		$megahal_path = $brain;
		$lastwords = {};
		$ignore = {};
		$flood = {};
		$megahal = new AI::MegaHAL(
			'Path' => $brain,
			'AutoSave' => 1,
			'Banner' => 0,
			'Wrap' => 0,
		);
	}
	irssi_log("Brain populated..");
}

## TODO: 
sub reset_brain {
	undef $megahal;
	my $braindir = Irssi::settings_get_str('megahal_brain');
	my $braindir_target = $braindir.'/bu/'. strftime("%Y-%m-%d", localtime);
	mkdir $braindir_target;
	move($braindir.'/megahal.brn', $braindir_target);
	move($braindir.'/megahal.dic', $braindir_target);
	#move($braindir.'/megahal.trn', $braindir_target);	# move training file also?
	load_settings();
}

##
# Save the contents of the brain to megahal.brn
##
sub save_brain {
	my ($data, $server, $witem) = @_;
	$megahal->_cleanup();
	irssi_log("Brains saved, probably");
}

##
# Load the settings from the irssi configuration
##
sub load_settings() {
	my $brain = Irssi::settings_get_str('megahal_brain');

	# Create the megahal object
	if (length $brain) {
		dp(__LINE__.' Populate brain next..');
		populate_brain($brain);
	}

	my $channels = Irssi::settings_get_str('megahal_channels');
	@valid_targets = split / +/, $channels;

	my $antiflood = Irssi::settings_get_bool('megahal_antiflood');
	if ($antiflood) {
		$prevent_flood = 0;

		my $floodratio = Irssi::settings_get_str('megahal_flood_ratio');
		my ($posts, $seconds) = split /:/, $floodratio;

		my $ignoreTO = Irssi::settings_get_int('megahal_ignore_timeout');

		if ($posts > 0 && $seconds > 0 && $ignoreTO > 0) {
			$ratio_posts = $posts;
			$ratio_seconds = $seconds;
			$ignore_timeout = $ignoreTO;
			$prevent_flood = 1;
		} else {
			irssi_log('Not enabling flood protection until flood ratio and ignore timeout are set');
		}

	} else {
		$prevent_flood = 0;
	}
}

##
# Get the megahal object associated with a particular target
# At the moment, it either returns the global megahal instance or
# undef depending if the target is in the valid_targets list.
# It could be changed to provide a separate brain per channel
# if the underlying libmegahal.c supported such a thing.
##
sub get_megahal {
	my $target = shift;
	return $megahal if grep {/^$target$/i} @valid_targets;
	#dp("MegaHAL Brains not found for $target.");
	return undef;
}

##
# Fun stuff
# Sometimes things exist just because they're funny
##

##
# Generate a simple, and wrong, haiku using feedback from the
# megahal engine and keywords the user supplies
##
sub get_haiku_line {
	my ($words, $count) = @_;

	my $line = '';
	my $syllables = 0;
	my $i = 10;
	while ($count > $syllables && scalar(@{$words}) > 0 && $i > 0) {
		$i--;
		$line .= shift @{$words};
		$line .= ' ';
		#irssi_log('add space!');
		#my @s = $line=~/([aeiouy]+)/gi;
		my @s = $line=~/([aeiouy���])/gi;
		$syllables = scalar(@s);
	}
	return $line;
}

sub give_me_a_haiku {
	#return;
	my ($megahal, $server, $data, $nick, $mask, $target) = @_;

	my $string = $megahal->do_reply($data, 0);
	$string .= ' ';
	$string .= $megahal->do_reply($string, 0);
	$string .= ' ';
	$string .= $megahal->do_reply($string, 0);

	my @words = $string =~ /\S+/g;

	my @haiku;
	push @haiku, get_haiku_line(\@words, 5);
	push @haiku, get_haiku_line(\@words, 7);
	push @haiku, get_haiku_line(\@words, 5);

	#$server->command("msg $target -!- ". KaaosRadioClass::replaceWeird($_)) for @haiku;
	$server->command("msg $target -!- ". $_) for @haiku;
}

##
# Public Responder
# The bulk of the work goes on in here, including flood and repeat
# protection, learning and reply generation. It's not as scary as it looks 
##
sub public_responder {
	my ($server, $data, $nick, $mask, $target) = @_;
	my $my_nick = $server->{'nick'};
	my $skip_oraakkeli_but_learn = 0;   # if oraakkeli.pl script is enabled, this is a fix.
	return if $nick ~~ @ignorenicks;
	return unless $target ~~ @valid_targets;
	return if $nick eq $my_nick;		# Don't talk to yourself
	return if $data =~ /kaaos/i && $target =~ /\#kaaosradio/i;

	# TEMP HACK:
	return unless $nick eq "laama";
	
	# Ignore lines containing URLs
	return if $data =~ /tps?:\/\//i || $data =~ /www\./i;

	#$skip_oraakkeli_but_learn = ((index $data, $my_nick) >= 0 && $data =~ /(.*)\?/); # oraakkeli parseri. Jos lause päättyy kysymysmerkkiin, ei vastata siihen
	#dp(__LINE__." $myname: Giving data to Oraakkeli: ". int $skip_oraakkeli_but_learn);
	#dp("test1");
	# Get the megahal instance for this channel
	my $megahal = get_megahal($target);
	return unless defined $megahal;
	#dp("test2");
	# replace weird/utf8 characters from user input
	Encode::from_to($data, 'utf-8', $charset);
	#$data = KaaosRadioClass::replaceWeird($data);

	# If all the user wants is a haiku, just do it
	if ($data =~ /^!haiku/ && $skip_oraakkeli_but_learn == 0) {
		if (KaaosRadioClass::floodCheck(3) > 0) {
			irssi_log("Haiku flood detected ($nick)! ..skip");
			return;
		}
		$data =~ s/\!haiku *//;
		irssi_log("!haiku search word: $data");
		give_me_a_haiku($megahal, $server, $data, $nick, $mask, $target);
		return;
	}
	if ($data =~ /^!/) {    # if !command
		irssi_log("Some un understood !command found, return: ".$data) if $DEBUG;
		return;
	}
	dp("test3");
	# check nicks from the channel
	populate_nicklist($target, $server);
	foreach my $currentnick (@channelnicks) {
		# go through all nicks from channel
		if ($data =~ $currentnick) {
			# if somebodys nick is found from the data
			# exit loop if it's mine.
			last if $currentnick eq $my_nick;

			# OR, remove nick from data instead
			substr($data, (index $data, $currentnick), (length $currentnick + 1)) = '';
		}
	}

	# Does the data contain my nick?
	my $nicklen = length $my_nick;
	my $nickindex = index $data, $my_nick;
	if ($nickindex >= 0 && $skip_oraakkeli_but_learn == 0) {
		dp(__LINE__.": my nick found, index: $nickindex, nicklen: $nicklen");
		dp(__LINE__.' data before: '.$data);
		substr($data, $nickindex, ($nicklen+1)) = '';	# remove one character after nick also
		#$data = substr $data, ($nicklen +1);
		dp(__LINE__.' data after: '. $data);
		my $alldone = 0;
		my $uniq = $nick . '@' . $target;	# nick@#target

		# Do the right thing if the user is ignored
		if (exists $ignore->{$uniq} && $ignore->{$uniq} != 0) {
			# If the user has done time, release them
			if (time - $ignore->{$uniq} > $ignore_timeout) {
				$ignore->{$uniq} = 0;
				$flood->{$uniq}->{'time'} = time;
				$flood->{$uniq}->{'count'} = 0;
				irssi_log("Not ignoring $uniq any more. He has suffered enough.");
			} else {
				dp("test1666");
				# Otherwise ignore them
				return;
			}
		}

		# Prevent flooding if necessary
		if ($prevent_flood) {

			# Add the user to the flood counter if he's new
			if (!defined($flood->{$uniq})) {
				$flood->{$uniq} = {'time' => time, 'count' => 1};
				irssi_log("Added $uniq to flood table");

			# If the time has expired, just reset
			} elsif (time - $flood->{$uniq}->{'time'} > $ratio_seconds) {
				$flood->{$uniq}->{'time'} = time;
				$flood->{$uniq}->{'count'} = 1;
				irssi_log("Reset $uniq flood count");

			# Otherwise just add one to the count
			} else {
				$flood->{$uniq}->{'count'}++;
				irssi_log("$uniq has a flood count of ".$flood->{$uniq}->{'count'});

				# If the user has been too verbose, ignore them
				if ($flood->{$uniq}->{'count'} > $ratio_posts) {
					$ignore->{$uniq} = time;

					# Display a pithy message stating our ignorance
					my $msg = $ignores[rand(scalar @ignores)];
					$msg = sprintf $msg, $nick;
					$server->command("msg $target $msg");
					irssi_log("Ignoring $uniq for $ignore_timeout seconds");
					$alldone = 1;
				}
			}
		}

		# Do nothing if the user is repeating himself
		if (exists($lastwords->{$uniq}) && $lastwords->{$uniq} eq $data) {
			if (rand(100) < 20) {
				$server->command("msg $target $nick, Konnari juoksi yli järven.");
			}
			$alldone = 1;
		}

		# Store this for next time
		$lastwords->{$uniq} = $data;
		# If we've finished with this user prematurely, just stop
		return if $alldone == 1;

		my $output = return_reply($data);
		$output = replace_weird($output);
		$server->command("msg $target $nick, $output") if $output;

	} else {
		foreach my $line (@wordlist) {
			if ($data =~ /$line/ && $skip_oraakkeli_but_learn == 0) {
				my $output = return_reply($data);
				$server->command("msg $target $nick, $output") if $output;
				last;
			}
		}
		dp("test learn: ". $data);
		$megahal->learn($data, 0);
	}
}
sub replace_weird {
	my ($text, @rest) = @_;
	$text =~ s/Ã¤/ä/g;          # ä
	$text =~ s/Ã¶/ö/g;          # ö
	$text =~ s/Ã¥/å/g;          # å
	$text =~ s/õ/ä/g;           # ä
	$text =~ s/Õ/Ä/g;           # Ä
	$text =~ s/÷/ö/g;           # ö
	return $text;
}

sub populate_nicklist {
	my ($channel, $server, @rest) = @_;
	if ($channel ne $currentchan && $server->{chatnet} ne $currentnetwork) {
		$currentchan = $channel;
		$currentnetwork = $server->{chatnet};
		my @channels = Irssi::channels();
		foreach my $item (@channels) {
			next unless $item->{type} eq "CHANNEL";
			next unless $item->{name} eq $channel;
			next unless $item->{names_got};
			#dp("we got correct window and have some nicks there. server:");
			#dp($item->{server}->{chatnet});
			next unless $item->{server}->{chatnet} eq $server->{chatnet};
			#dp ("CHANNELI: ".$item->{name});
			#dp("channel:");
			#da($item);
			my @nicks = $item->nicks();
			@channelnicks = ();
			foreach my $newnick (@nicks) {
				push @channelnicks, $newnick->{nick};
			}
			return;
		}
	} else {
		#dp("same channel as previous..");
	}
}

sub return_reply {
	my ($data, @rest) = @_;
	my $output = $megahal->do_reply($data, 0);

	# experimental 2023-03-06
	Encode::from_to($output, $charset, 'utf8');

	$output = KaaosRadioClass::ktrim($output);
	# $output = KaaosRadioClass::replaceWeird($output);
	return $output;
}

# Learn from URL. Every line is used, so be careful.
sub learn_txt_file {
	my ($url, @rest) = @_;
	my $response = KaaosRadioClass::fetchUrl($url);
	if ($response ne '-1') {
		my @lines = split /\n/, $response;
		my $linecount = 0;

		foreach my $line (@lines) {
			dp(__LINE__.': Line nbr: '.$linecount.', Line: '.$line);
			Encode::from_to($line, 'utf-8', $charset);
			$megahal->learn($line, 0) if $line;
			$linecount++;
		}
		irssi_log("Learned $linecount items from $url.");
	} else {
		irssi_log("Didn't learn anything from $url.");
	}
}

# debug array
sub da {
	return unless $DEBUG;
	Irssi::print("$myname-debug array:");
	Irssi::print Dumper (@_);
}

# debug print line
sub dp {
	return unless $DEBUG;
	Irssi::print("$myname-debug: @_");
}


Irssi::signal_add("message public", \&public_responder);
# LAama1 2022-04-20 Irssi::signal_add("setup changed", \&load_settings);
Irssi::signal_add("setup reread", \&load_settings);
Irssi::command_bind('savebrain', \&save_brain, 'megahal2');
Irssi::command_bind('save', \&save_brain, 'megahal2');
Irssi::command_bind('resetbrain', \&reset_brain, 'megahal2');
Irssi::command_bind('megahal_learn_from_url','learn_txt_file', "megahal2");

Irssi::settings_add_str('MegaHAL', 'megahal_brain', '');
Irssi::settings_add_str('MegaHAL', 'megahal_channels', '');
Irssi::settings_add_bool('MegaHAL', 'megahal_antiflood', 1);
Irssi::settings_add_str('MegaHAL', 'megahal_flood_ratio', '1:2');
Irssi::settings_add_int('MegaHAL', 'megahal_ignore_timeout', '1');
dp("Loading settings next..");    # LAama1
Irssi::settings_set_str('megahal_brain', '/home/laama/.irssi/megahal/');
Irssi::print('');
load_settings();
