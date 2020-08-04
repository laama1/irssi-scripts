use Irssi;
use warnings;
use strict;
use utf8;
#binmode(STDOUT, ':utf8');
#binmode(STDIN, ':utf8');
#use open ':std', ':encoding(UTF-8)';
#use Irssi::Irc;
#use DBI;
#use DBI qw(:sql_types);
#use Encode;
#use KaaosRadioClass;		# LAama1 30.12.2016
use Data::Dumper;


use vars qw($VERSION %IRSSI);
$VERSION = '20200719';
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
my @answers = ('.bef', '.bang', '.pew');
my @keywords = ('KWEK', 'FLAP');
my $DEBUG = 1;

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

sub if_kwek {
	my ($msg, $nick, @rest) = @_;
	if($msg =~ /KWEK/ || $msg =~ /FLAP/) {
		print($IRSSI{name}.'> '. $msg);
		return $answers[int(rand(scalar @answers))];
	}
	return undef;
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
	#Irssi::print($IRSSI{name}.' pubmsg! target: '. $target);
	if ($target ~~ @channels) {
		my $newReturnString = if_kwek($msg, $nick);
		if ($newReturnString) {
			sleep(4);
			print($IRSSI{name}."> target found! $target, returnstring: $newReturnString") if $DEBUG;
			sayit($server, $target, $newReturnString);
		}
	}
	return;
}

Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::print($IRSSI{name}." v. $VERSION");
