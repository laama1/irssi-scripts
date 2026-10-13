use Irssi;
use strict;
use Data::Dumper;
use vars qw($VERSION %IRSSI);

$VERSION="0.3.1";
%IRSSI = (
	authors => 'LAama1',
	contact => 'laama+irssi@8u.fi',
	name => 'timesum',
	description => 'Tell time',
	sbitems => 'timesum',
	license => 'GPL v2 or later',
	url => 'https://8-b.fi',
);

# remove normal clock from irssi statusbar:
# /STATUSBAR REMOVEITEM time window
# add this item to irssi statusbar:
# /STATUSBAR ADDITEM -priority 101 -before user timesum window

my $sbitem;

sub check_message {
    my ($server, $msg, $nick, $address, $channeli ) = @_;

	my $mynick = quotemeta $server->{nick};
	return if ($nick eq $mynick);   #self-test

    if ($msg eq '!time') {
        my $hour = (localtime)[2];
        my $min = (localtime)[1];

        prind(" $hour + $min = " . ($hour + $min) );
        $server->command("msg $channeli $hour + $min = " . ($hour + $min) );
        check_time();	# check if it's time to send a special message after responding to !time command
    }
}

sub check_time {
    my $hour = (localtime)[2];
    my $min = (localtime)[1];

    if (
        ($hour + $min == 60) || 
        ($hour + $min == 69)
    ) {
        msg_time_channels($hour, $min);
    }

    #prind(" $hour + $min = " . ($hour + $min) );
    if (($hour == 4 || $hour == 16) && $min == 20) {
        msg_channels("It's 4:20! Blaze it! 🔥🔥🔥");
    }
    if (($hour == 4 || $hour == 16) && $min == 21) {
        msg_channels("It's 4:21! You missed it! 💨💨💨");
    }
    if (($hour == 4 || $hour == 16) && $min == 22) {
        msg_channels("It's 4:22! Too late! 😵‍💫😵‍💫😵‍💫");
    }
    if (($hour == 4 || $hour == 16) && $min == 23) {
        msg_channels("It's 4:23! Why are you still here? 🚪🚪🚪");
    }

    if ($hour == 1 && $min == 23) {
        msg_channels("It's 01:23! Time to sleep! 😴😴😴 and sequential time! 🔢🔢🔢");
    }
    # if number 1,2,3,4 all exist on some order in the time, it's sequential time
    if (
        ($hour == 1 && $min == 23) || 
        ($hour == 12 && $min == 34) || 
        ($hour == 12 && $min == 43) || 
        ($hour == 13 && $min == 42) || 
        ($hour == 13 && $min == 24) || 
        ($hour == 14 && $min == 23) || 
        ($hour == 14 && $min == 32) || 
        ($hour == 23 && $min == 45) || 
        ($hour == 23 && $min == 54) || 
        ($hour == 23 && $min == 14) ||
        ($hour == 23 && $min == 41)
    ) {
        msg_channels("It's $hour:$min sequential time! 🔢🔢🔢");
    }

    if ($hour == 23 && $min == 58) {
        msg_channels("It's 23:58! Two minutes to midnight! 🌑🌑🌑");
    }
    if ($hour == 4 && $min == 44) {
        msg_channels("It's 04:44! Spooky time! 👻👻👻");
    }
    if ($hour == 16 && $min == 16) {
        msg_channels("It's 16:16! Sweet sixteen! 🎂🎂🎂");
    }
    if ($hour == 15 && $min == 15) {
        msg_channels("It's 15:15! Sweet fifteen! 🎂🎂🎂");
    }
    if ($hour == 12 && $min == 12) {
        msg_channels("It's 12:12! Dozen time! 🎂🎂🎂");
    }

    if ($hour == 20 && $min == 20) {
        msg_channels("It's 20:20! Perfect vision! 👓👓👓");
    }
    if (($hour == 4 && $min == 32) ||
        ($hour == 3 && $min == 21) ||
        ($hour == 2 && $min == 34) ||
        ($hour == 2 && $min == 10) ||
        ($hour == 5 && $min == 43) ||
        ($hour == 6 && $min == 54)
    ) {
        msg_channels("It's $hour:$min! Time to check the clock! 🕰️🕰️🕰️");
    }

    if ($hour == 0 && $min == 0) {
        msg_channels("It's midnight! 🌑🌑🌑");
    }
    if ($hour == 0 && $min == 4) {
        msg_channels("It's 00:04! Still midnight! 🌑🌑🌑");
    }
}

sub sb_timesum_init {
    my ($item, $get_size_only) = @_;
    my $hour = (localtime)[2];
    my $min = (localtime)[1];
	$sbitem = "{sb ${hour}+${min}=" . ($hour + $min) . "}";
    $item->default_handler($get_size_only, $sbitem, undef, 1);
}

sub sb_timesum {
    my ($item, $get_size_only) = @_;
    my $hour = (localtime)[2];
    my $min = (localtime)[1];
	$sbitem = "{sb ${hour}+${min}=" . ($hour + $min) . "}";
    refresh_sb();
}

sub msg_time_channels {
    msg_channels("$_[0]+$_[1]=" . ($_[0]+$_[1]) . " 🕰️🕰️🕰️");
}

sub msg_channels {
    # msg to every channel window
    my ($text) = @_;

    my @windows = Irssi::windows();
    foreach my $window (@windows) {
        next if $window->{name} eq '(status)';
        if (defined $window->{active}->{type} && $window->{active}->{type} eq 'CHANNEL') {
            $window->{active_server}->command("msg $window->{active}->{name} $text");
        }
    }
    return;
}

sub refresh_sb {
    Irssi::statusbar_items_redraw('timesum');
}

# print to irssi status window
sub prind {
	my ($text, @test) = @_;
	print("\0038" . $IRSSI{name} . ">\003 ". $text);
}

# print warning to irssi status window
sub prindw {
	my ($text, @test) = @_;
	print("\0034" . $IRSSI{name} . " warning>\003 ". $text);
}

#my $refresh_tag = Irssi::timeout_add(60*1000, 'check_time', undef);
my $refresh_tag2 = Irssi::timeout_add(60*1000, 'sb_timesum', undef);

Irssi::command('^STATUSBAR REMOVEITEM time window');
Irssi::command('^STATUSBAR ADDITEM -priority 101 -before user timesum window');

Irssi::statusbar_item_register('timesum', undef, 'sb_timesum_init');
Irssi::statusbars_recreate_items();
Irssi::signal_add_last('message public', 'check_message' );
prind("loaded.");
