use warnings;
use strict;
use Irssi;
use Data::Dumper;

# HELP
# irssi gateway for fifi-remote.pl script. (originally derived from fifo-remote.pl)
#

use vars qw($VERSION %IRSSI);
$VERSION = '2019-03-17';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'LAama1@ircnet',
	name        => 'fifi_remote_handler',
	description => 'Handle signals emited with fifi-remote-msg tag.',
	license     => 'Fublic Domain',
	url         => 'http://kaaosradio.fi',
	changed     => $VERSION
);

my $kanava = '#salamolo';
my $ircnetwork = '';
my $DEBUG = 0;

# debug print array
sub da {
	return unless $DEBUG == 1;
	Irssi::print("fifi-remote-handler: ");
	Irssi::print(Dumper(@_));
}

sub sayit {
	my ($server, $target, $msg) = @_;
	#$server->command("MSG $target $msg");
	$server->command("MSG $kanava $msg");
}

sub printit {
	my ($cmd, $data, @rest) = @_;
	Irssi::print("%R>>%n %_$cmd%_ $data", MSGLEVEL_CLIENTCRAP);
}

sub parse_remote_msg {
	my ($msg, @rest) = @_;
	#Irssi::print('msg: ' . $msg);
	if ($msg =~ /^(kaaos): (.*)$/) {
		my $command = $1;
		my $data = $2;
		printit('kaaos!', $data);
	} elsif ($msg =~ /^(icecast): (.*)$/) {
		my $command = $1;
		my $data = $2;
		printit($command . ':', $data);
	} elsif ($msg =~ /^(stream\d?): (.*)$/) {
		my $command = $1;
		my $data = $2;
		printit($command . ':', $data);
	} elsif ($msg =~ /^(chill): (.*)$/) {
		my $command = $1;
		my $data = $2;
		printit($command . ':', $data);
	} elsif ($msg =~ /^(krnytsoi): (.*)$/) {
		my $command = $1;
		my $data = $2;
		printit('krnytsoi:', $data);
	}
}

Irssi::signal_add('fifi-remote-msg', 'parse_remote_msg');
Irssi::print($IRSSI{name} .' loaded. Version: '.$VERSION);
