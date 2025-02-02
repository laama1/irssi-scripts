use warnings;
use strict;
use Irssi;
use vars qw($VERSION %IRSSI);
use Encode;

$VERSION = '0.42';
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
    my $mynick = quotemeta $serverrec->{nick};
	return if ($nick eq $mynick);   #self-test
	return if $nick eq 'kaaosradio';			# ignore this nick, a known bot
	my @targets = split / /, Irssi::settings_get_str('oraakkeli_enabled_channels');
    return unless $target ~~ @targets;
	my $nickindex = index $msg, $serverrec->{nick};
	if ($nickindex >= 0 && $msg =~ /\?$/gi ) {
		return if KaaosRadioClass::floodCheck() == 1;			# return if flooding
		$msg = decode('UTF-8', $msg);
		my $querystr = substr $msg, ((length $serverrec->{nick}) +2);
		my $urli = "https://www.lintukoto.net/viihde/oraakkeli/index.php?html&kysymys=${querystr}";
		my $stats = fetchOraakkeliUrl($urli);
		if ($stats =~ /html/) {
			$serverrec->command("MSG $target $nick: nyt ei natsaa.. sorry");
			return;
		}
		$serverrec->command("MSG $target $nick: ${stats}") if defined $stats;
		my $finalstring = '!oraakkeli request from '.$nick.' on channel '.$target.': '.$querystr.' -- answer: '.$stats;
		Irssi::print($finalstring);
	}
	return;
}


sub fetchOraakkeliUrl {
	my ($url, @rest) = @_;
	my $ua = LWP::UserAgent->new();#'agent' => $useragent, max_size => 265536);
	$ua->timeout(3);				# 3 seconds
	$ua->ssl_opts('verify_hostname' => 0);

	my $response = $ua->get($url);
	my $page = '';
	if ($response->is_success) {
		$page = $response->decoded_content();		# $page = $response->decoded_content(charset => 'none');
	} else {
		print("Failure ($url): " . $response->code() . ', ' . $response->message() . ', ' . $response->status_line);
		return undef;
	}
	if (defined $page && length $page > 240) {
		$page = substr $page, 0, 240;
		$page .= ' ...';
	}
	return $page;
}

Irssi::settings_add_str('Oraakkeli', 'oraakkeli_enabled_channels', '');
Irssi::signal_add_last('message public', 'pubmsg');
#Irssi::signal_add_last('message irc action', 'pubmsg');

Irssi::print("Oraakkeli v. $VERSION loaded");
Irssi::print('Enabled channels: '. Irssi::settings_get_str('oraakkeli_enabled_channels'));
