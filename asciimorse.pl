use warnings;
use strict;
use Irssi;
use vars qw($VERSION %IRSSI);
use Encode;
use Data::Dumper;       # for debugging only

use Convert::Morse qw(as_ascii as_morse is_morsable);

$VERSION = '0.1';
%IRSSI = (
        authors     => 'LAama1',
        contact     => 'LAama1@Ircnet',
        name        => 'ascii 2 morse',
        description => 'Tulostaa morsekooodia.',
        license     => 'BSD',
        url         => 'https://8-b.fi',
        changed     => $VERSION
);

sub pubmsg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;
	return if ($nick eq $serverrec->{nick});	# self-test
	return if $nick eq 'kaaosradio';			# ignore this nick

	return if KaaosRadioClass::floodCheck() == 1;			# return if flooding
    if ($msg =~ /\!morse (.*)/ui) {
    	my $searchw = decode('ISO-8859-1', $1);
        print("asciimorse> Searchword: ".$searchw);
        my $morse = as_morse($searchw);
        $serverrec->command("MSG $target Morse: $morse") if $morse;
    }
	return;
}

Irssi::signal_add_last('message public', 'pubmsg');
Irssi::print($IRSSI{name}." v. $VERSION loaded");
