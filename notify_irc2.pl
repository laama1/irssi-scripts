use warnings;
use strict;
use Irssi;
use utf8;
use KaaosRadioClass;
#use IO::Socket;
use Socket;
#use Fcntl;

use vars qw($VERSION %IRSSI);
$VERSION = "0.2";
%IRSSI = (
	authors	=> 'laama',
	contact	=> 'kaaosradio ircnet',
	name	=> 'notify_irc',
	description	=> 'Skripti lukee sock-tiedostoa tai porttia ja ilmoittaa irciin jos jotain kivaa tapahtuu',
	license	=> 'BSD',
	changed	=> '2023-03-08',
	url		=> 'https://www.kaaosradio.fi'
);

my $DEBUG = 1;
my $lastmesg = '';

my $kaaos_server;
my $handle = undef;


start_server();
sub start_server {
	Irssi::print("KAaosd> starting...");
  	$kaaos_server = IO::Socket::INET->new( Proto => 'tcp', LocalAddr => '127.0.0.1' , LocalPort => 12347, Listen => SOMAXCONN, ReusePort => 1) 
		or Irssi::print "KAaosd> Can't bind to port 12347, $@";
  	if(!$kaaos_server) {
    	Irssi::print("KAaosd> couldn't start server, $@", MSGLEVEL_CLIENTERROR);
    	return;
  	}

  Irssi::print(sprintf("KAaosd> waiting for socket connections on %s:%s...", $kaaos_server->sockhost, $kaaos_server->sockport));
  $handle = Irssi::input_add($kaaos_server->fileno, INPUT_READ, 'handle_connection', $kaaos_server);
}

sub handle_connection {
	my $sock = $_[0]->accept;
  	my $iaddr = inet_aton($sock->peerhost); 	# or whatever address
  	my $peer  = gethostbyaddr($iaddr, AF_INET); # $sock->peerhost;
	print("KAaosd> handling connection from $peer");

	my $incoming = <$sock>;
	$sock->autoflush(1);
	$incoming = KaaosRadioClass::ktrim($incoming);
	print("KAaosd> got: $incoming, parse it next.");
	parse_msg($incoming);
}

# check the socket for data and act upon it
sub parse_msg {
	my ($msg, @rest) = @_;
	#DP("Got message from socket: $msg") if $msg;
	if ($msg =~ /nytsoivideo (.*)$/ && $msg ne $lastmesg) {
		DP("Joku päivitti videostreamin metan: $1");
		Irssi::signal_emit('krnytsoivideo-remote-msg', $msg, $1);
	} elsif ($msg =~ /nytsoivideotwitch (.*)$/ && $msg ne $lastmesg) {
		DP("Joku päivitti twitch-tiedon: $1");
		Irssi::signal_emit('krnytsoivideotwitch-remote-msg', $msg, $1);
	} elsif ($msg =~ /nytsoi (.*)$/ && $msg ne $lastmesg) {
		DP("Joku päivitti icecastin: $1");
		Irssi::signal_emit('krnytsoi-remote-msg', $msg, $1);
	} elsif ($msg =~ /^icecast (.*)$/) {
		# TODO
		$msg = $msg;
	}
	$lastmesg = $msg;
}

sub DP {
	return unless $DEBUG == 1;
	print($IRSSI{name}." debug> @_");
	return;
}

my $signal_config_hash1 = { 'krnytsoi-remote-msg' => [ qw/iobject string/ ] };
Irssi::signal_register($signal_config_hash1);

my $signal_config_hash2 = { 'krnytsoivideo-remote-msg' => [ qw/iobject string/ ] };
Irssi::signal_register($signal_config_hash2);

my $signal_config_hash3 = { 'krnytsoivideotwitch-remote-msg' => [ qw/iobject string/ ] };
Irssi::signal_register($signal_config_hash3);

print($IRSSI{name}."> v. $VERSION Loaded!");
