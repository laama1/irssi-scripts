use Irssi;
#use Irssi::Irc;
use DBI;
use DBI qw(:sql_types);
use warnings;
use strict;
use utf8;
binmode STDOUT, ':utf8';
binmode STDIN, ':utf8';
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;		# LAama1 30.12.2016
use Data::Dumper;
use vars qw($VERSION %IRSSI);

$VERSION = '2023-01-09';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'KickPelle',
	description => 'Kickaa Pelle ulos kanavalta anomuumisti.',
	license     => 'Public Domain',
	url         => '#salamolo',
	changed     => $VERSION
);
#TODO
# check if you are op

# config
my $DEBUG = 1;
my $votelimit = 3;		# how many votes is needed to kick someone
my $myname = 'kickpelle.pl';
my $badwordfile = Irssi::get_irssi_dir().'/scripts/badwordlist.txt';

my $publicvotes = {};
my $lastprivkick = time;
my @badwords;

GETBADWORDLIST();

my $helptext = 'Votea pelle ulos kanavalta kirjoittamalla kanavalla: "!kick pelle [kickmessage]". Kick vaatii 3 votea. 
Operaattorit voivat käyttää myös privassa: "!kick #kanava <nick>", jolloin henkilö lähtee ensimmäisestä osumasta!';
my $helptext2 = 'Kickpelleskripti. Ohje: https://bot.8-b.fi/#kick';

my $joinmessage = 'Achtung. Olen kanavan sheriffi. Potkin väkeä jos he mainitsevat kiellettyjä sanoja. Listan kielletyistä sanoista saat privaasi komennolla: !badwords tai !kirosanat. Opit voivat kasvattaa listaa, kirjoita "!help badword" niin saat privaasi ohjeet.';

sub print_help {
	my ($server, $target) = @_;
	sayit($server, $target, $helptext);
	return 0;
}

sub print_joinmsg {
	my $enabled_raw = Irssi::settings_get_str('kickpelle_enabled_channels');
	my @enabled = split / /, $enabled_raw;
	my @windows = Irssi::windows();
	foreach my $window (@windows) {
		if ($window->{active}->{type} eq 'CHANNEL' && $window->{active}->{name} ~~ @enabled) {
			#$window->{active_server}->command("MSG $window->{active}->{name} $joinmessage");
			return;
		}
	}
	return;
}

# private message to nick
sub msgit {
	my ($server, $nick, $text, @rest) = @_;
	$server->command("msg $nick $text");
	return;
}

# Say it public to a channel
sub sayit {
	my ($server, $target, $saywhat) = @_;
	if (KaaosRadioClass::floodCheck(5) == 0) {
		$server->command("MSG $target $saywhat");
	}
	return;
}

sub getStats {
	da(__LINE__.': getStats:', $publicvotes);
	return;
}

sub ADDBADWORD {
	my ($badsword, @rest) = @_;
	# TODO: sanitize badsword
	if ($badsword ~~ @badwords) {
		return '';
	}
	KaaosRadioClass::addLineToFile($badwordfile, $badsword);
	push @badwords, $badsword;
	return 1;
}

sub SAVEBADWORDLIST {
	my @rest = @_;
	KaaosRadioClass::writeArrayToFile($badwordfile, @badwords);
	return;
}

sub DELBADWORD {
	my ($badword, @rest) = @_;
	my $index = 0;
	my $found = 0;
	foreach my $word (@badwords) {
		if ($badword eq $word) {
			splice @badwords, $index, 1;
			$found = 1;
			dp(__LINE__.': del found: ' . $badword);
			#return 1;
			last;
		}
		$index++;
	}

	if ($found == 1) {
		SAVEBADWORDLIST();
		return 1;
	}
}

sub GETBADWORDLIST {
	my @rest = @_;
	my $temp_badwords = KaaosRadioClass::readTextFile($badwordfile);
	if ($temp_badwords == -1) {
		dp(__LINE__.': no bad words!');
		@badwords = ('____', 'russiancup');
		SAVEBADWORDLIST();
	}
	foreach my $test (@$temp_badwords) {
		dp(__LINE__.' badword: '.$test);
		push @badwords, $test;
	}
	#da(@badwords);
	prind('Badwordfile '.$badwordfile.' loaded.');
	return;
}

sub kickPerson {
	my ($server, $channel, $nick, $reason, $kicker, @rest) = @_;
	#dp("target: $channel, nick: $nick, reason: $reason");

	if (defined($publicvotes->{$nick}->{$channel}->{$kicker})) {
		sayit($server, $channel, "Only one vote per user. ($nick) votes: ".($publicvotes->{$nick}->{$channel}->{votecount} % $votelimit));
		return 0;
	} else {
		$publicvotes->{$nick}->{$channel}->{$kicker} = 1;
	}

	$publicvotes->{$nick}->{$channel}->{votecount} += 1;
	$publicvotes->{$nick}->{when} = localtime time;		# format like this for informational purposes
	$publicvotes->{$nick}->{$channel}->{reason} = $reason;

	my $howmany = $publicvotes->{$nick}->{$channel}->{votecount};
	dp(__LINE__.': kickPerson count: '.$howmany. ', modulo: '.($howmany % $votelimit));

	if ($howmany > 1 && $howmany % $votelimit == 0) {
		dp(__LINE__.': kickPerson KICK-KING!');
		doKick($server, $channel, $nick, $publicvotes->{$nick}->{$channel}->{reason});
		$publicvotes->{$nick}->{bootcount} += 1;
	} else {
		sayit($server, $channel, "($nick) votes: ".($howmany % $votelimit). "/3, \"$reason\"");
	}
}

sub doKick {
	my ($server, $channel, $nick, $reason) = @_;
	$server->send_raw("kick $channel $nick :*BOOT $reason*");
	return;
}

sub do_ban {
	my ($server, $channel, $nick, $reason) = @_;
	doKick($server, $channel, $nick, $reason);
	$server->send_raw("ban $channel $nick :*$reason*");
	return;
}

sub event_privmsg {
	my ($server, $data, $nick, $address) = @_;
	#if($data =~ /^!kick (#[^\s]*) ([^\s]*) (.{1,470})/gi) {
	if($data =~ /^!kick (#[^\s]*) ([^\s]*)(.*)/gi) {
		dp(__LINE__.": event_privmsg kick 3 params: $1 $2 $3");
		my $kickchannel = $1;
		my $kicknick = $2;
		my $kickreason = $3;
		if (get_nickrec($server, $kickchannel, $kicknick)) {
			dp(__LINE__.': event_privmsg, get_nickrec found');
			if (ifop($server, $kickchannel, $nick)) {
				dp(__LINE__.": event_privmsg, $nick is op.");
				doKick($server, $kickchannel, $kicknick, $kickreason);
				msgit($server, $nick, "Kicked $kicknick off $kickchannel!");
			} else {
				dp(__LINE__.": event_privmsg, $nick is NOT op.");
				msgit($server, $nick, "You don't have operator status on $kickchannel!");
			}
		} else {
			dp(__LINE__.": event_privmsg, no $kicknick on $kickchannel.");
			msgit($server, $nick, "No nick $kicknick on $kickchannel!");
		}
	} elsif ($data =~ /^!kickban (#[^\s]*) ([^\s]*)(.*)/gi) {
		dp(__LINE__.": event_privmsg kickban 3 params: $1 $2 $3");
		my $banchannel = $1;
		my $bannick = $2;
		my $banreason = $3;
		if (get_nickrec($server, $banchannel, $bannick)) {
			if (ifop($server, $banchannel, $nick)) {
				#dp(__LINE__.": event_privmsg, $nick is op.");
				do_ban($server, $banchannel, $bannick, $banreason);
				msgit($server, $nick, "Banned $bannick off $banchannel!");
			} else {
				#dp(__LINE__.": event_privmsg, $nick is NOT op.");
				msgit($server, $nick, "You don't have operator status on $banchannel!");
			}
		} else {
			#dp(__LINE__.": event_privmsg, no $bannick on $banchannel.");
			msgit($server, $nick, "No nick $bannick on $banchannel!");
		}
	}
	return;
}

sub badWordFilter {
	my ($msg, @rest) = @_;
	foreach my $badword (@badwords) {
		return 1 if $msg =~ m/$badword/i;
	}
	return 0;
}

sub get_nickrec {
	my ($server, $channel, $nick) = @_;
	return unless defined $server && defined $channel && defined $nick;
	my $chanrec = $server->channel_find($channel);
	return $chanrec ? $chanrec->nick_find($nick) : undef;
}

# if $nick is OP or VOICE or HALFOP
sub ifop {
	my ($server, $channel, $nick) = @_;
	my $nickrec = get_nickrec($server, $channel, $nick);
	return ($nickrec->{op} == 1 || $nickrec->{voice} == 1 || $nickrec->{halfop} == 1) ? 1 : 0;
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;

	my $enabled_raw = Irssi::settings_get_str('kickpelle_enabled_channels');
	my @enabled = split / /, $enabled_raw;
	return unless grep /$target/i, @enabled;

	if ($msg =~ /^!help kick/i) {
		print_help($server, $target);
		return;
	} elsif ($msg =~ /^!help badword/) {
		msgit($server, $nick, $helptext2);
		msgit($server, $nick, $helptext);
		return;
	} elsif ($msg =~ /^!kirosanat$/gi || $msg =~ /^!badwords$/gi) {
		my $string = 'Bad words: ';
		foreach my $badword (@badwords) {
			$string .= "$badword, ";
		}
		#msgit($server, $nick, $string);
		sayit($server, $target, $string);
		return;
	}

	if (ifop($server, $target, $nick) != 1) {
		return;
	}
	if ($msg =~ /^!kick ([^\s]*) (.*)$/gi)	{
		dp(__LINE__.": kickmsg: $msg");
		my $kicknick = $1;		# nick to kick
		my $reason = $2;
		if (get_nickrec($server, $target, $nick)) {
			kickPerson($server, $target, $kicknick, $reason, $nick);
		}
		return;
	} elsif ($msg =~ /^!kick ([^\s]*)/gi) {
		dp(__LINE__.": msg: $msg");
		my $kicknick = $1;
		my $reason = '';		# no reason, just for kicks
		if (get_nickrec($server, $target, $kicknick)) {
			kickPerson($server, $target, $kicknick, $reason, $nick);
		}
		return;
	} elsif ($msg =~ /^!badword del (.*)/gi) {
		if (DELBADWORD($1)) {
			sayit($server, $target, "Poistettiin '$1' kirosanafiltteristä.");
		} else {
			sayit($server, $target, 'Ei löytynyt filtteristä, tai sattui virhe.');
		}
		return;
	} elsif ($msg =~ /^!badword add (.*)$/gi || $msg =~ /^!badword (.*)$/gi) {
		if (ADDBADWORD($1)) {
			sayit($server, $target, "Lisättiin '$1' kirosanafiltteriin.");
		} else {
			sayit($server, $target, 'Löytyi jo filtteristä, tai sattui virhe.');
		}
		return;
	}

	if (badWordFilter($msg)) {
		doKick($server, $target, $nick, 'Ei kiroilla!');
		return;
	}
}

sub prind {
	my ($text, @rest) = @_;
	print("\00313" . $IRSSI{name} . ">\003 ". $text);
}

sub da {
	return unless $DEBUG == 1;
	Irssi::print("$myname-debug array:");
	Irssi::print Dumper (@_);
	return;
}

sub dp {
	return unless $DEBUG == 1;
	Irssi::print("$myname-debug: @_");
	return;
}

Irssi::command_bind('kickpellestats', \&getStats);
Irssi::settings_add_str('kickpelle', 'kickpelle_enabled_channels', '');
#print_joinmsg();
Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::signal_add_last('message private', 'event_privmsg');
prind("kickpelle.pl v. $VERSION -- New commands: /set kickpelle_enabled_channels #chan1 #chan2, /kickpellestats");
