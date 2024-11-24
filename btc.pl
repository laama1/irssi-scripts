use warnings;
use strict;
use Encode qw/encode decode/;
use Irssi;
use Data::Dumper;
use DBI qw(:sql_types);

use utf8;
binmode STDOUT, ':utf8';
binmode STDIN, ':utf8';
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;		# LAama1 30.12.2016
my $DEBUG = 0;

my $apiurl = 'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=eur';

use vars qw($VERSION %IRSSI);
$VERSION = '20241125';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'btc.pl',
	description => 'Get BTC value from random api.',
	license     => 'Public Domain',
	url         => 'https://bot.8-b.fi',
	changed     => $VERSION,
);

sub event_privmsg {
	my ($server, $msg, $nick, $address) = @_;
	return if ($nick eq $server->{nick});	#self-test
	
	return;
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
    if ($msg =~ /^!btc/gi) {
        my $btc = getBtcValue();
        $server->command("MSG $target BTC value: $btc €");
    }
	return;
}

sub getBtcValue {
    my $data = KaaosRadioClass::getJSON($apiurl);
    if ($data) {
        return $data->{bitcoin}->{eur};
    } else {
        return "Error.";
    }
}

sub dp {
	return unless $DEBUG == 1;
	Irssi::print($IRSSI{name}." debug: @_");
	return;
}

sub da {
	return unless $DEBUG == 1;
	Irssi::print('addquote: ');
	Irssi::print(Dumper(@_));
	return;
}

sub prind {
	my ($text, @rest) = @_;
	print "\0039" . $IRSSI{name} . ">\003 " . $text;
}

sub prindw {
	my ($text, @rest) = @_;
	print "\0034" . $IRSSI{name} . ">\003 " . $text;
}

Irssi::signal_add('message public', 'event_pubmsg');
Irssi::signal_add('message private', 'event_privmsg');
