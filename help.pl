use strict;
use warnings;

use Irssi;
use vars qw($VERSION %IRSSI);
use Irssi::Irc;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;

$VERSION = '0.50';
%IRSSI = (
	authors => 'LAama1',
	contact => 'LAama1@ircnet',
	name => 'help',
	description => 'Huolehtii help-sivun tulostamisesta.',
	license => 'BSD',
	url => 'https://bot.8-b.fi',
	changed => '2022-12-06',
);

sub getHelp {
	return 'https://bot.8-b.fi/';
}

sub pubmsg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;

	return if ($nick eq $serverrec->{nick});   #self-test
	if ($msg =~ /(!help)/gi || $msg =~ /(.help)/gi {
        my $keyword = $1;
		return if KaaosRadioClass::floodCheck() == 1;
		my $help = $serverrec->{nick} . " ohje: ". getHelp();
		$serverrec->command("MSG $target $help");
        Irssi::print($IRSSI{name} .": $keyword request from $nick on channel $target");
	}
}
Irssi::signal_add_last('message public', 'pubmsg');
