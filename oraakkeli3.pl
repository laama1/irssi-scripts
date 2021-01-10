use warnings;
use strict;
use Irssi;
use KaaosRadioClass;				# LAama1 9.10.2017
use vars qw($VERSION %IRSSI);

$VERSION = '0.322';
%IRSSI = (
        authors     => 'LAama1',
        contact     => 'LAama1@Ircnet',
        name        => 'Oraakkeli',
        description => 'Kysyy lintukodon oraakkelilta ja kertoo vastauksen.',
        license     => 'BSD',
        url         => 'http://www.lintukoto.net/viihde/oraakkeli',
        changed     => $VERSION
);

sub pubmsg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;
	return if ($nick eq $serverrec->{nick});	# self-test
	return if $nick eq 'kaaosradio';			# ignore this nick
	my @targets = split / /, Irssi::settings_get_str('oraakkeli_enabled_channels');
    return unless $target ~~ @targets;
	my $nickindex = index $msg, $serverrec->{nick};
	if ($nickindex >= 0 && $msg =~ /\?$/gi ) {
		return if KaaosRadioClass::floodCheck() == 1;			# return if flooding
		my $querystr = substr $msg, ((length $serverrec->{nick}) +2);
		my $stats = KaaosRadioClass::fetchUrl("http://www.lintukoto.net/viihde/oraakkeli/index.php?html=0&kysymys=${querystr}",0);
		#sleep(2); # take a nap before answering
		$serverrec->command("MSG $target $nick: ${stats}") unless $stats eq '-1';
		Irssi::print("!oraakkeli request from $nick on channel $target: $querystr -- answer: $stats");
	}
	return;
}

Irssi::settings_add_str('Oraakkeli', 'oraakkeli_enabled_channels', '');
Irssi::signal_add_last('message public', 'pubmsg');
#Irssi::signal_add_last('message irc action', 'pubmsg');

Irssi::print("Oraakkeli v. $VERSION loaded");
Irssi::print('Enabled channels: '. Irssi::settings_get_str('oraakkeli_enabled_channels'));
