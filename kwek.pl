use Irssi;
use warnings;
use strict;
use utf8;
use Data::Dumper;
use Time::HiRes;
use vars qw($VERSION %IRSSI);

$VERSION = '20241231';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'kwek',
	description => 'Vastaa botin huutoihin.',
	license     => 'Public Domain',
	url         => '#chat',
	changed     => $VERSION,
);

my @channels = ('#Chat', '#salamolo2', '#salamolo', '#chat');
#my @answers = ('.boo','.bang', '.pang', '.pew', '.peng', '.p00f', '.paf', '.boem', '.kaboem', '.knal', '.bef', '.hump');
my @answers = (',bef',',bang');
my @keywords = ('quack', 'QUACK', 'KWEK');
my $DEBUG = 0;
my @botnick = ('Ducks', 'CloudBot');

sub sayit {
	my ($server, $target, $saywhat) = @_;
	prind('sayit: '.$saywhat);
	$server->command("MSG $target $saywhat");
	return;
}

sub if_kwek {
	my ($msg, $nick, @rest) = @_;
	if($msg ~~ @keywords) {
		if ($nick ~~ @botnick) {
			prind($msg);
			return $answers[int(rand(scalar @answers))];
		}
	}
	return undef;
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
	if ($target ~~ @channels) {
		my $newReturnString = if_kwek($msg, $nick);
		if ($newReturnString) {
			sleep 2;
			my $slept = Time::HiRes::sleep(rand 6);
			prind("target found! $target, returnstring: $newReturnString. slept: 2+$slept") if $DEBUG;
			sayit($server, $target, $newReturnString);
		}
	}
}

sub prind {
	my ($text, @rest) = @_;
	print "\0035" . $IRSSI{name} . ">\003 " . $text;
}

Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::print($IRSSI{name}." v. $VERSION");
