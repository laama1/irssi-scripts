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
	authors     => 'Matt "f0rked" Sparks, Miklos Vajna, LAama1',
	contact     => 'LAama1@ircnet',
	name        => 'muistuta',
	description => 'provides an interface to irssi via unix sockets',
	license     => 'GPLv2',
	url         => 'http://quadpoint.org',
	changed     => '2022-01-09',
);

my $socket = "/tmp/irssi.sock";
my $DEBUG = 1;
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
	my ($tag, $target, $nick, $note, @rest) = @_;
	dp("i here.. tag: $tag, target: $target, nick: $nick, note: $note");

	my @windows = Irssi::windows();
	foreach my $window (@windows) {

		next if $window->{name} eq '(status)';
		next unless $window->{active}->{type} eq 'CHANNEL';
		dp("i here.. again, name: ");
		#da($window);
		dp($window->{active}->{name}. ', '. $window->{active_server}->{tag});

		if($window->{active}->{name} eq $target && $window->{active_server}->{tag} eq $tag) {
			dp("Found! $window->{active}->{name}");
			$window->{active_server}->command("msg $window->{active}->{name} $nick, muistathan.. $note");
		}
	}
	return;
}

sub parse_bad {
	my ($word, @test) = @_;
	$word =~ s/\s.*//;
	$word =~ s/"//g;	# "
	$word =~ s/\///g;	# /
	$word =~ s/\|//g;	# |
	$word =~ s/\.//g;	# .	
	return $word;
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
	return if $nick eq $server->{nick};		# self test
	return unless $msg =~ /^!muistu/;

	if ($msg =~ /^!muistuta (\d+) ?(.*)$irs/) {
		echota("msg: $msg");
		my $time = $1;
		my $note = $2;
		$note = parse_bad($note);

		my $command = 'echo "echo '.$target.', '.$nick.', '.$note.' | nc -U '.$socket.'" | at now +'.$time.' minutes';
		#echota("Komento: ".$command);
		#Irssi::command("exec -name at -nosh $command");
		create_command($server, $target, $nick, $note, $time);
		$server->command("msg -channel $target ööh juu koitan muistaa muistuttaa..");
	} elsif ($msg =~ /^!muistuta (\d+)h ?(.*)$/) {
		my $hours = $1;
		my $note = $2;
		my $command = 'echo "echo '.$target.', '.$nick.', '.$note.' | nc -U '.$socket.'" | at now +'.$hours.' hours';
	}
	
	
	elsif ($msg =~ /!muistutukset/) {
		Irssi::command("exec -name atq atq");
	}
	return;
}

sub create_command {
	my ($server, $target, $nick, $note, $time, @rest) = @_;
	#da($server);
	my $command = 'echo "echo \"'.$server->{tag}.', '.$target.', '.$nick.', '.$note.'\" | nc -U '.$socket.'" | at now +'.$time.' minutes';
	echota("Komento: ".$command);
	#Irssi::command("exec -name at -nosh $command");
	my $retval = `$command`;
	#echota("Retval: ". chomp($retval));
	#echota("that was it");
}

# check the socket for data and act upon it
sub check_sock {
	my $msg;
	if (my $client = $server->accept()) {
		$client->recv($msg, 1024);
		echota("Got message from socket: $msg") if $msg;
		if ($msg =~ /(.*?), (.*?), (.*?), (.*)$/) {
			my $tag = $1;
			my $target = $2;
			my $nick = $3;
			my $note = $4;
			echota("Tag: $tag, Target: $target, nick: $nick, note: $note");
			msg_to_channel($tag, $target, $nick, $note);
		}
	}
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

my $timer = Irssi::timeout_add(250, \&check_sock, []);

Irssi::signal_add('message public', 'event_pubmsg');
#Irssi::signal_add('message private', 'event_privmsg');
