use strict;
use warnings;
use Irssi;
use Data::Dumper;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;
use Net::DNS;

use vars qw($VERSION %IRSSI);
$VERSION = '0.1';
%IRSSI = (
    authors	=> 'LAama1',
    contact	=> '#kaaosradio.fi@ircnet',
    name	=> 'dronecheck',
    description	=> 'Check if somebody joined the channel from a open proxy.',
    license	=> 'BSD',
    changed	=> '2023-01-28',
    url		=> 'http://www.kaaosradio.fi'
);

my $dronebl_address = 'https://';
my $statsfile = Irssi::get_irssi_dir().'/scripts/dronebl.log';
my $scriptfile = Irssi::get_irssi_dir().'/scripts/checkdnsbl.sh';
my $ipinfo_script = Irssi::get_irssi_dir().'/scripts/irssi-scripts/python/ip_info.py';
my $nicks = {};

my $DEBUG = 1;

sub sig_msg_pub {
    my ($server, $msg, $nick, $address, $target) = @_;
    return unless KaaosRadioClass::is_enabled_channel('dronebl_check_enabled_channels', $server->{chatnet}, $target);
    my ($data1, $data2) = ('', '');
    if ($msg =~ /^!ip (.*)$/) {
        create_window('dronebl_check');
        my $ip = $1;
        my $data1 = dronebl_check($ip);
        my $data2 = ip_info($ip);
        if ($data1 ne '') {
            $server->command("msg $target DroneBL check for $ip: $data1");
        }
        if ($data2 ne '') {
            $server->command("msg $target GeoLite2 info for $ip: $data2");
        }
    }
}

sub create_window {
    my ($window_name) = @_;
    my $window = Irssi::window_find_name($window_name);
    unless ($window) {
        prind("Create new window: $window_name");
        Irssi::command("window new hidden");
        Irssi::command("window name $window_name");
		#debu("Window created: " . Irssi::active_win()->{name});
    }
    Irssi::command("window goto $window_name");
}

# fetch info from ip_info.py script
sub ip_info {
    my ($ip, @rest) = @_;
    chomp(my $data = `${ipinfo_script} ${ip}`);

    Irssi::active_win()->print("data from ip_info script:");
    Irssi::active_win()->print($data);
    return $data;
}

# when you join a channel
sub event_chan_joined {
    my ($channel, @rest) = @_;
    print "Jes. i joined: ";
    #print Dumper $channel;
    print "--------------";
    #print Dumper @rest ;
    return;

}

sub dronebl_check {
    my ($ip, @rest) = @_;
    my $data = `${scriptfile} ${ip}`;

    Irssi::active_win()->print("data from script:");
    Irssi::active_win()->print(Dumper $data);
    return $data;
}

# when user joined your channel
sub event_msg_joined {
    my ($server, $channel, $nick, $address, $account, $realname) = @_;
    #my @ip_parts = split '\@', $address;
    create_window('dronebl_check');
    my @ip_parts = split '@', $address;
    $server->send_raw("whois $nick");

    my $host = $ip_parts[1];
    my $ident = $ip_parts[0];
    is_ipaddress($host);
    Irssi::active_win()->print("Got nick: $nick, ident: $ident, host: $host");
    save_stuff($nick, $ident, $host);
    dronebl_check($host);
    #save_stuff($nick, $ident, $host);
}

sub event_whois {
    my ($server, $data, $srv_addr, @rest) = @_;
    my ($me, $nick, $user, $host, $something) = split(" ", $data);

    Irssi::active_win()->print("Nick: $nick, user: $user, host: $host, server address: $srv_addr, something: $something");
    Irssi::active_win()->print(Dumper \@rest);
}

sub do_the_kick {
    my ($server, $chan, $nick, @rest) = @_;
}

# check if given string is ipaddress. if not, do reverse dns to get ip
sub is_ipaddress {
    my ($value, @rest) = @_;
    if ($value =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/) {
        print "ipv4 address detected: " . $value if $DEBUG;
        return 1;
    }
    # check if it is ipv6
    if ($value =~ /^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$/) {
        print "ipv6 address detected: " . $value if $DEBUG;
        return 1;
    }
    # do reverse dns here if needed
    my $data = rr($value);
    print Dumper $data;
    return 0;
}

sub save_stuff {
    my ($nick, $ident, $ip, @channels) = @_;
    Irssi::active_win()->print("Saving: $nick, $ident, $ip");
    KaaosRadioClass::addLineToFile($statsfile, time.';'.$nick. ';'. $ident.';'.$ip.';');
}

sub add_enabled_channel_command {
	my ($text, $server, $channel, @rest) = @_;
	prind('Add channel: text: ' . $text . ', server tag: ' . $server->{tag} . ', server chatnet: ' . $server->{chatnet} . ', channel: ' . $channel->{name});
	my $rv = KaaosRadioClass::add_enabled_channel('dronebl_check_enabled_channels', $server->{chatnet}, $channel->{name});
	prind("Enabled channels: " . Irssi::settings_get_str('dronebl_check_enabled_channels'));
	return 0;
}

sub remove_enabled_channel_command {
	my ($text, $server, $channel, @rest) = @_;
	prind('Remove channel: text: ' . $text . ', server tag: ' . $server->{tag} . ', server chatnet: ' . $server->{chatnet} . ', channel: ' . $channel->{name});
	my $network = $server->{chatnet};
	my $channel_name = $channel->{name};
	my $rv = KaaosRadioClass::remove_enabled_channel('dronebl_check_enabled_channels', $network, $channel_name);

	prind("Channel $channel_name\@$network removed from enabled channels.");
	prind("Enabled channels: " . Irssi::settings_get_str('dronebl_check_enabled_channels'));
	return 1;
}

sub prind {
	my ($text, @test) = @_;
	print("\00312" . $IRSSI{name} . ">\003 ". $text);
}

sub prindw {
	my ($text, @test) = @_;
	print("\0034" . $IRSSI{name} . " warning>\003 ". $text);
}

Irssi::settings_add_str('dronebl_check', 'dronebl_check_enabled_channels', '');
Irssi::signal_add('channel joined', 'event_chan_joined');
Irssi::signal_add('message join', 'event_msg_joined');
Irssi::signal_add_first('event 311', 'event_whois');
Irssi::signal_add('message public', 'sig_msg_pub');

Irssi::command_bind('dronbel_add_channel', \&add_enabled_channel_command, 'dronebl_check');
Irssi::command_bind('dronebl_remove_channel', \&remove_enabled_channel_command, 'dronebl_check');