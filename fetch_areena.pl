# skripti lataa yleareena-linkin takaa löytyvän videon
# LAama1 4.4.2020
use strict;
use warnings;
use Irssi;

use vars qw($VERSION %IRSSI);
$VERSION = '20200404';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'fetch_areena.pl',
	description => 'Download video from YLE Areena.',
	license     => 'Public Domain',
	url         => '',
	changed     => $VERSION,
);

my $myname = 'fetch_areena.pl';
my $ylescript = 'yle-dl -qq --vfat --no-overwrite --destdir /mnt/music/areena --maxbitrate best --proxy=10.7.0.4:3128';

sub sig_msg_pub {
	my ($server, $msg, $target) = @_;
	if ($msg =~ /(https?:\/\/areena\.yle\.fi\/\S+)/i) {
		cmd_start_dl($1);
	} elsif ($msg =~ /(https:\/\/yle\.fi\S+)/i) {
		cmd_start_dl($1);
	}
}

sub cmd_start_dl {
	my ($url, @rest) = @_;
	Irssi::print($IRSSI{name}.' fetching: '. $url);
	Irssi::command("exec -name yle -nosh $ylescript $url");
	#Irssi::command("exec -close yle");	# detach
	# -interactive
}

Irssi::signal_add('message public', 'sig_msg_pub');
