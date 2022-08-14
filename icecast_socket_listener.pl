use strict;
use IO::Socket;
use Fcntl;
use Irssi;
# install next one: 
use Time::Format qw(%strftime);
use Data::Dumper;
use KaaosRadioClass;

use vars qw($VERSION %IRSSI);

$VERSION = '0.1';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'LAama1@ircnet',
	name        => 'Icecast socket listener',
	description => 'provides an interface to irssi via unix sockets',
	license     => 'BSD',
	url         => 'http://8-b.fi',
	changed     => '2022-03-04',
);

my $socket = "/tmp/irssi_icecast.sock";
my $DEBUG = 1;
my $timer = '';
# create the socket
unlink $socket;
my $server = IO::Socket::UNIX->new(Local  => $socket,
								   Type   => SOCK_STREAM,
								   Listen => 5) or die $@;

# set this socket as nonblocking so we can check stuff without interrupting
# irssi.
nonblock($server);

# method to set a socket handle as nonblocking
sub nonblock {
	my($fd) = @_;
	my $flags = fcntl($fd, F_GETFL, 0);
	fcntl($fd, F_SETFL, $flags | O_NONBLOCK);
}

sub msg_to_channel {
	my ($tag, $target, $note, @rest) = @_;
	#dp("i here.. tag: $tag, target: $target, nick: $nick, note: $note");

	my @windows = Irssi::windows();
	foreach my $window (@windows) {

		next if $window->{name} eq '(status)';
		next unless $window->{active}->{type} eq 'CHANNEL';
		if($window->{active}->{name} eq $target && $window->{active_server}->{tag} eq $tag) {
			dp("Found! $window->{active}->{name}");
			$window->{active_server}->command("msg $window->{active}->{name} $note");
		}
	}
	return;
}

# check the socket for data and act upon it
sub check_sock_icecast {
	my $msg;
	if (my $client = $server->accept()) {
		$client->recv($msg, 1024);
		echota("Got message from socket: $msg") if $msg;
		if ($msg =~ /(.*?)$/) {
			my $data = $1;
            my $channel = "#salamolo";
            my $tag = "nerv";
			echota("Tag: $tag, Channel: $channel, data: $data");
			msg_to_channel($tag, $channel, $data);
		}
	}
}

sub parse_mesg {
	my ($mesg, @rest) = @_;
}

sub echota {
	my ($msg, @rest) = @_;
	print("%G".$IRSSI{name}.">%n ".$msg);
}

sub dp {
	return unless $DEBUG == 1;
	print("%R".$IRSSI{name}." debug >%n @_");
	return;
}

sub da {
	return unless $DEBUG == 1;
	print("%R".$IRSSI{name}." debug>%n ");
	print(Dumper(@_));
	return;
}
sub UNLOAD {
	unlink $socket;
}
my $timer = Irssi::timeout_add(250, \&check_sock_icecast, []);

#Irssi::signal_add('message public', 'event_pubmsg');
#Irssi::signal_add('message private', 'event_privmsg');
