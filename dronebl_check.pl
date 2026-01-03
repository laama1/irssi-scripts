use strict;
use warnings;
use Irssi;
use Data::Dumper;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;
use Net::DNS;
use POSIX qw(strftime);

use vars qw($VERSION %IRSSI);
$VERSION = '0.2';
%IRSSI = (
    authors	=> 'LAama1',
    contact	=> '#kaaosradio.fi@IRCNet',
    name	=> 'dronecheck',
    description	=> 'Check if somebody joined the channel from an open proxy.',
    license	=> 'BSD',
    changed	=> '2025-12-29',
    url		=> 'http://www.kaaosradio.fi'
);

my $dronebl_address = 'https://';
my $statsfile = Irssi::get_irssi_dir() . '/scripts/dronebl.log';
my $scriptfile = Irssi::get_irssi_dir() . '/scripts/checkdnsbl.sh';
my $ipinfo_script = Irssi::get_irssi_dir() . '/scripts/irssi-scripts/python/ip_info.py';
my $nicks = {};

# TODO: 
# - add stats-command
# - add option to auto-kick users found in dronebl
# - close channel when too many proxy users join

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
    chomp(my $data = `${scriptfile} ${ip}`);

    if ($data) {
        Irssi::active_win()->print("data from checkdns script for ip $ip: ");
        Irssi::active_win()->print(Dumper $data);
    } else {
        Irssi::active_win()->print("No data from checkdns script for ip: " . $ip);
    }
    Irssi::active_win()->print("------ end of dronebl check ------") if $DEBUG;

    return $data;
}

# when a user joined your channel
sub event_msg_joined {
    my ($server, $channel, $nick, $address, $account, $realname) = @_;
    create_window('dronebl_check');
    prind("User joined channel signal received: " . $channel . " $nick, address: $address");
    my @ip_parts = split '@', $address;
    $server->send_raw("whois $nick");

    my $host = $ip_parts[1];
    my $ident = $ip_parts[0];
    my $converted_ip = '';
    # TODO: if ident has hex chars only, then it is probably a cloaked ident
    if (is_hex_ident($ident)) {
        $converted_ip = is_hex_ident($ident);
        prindd(__LINE__ . " converted ip from hex ident: " . $converted_ip) if $DEBUG;
        #if ($converted_ip ne 0) {
        #    $ident = $converted_ip;
        #}
    }

    if (is_ipaddress($host) > 0) {
        dronebl_check($host);
    } elsif (is_ipaddress($converted_ip) > 0) {
        dronebl_check($converted_ip);
    } else {
        # do reverse dns here if needed
        $converted_ip = do_resolve($host);
        if ($converted_ip ne '') {
            dronebl_check($converted_ip);
        }
    }
    Irssi::active_win()->print("User joined channel: " . $channel . ", nick: $nick, ident: $ident, host: $host, full address: $address, converted ip: " . $converted_ip);
    save_stuff($nick, $ident, $host, $converted_ip);
}

sub is_hex_ident {
    my ($ident, @rest) = @_;
    if ($ident =~ /^[0-9a-fA-F]{8}+$/) {
        prind(__LINE__ . " hex ident detected: " . $ident) if $DEBUG;
        my @bytes = ($ident =~ /../g);
        prind(__LINE__ . " bytes: " . Dumper \@bytes) if $DEBUG;
        my @decimals = map { hex($_) } @bytes;
        prind(__LINE__ . " decimals: " . Dumper \@decimals) if $DEBUG;
        my $ip = join('.', @decimals);
        prind(__LINE__ . " converted ip: " . $ip) if $DEBUG;
        return $ip;
        #return 1;
    }
    return 0;
}

sub event_whois {
    my ($server, $data, $srv_addr, @rest) = @_;
    my ($me, $nick, $user, $host, $something) = split(" ", $data);

    Irssi::active_win()->print("Nick: $nick, user: $user, host: $host, server address: $srv_addr, something: $something");
    #Irssi::active_win()->print(Dumper \@rest);
}

sub do_the_kick {
    my ($server, $chan, $nick, @rest) = @_;
}

# check if given string is ipaddress. if not, do reverse dns to get ip
sub is_ipaddress {
    my ($value, @rest) = @_;
    if ($value =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/) {
        prind(__LINE__ . " ipv4 address detected: " . $value) if $DEBUG;
        return 1;
    }
    # check if it is ipv6
    if ($value =~ /^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$/) {
        prind(__LINE__ . " ipv6 address detected: " . $value) if $DEBUG;
        return 1;
    }
    if ($value =~ /^[0-9a-fA-F]{8}$/) {
        my $converted_ip = is_hex_ident($value);
        if ($converted_ip ne 0) {
            prind(__LINE__ . " converted hex ident to ip: " . $converted_ip) if $DEBUG;
            return 1;
        }
    }

    if ($value =~ /[0-9a-fA-F]{8}/) {
        my $converted_ip2 = is_hex_ident($value);
        if ($converted_ip2 ne 0) {
            prind(__LINE__ . " found hex from the middle part: " . $converted_ip2) if $DEBUG;
            return 1;
        }
    }

    # do reverse dns here if needed
    #my @data = rr($value);
    #prind(__LINE__ . ': ' . Dumper \@data) if $DEBUG;
    prind(__LINE__ . " not an ip address: " . $value) if $DEBUG;
    return 0;
}

# resolve host and return first A or AAAA record found
sub do_resolve {
    my ($host, @rest) = @_;
    my $res = Net::DNS::Resolver->new;
    my $query = $res->search($host);

    if ($query) {
        foreach my $rr ($query->answer) {
            next unless ($rr->type eq "A" or $rr->type eq "AAAA");
            prind("address: " . $rr->address) if $DEBUG;
            return $rr->address;
        }
    } else {
        warn "Query failed: ", $res->errorstring, "\n";
    }
    return '';
}

sub save_stuff {
    my ($nick, $ident, $ip, $converted_ip, @channels) = @_;
    my $iso_time = strftime("%Y-%m-%dT%H:%M:%S%z", localtime);
    Irssi::active_win()->print("Saving to file $statsfile: $nick, $ident, $ip");
    KaaosRadioClass::addLineToFile($statsfile, $iso_time . ';' . $nick . ';' . $ident . ';' . $ip . ';' . $converted_ip . ';');
}

sub add_enabled_channel_command {
	my ($text, $server, $channel, @rest) = @_;
    #if (not defined $channel or $channel == '') {
    #    prindw("No channel context found. Change to a channel window first.");
    #    return -1;
    #}
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

Irssi::command_bind('dronebl_add_channel', \&add_enabled_channel_command, 'dronebl_check');
Irssi::command_bind('dronebl_remove_channel', \&remove_enabled_channel_command, 'dronebl_check');