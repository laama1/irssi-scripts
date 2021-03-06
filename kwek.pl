use Irssi;
use warnings;
use strict;
use utf8;
use Data::Dumper;
use Time::HiRes;
use vars qw($VERSION %IRSSI);

$VERSION = '20201022';
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
my @answers = ('.bef','.hump');
#my @keywords = ('KWEK', 'FLAP');		# TODO
my @keywords = ('quack', 'quack2');
my $DEBUG = 0;

# send private message
sub msgit {
	my ($server, $nick, $text, @rest) = @_;
	$server->command("msg $nick $text");
	return;
}

# Say it public to a channel. Params: $server, $target, $saywhat
sub sayit {
	my ($server, $target, $saywhat) = @_;
	print($IRSSI{name}.'> sayit: '.$saywhat);
	$server->command("MSG $target $saywhat");
	return;
}

# check if line contains these regexp
sub if_kwek {
	my ($msg, $nick, @rest) = @_;
	#if($msg =~ /KWEK/ || $msg =~ /FLAP/) {
	if($msg =~ /quack/ ) {
		print($IRSSI{name}.'> '. $msg);
		return $answers[int(rand(scalar @answers))];
	}
	return undef;
}

# run this function on every text line
sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
	if ($target ~~ @channels) {
		my $newReturnString = if_kwek($msg, $nick);
		if ($newReturnString) {
			sleep 5;
			my $howlong = Time::HiRes::sleep rand(6);
			print($IRSSI{name}."> target found! $target, returnstring: $newReturnString. Slept for $howlong+3 seconds") if $DEBUG;
			sayit($server, $target, $newReturnString);
		}
	}
	if ($msg =~ /fumigate the moose/) {
		my $response = "Uh, no, actually I'm an Epsilon from way back.";
		print $IRSSI{name}."> bot mooses!" if $DEBUG;
		sayit($server, $target, $response);
	}
}

Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::print($IRSSI{name}." v. $VERSION");
