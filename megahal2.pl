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

use strict;
use Irssi;
use AI::MegaHAL;
use vars qw($VERSION %IRSSI);

# LAama1
use Data::Dumper;
use KaaosRadioClass;      # LAama1 8.11.2017

$VERSION = '0.23';
%IRSSI = (
    'authors' => 'Craig Andrews, LAama1',
    'contact' => 'craig@simplyspiffing.com',
    'name'    => 'MegaHAL Irssi - 2.0',
    'description' => 'Donut Monkies AI',
    'license' => 'GNU General Public License 3.0',
    'version' => $VERSION
);


# Intialise the AI
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
    'moikka',
    'tervehdys',
	'niinist',
);

my @ignorenicks = (
	'kaaosradio',
    'ryokas',

);

my $DEBUG = 0;                 # LAama1
my $myname = "megahal2.pl";    # LAama1

sub irssi_log {
    my $msg = shift;
    Irssi::print("MegaHAL:: $msg");
}

##
# Attempt to load the brain from the specified directory if it is
# not already loaded, or reset the brain to undef if no path supplied
##
sub populate_brain {
    my $brain = shift;
    dp($brain);
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
        # $megahal = AI::MegaHAL->new('Path' => './', 'Banner' => 0, 'Prompt' => 0, 'Wrap' => 0, 'AutoSave' => 0);
        $megahal = new AI::MegaHAL(
            'Path' => $brain,
            'AutoSave' => 1);
    }
    Irssi::print("$myname: Brain populated..");      # LAama1

}

##
# Save the contents of the brain to megahal.brn
##
sub savebrain {
    my ($data, $server, $witem) = @_;

    $megahal->_cleanup();
    Irssi::print("$myname: Brains saved, probably");
}

##
# Load the settings from the irssi configuration
##
sub load_settings() {
    my $brain = Irssi::settings_get_str('megahal_brain');

    # Create the megahal object
    if (length $brain) {
        dp("Populate brain next..");      # LAama1
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
            irssi_log("Not enabling flood protection until flood ratio and ignore timeout are set");
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
    return $megahal if grep {/^$target$/} @valid_targets;
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

    my $line = "";
    my $syllables = 0;
    my $i = 10;
    while ($count > $syllables && scalar(@{$words}) > 0 && $i > 0)
    {
        $i--;
        $line .= shift @{$words};
        $line .= " ";
        #my @s = $line=~/([aeiouy]+)/gi;
        my @s = $line=~/([aeiouyöäå]+)/gi;  # LAama added öäå
        $syllables = scalar(@s);
    }
    return $line;
}

sub give_me_a_haiku {
    my ($megahal, $server, $data, $nick, $mask, $target) = @_;

    my $string = $megahal->do_reply($data, 0);
    $string .= ' ';
    $string .= $megahal->do_reply($string, 0);
    $string .= ' ';
    $string .= $megahal->do_reply($string, 0);

    my @words = $string=~/\S+/g;

    my @haiku;
    push @haiku, get_haiku_line(\@words, 5);
    push @haiku, get_haiku_line(\@words, 7);
    push @haiku, get_haiku_line(\@words, 5);

    $server->command("msg $target -!- ". KaaosRadioClass::replaceWeird($_)) for @haiku;
}


##
# Public Responder
# The bulk of the work goes on in here, including flood and repeat
# protection, learning and reply generation. It's not as scary as it looks
##
sub public_responder {
    my ($server, $data, $nick, $mask, $target) = @_;

    my $my_nick = $server->{'nick'};
    my $skip_oraakkeli_but_learn = 0;   #if oraakkeli.pl script enabled this is a fix.
	return if $nick ~~ @ignorenicks;
    return if $data =~ /kaaos/i;
    # Ignore lines containing URLs or !commands other than !haiku
    return if $data =~ /https?:\/\//i || $data =~ /www\./i || $data =~ /^\![^haiku]/;
    
    $skip_oraakkeli_but_learn = ($data =~ /$my_nick/i && $data =~ /(.*)\?/);    # LAama1, oraakkeli parseri.

	dp("$myname: Giving to Oraakkeli..") if $skip_oraakkeli_but_learn;
    
	# Don't talk to yourself
    return if $nick =~ /$my_nick/;
    
    # Get the megahal instance for this channel
    my $megahal = get_megahal($target);
    return unless defined $megahal;

	# replace weird characters from user input
    $data = KaaosRadioClass::replaceWeird($data);
    
	# If all the user wants is a haiku, just do it
    if ($data =~ /^!haiku/ && $skip_oraakkeli_but_learn == 0) {
        if (KaaosRadioClass::floodCheck(5) > 0) {
            Irssi::print("$myname: Haiku flood detected ($nick)");
            return;
        }
        $data =~ s/\!haiku *//;
        Irssi::print("$myname: !haiku search word: $data");
        give_me_a_haiku($megahal, $server, $data, $nick, $mask, $target);
        return;
    }
    return if $data =~ /^!/;    # if !command

    # Does the data contain my nick?
    my $referencesme = $data =~ /$my_nick/i;

    if ($referencesme && $skip_oraakkeli_but_learn == 0) {
        my $alldone = 0;
        my $uniq = $nick . "@" . $target;

        # Do the right thing if the user is ignored
        if (exists($ignore->{$uniq}) && $ignore->{$uniq} != 0) {

            # If the user has done time, release them
            if (time() - $ignore->{$uniq} > $ignore_timeout) {

                $ignore->{$uniq} = 0;
                $flood->{$uniq}->{'time'} = time();
                $flood->{$uniq}->{'count'} = 0;
                irssi_log("Not ignoring $uniq any more");

            # Otherwise ignore them
            } else {
                return;
            }
        }

        # Prevent flooding if necessary
        if ($prevent_flood) {

            # Add the user to the flood counter if he's new
            if (!defined($flood->{$uniq})) {
                $flood->{$uniq} = {'time' => time(), 'count' => 1};
                irssi_log("Added $uniq to flood table");

            # If the time has expired, just reset
            } elsif (time() - $flood->{$uniq}->{'time'} > $ratio_seconds) {
                $flood->{$uniq}->{'time'} = time();
                $flood->{$uniq}->{'count'} = 1;

                irssi_log("Reset $uniq flood count");

            # Otherwise just add one to the count
            } else {
                $flood->{$uniq}->{'count'}++;
                irssi_log("$uniq has a flood count of ".$flood->{$uniq}->{'count'});

                # If the user has been too verbose, ignore them
                if ($flood->{$uniq}->{'count'} > $ratio_posts) {

                    $ignore->{$uniq} = time();

                    # Display a pithy message stating our ignorance
                    my $msg = $ignores[rand(scalar(@ignores))];
                    $msg = sprintf($msg, $nick);
                    $server->command("msg $target $msg");
                    irssi_log("Ignoring $uniq for $ignore_timeout seconds");

                    $alldone = 1;
                }
            }
        }

        # Do nothing if the user is repeating himself
        if (exists($lastwords->{$uniq}) && $lastwords->{$uniq} eq $data) {
            if (rand(100) < 20) {
                $server->command("msg $target $nick, Konnari juoksi yli järven, $nick.");
            }
            $alldone = 1;
        }

        # Store this for next time
        $lastwords->{$uniq} = $data;

        # If we've finished with this user prematurely, just stop
        return if $alldone == 1;

        $data =~ s/^$my_nick\S?//;
		my $output = return_reply($data);
        #my $output = $megahal->do_reply($data, 0);
        #$output =~ s/  */ /g;		# replace multiple spaces
        #$output =~ s/^ *//g;		# replace spaces from beginning
        #$output = KaaosRadioClass::replaceWeird($output);
        #$output = "$nick: $output" if $referencesme;
        
        $server->command("msg $target $nick, $output");

    } else {
		$data =~ s/^$my_nick\S?//;
		foreach my $line (@wordlist) {
			if ($data =~ /$line/ && $skip_oraakkeli_but_learn == 0) {
        		my $output = return_reply($data);
        		$server->command("msg $target $nick, $output");		
                last;		
			}
		}

        Irssi::print("$myname: Learned something.. nick: $nick, data: $data") if $DEBUG;
        $data =~ s/^\S+[\:,]\s*//;
        $megahal->learn($data, 0);
        
    }
}

sub return_reply {
	my ($data, @rest) = @_;
	my $output = $megahal->do_reply($data, 0);
	$output =~ s/  */ /g;		# replace multiple spaces
	$output =~ s/^ *//g;		# replace spaces from beginning
	$output = KaaosRadioClass::replaceWeird($output);
	return $output;
}

# Learn from URL. Every line is used, so be careful.
sub learn_txt_file {
	my ($url, @rest) = @_;
	
	#my $response = $ua->get($url);
    my $response = KaaosRadioClass::fetchUrl($url);
    if ($response ne "-1") {
        #my $page = $response->decoded_content(charset => 'none');
        my @lines = split (/\n/, $response);

        foreach my $line (@lines) {
            dp("Line: ".$line);
            $megahal->learn($line, 0) if $line;
        }

        Irssi::print("$myname: Learned ok.");
    } else {
        Irssi::print("$myname: Didn't learn anything..");
    }

}

sub da {
	return unless $DEBUG;
	Irssi::print("$myname-debug array:");
	Irssi::print Dumper (@_);
}

sub dp {
    return unless $DEBUG;
    Irssi::print("$myname-debug: @_");
    #Irssi::print("@_");
}

Irssi::command_bind('megahal_learn_from_url','learn_txt_file', "MegaHAL commands");


Irssi::signal_add("message public", \&public_responder);
Irssi::signal_add("setup changed", \&load_settings);
Irssi::signal_add("setup reread", \&load_settings);
Irssi::command_bind('savebrain', \&savebrain);
Irssi::command_bind('save', \&savebrain);


Irssi::settings_add_str('MegaHAL', 'megahal_brain', '');

Irssi::settings_add_str('MegaHAL', 'megahal_channels', '');
Irssi::settings_add_bool('MegaHAL', 'megahal_antiflood', '');
Irssi::settings_add_str('MegaHAL', 'megahal_flood_ratio', '');
Irssi::settings_add_int('MegaHAL', 'megahal_ignore_timeout', '1');
dp("Loading settings next..");    # LAama1
#Irssi::settings_set_str('megahal_brain', '/home/laama/.cpan/build/AI-MegaHAL-0.08-TSMTQK/');
Irssi::settings_set_str('megahal_brain', '/home/laama/.irssi/scripts/');
dp(Irssi::settings_get_str('megahal_brain'));
Irssi::print("");
load_settings();
