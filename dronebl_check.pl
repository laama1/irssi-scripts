use strict;
use warnings;
use Irssi;
use Data::Dumper;
use KaaosRadioClass;


use vars qw($VERSION %IRSSI);
$VERSION = '0.1';
%IRSSI = (
    authors	=> 'LAama1',
    contact	=> '#kaaosradio.fi@ircnet',
    name	=> 'dronecheck',
    description	=> 'Check if somebody joined the channel from open proxy.',
    license	=> 'BSD',
    changed	=> '2023-01-28',
    url		=> 'http://www.kaaosradio.fi'
);

my $dronebl_address = 'https://';
my $statsfile = Irssi::get_irssi_dir().'/scripts/dronebl.log';
my $scriptfile = Irssi::get_irssi_dir().'/scripts/checkdnsbl.sh';

# when you join a channel
sub event_chan_joined {
    my ($channel, @rest) = @_;
    print "Jes. i joined: ";
    print Dumper $channel;
    print "--------------";
    print Dumper @rest ;

}

sub dronebl_check {
    my ($ip, @rest) = @_;
    my $data = `${scriptfile} ${ip}`;

    print("data from script:");
    print Dumper $data;
}

# when user joined your channel
sub event_msg_joined {
    my ($server, $channel, $nick, $address, $account, $realname) = @_;
    #my @ip_parts = split '\@', $address;
    my @ip_parts = split '@', $address;
    $server->send_raw("whois $nick");

    my $host = $ip_parts[1];
    my $ident = $ip_parts[0];
    print "Got nick: $nick, ident: $ident, host: $host";
    save_stuff($nick, $ident, $host);
    dronebl_check($host);
    #save_stuff($nick, $ident, $host);
}

sub event_whois {
    my ($server, $data, $srv_addr, @rest) = @_;
    my ($me, $nick, $user, $host) = split(" ", $data);
    #my $network = $server->{tag};
    
    #$nick = fc $nick;
    print("Nick: $nick, me: $me, user: $user, host: $host, server address: $srv_addr");
    print Dumper @rest;
}

sub do_the_kick {
    my ($server, $chan, $nick, @rest) = @_;
}

sub save_stuff {
    my ($nick, $ident, $ip, @channels) = @_;
    print("Saving: $nick, $ident, $ip");
    KaaosRadioClass::addLineToFile($statsfile, time.';'.$nick. ';'. $ident.';'.$ip.';');
}

Irssi::signal_add('channel joined', 'event_chan_joined');
Irssi::signal_add('message join', 'event_msg_joined');
Irssi::signal_add_first('event 311', 'event_whois');
