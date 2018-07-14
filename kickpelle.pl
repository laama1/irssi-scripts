use Irssi;
use Irssi::Irc;
use DBI;
use DBI qw(:sql_types);
use warnings;
use strict;
use utf8;
use KaaosRadioClass;		# LAama1 30.12.2016
use Data::Dumper;


use vars qw($VERSION %IRSSI);
$VERSION = "2018-06-20";
%IRSSI = (
	authors     => "LAama1",
	contact     => "ircnet: LAama1",
	name        => "KickPelle",
	description => "Kickaa Pelle ulos kanavalta anomuumisti.",
	license     => "Public Domain",
	url         => "#salamolo2",
	changed     => $VERSION
);


my $channels = '#kaaosradio';
my $myname = "kickpelle.pl";
my $votelimit = 3;		# how many votes needed to kick someone
my $publicvotes = {};
# publicvotes->{nick}->{channel}->votecount
# 
#
#
my @badwords = ('____','russiancup');

my $DEBUG = 1;

my $helptext = "Kickaa pelle ulos kanavalta kirjoittamalla minulle kanavalla !kick <nick> [kickmessage]";


sub print_help {
	my ($server, $target) = @_;
	dp("Printing help..");
	sayit($server, $target, $helptext);
	return 0;
}

sub msgit {
	my ($server, $nick, $text, @rest) = @_;
	$server->command("msg $nick $text");
}

# Say it public to a channel
sub sayit {
	my ($server, $target, $saywhat) = @_;
	if (KaaosRadioClass::floodCheck(5) == 0) {
		$server->command("MSG $target $saywhat");
	}
}

sub getStats {
	dp("jees");
	da(@$publicvotes);
}

sub ifUserFoundFromChannel {
	my ($channel, $nick, @rest) = @_;
	my @windows = Irssi::windows();
	foreach my $window (@windows) {
		next if $window->{name} eq "(status)";
		next unless $window->{active}->{type} eq "CHANNEL";
		if($window->{active}->{name} eq $channel) {
			dp("Found! $window->{active}->{name}");
			dp("what if...");
			#da($window);
			my @nicks = $window->{active}->nicks();
			#da(@nicks);
			foreach my $comparenick (@nicks) {
				if ($comparenick->{nick} eq $nick) {
					dp("found it! feel free to kick $nick");
					# return 1 on first match
					# operator status check.
					#return 1 unless $comparenick->{op} == 1 or $comparenick->{halfop} == 1 or $comparenick->{voice} == 1;
					return 1;
				}
			}
		}
	}
	return 0;
}

sub kickPerson {
	my ($server, $channel, $nick, $reason, $kicker, @rest) = @_;
	dp("target: $channel, nick: $nick, reason: $reason");

	if ($publicvotes->{$nick}->{$channel}->{$kicker}) {
		sayit($server, $channel, "Only one vote per user. ($nick) votes: ".($publicvotes->{$nick}->{$channel}->{'votecount'} % $votelimit));
		return 0;
	} else {
		$publicvotes->{$nick}->{$channel}->{$kicker} += 1;
	}

	$publicvotes->{$nick}->{$channel}->{'votecount'} += 1;
	my $howmany = $publicvotes->{$nick}->{$channel}->{'votecount'};
	$publicvotes->{$nick}->{'when'} = localtime(time());

	$publicvotes->{$nick}->{$channel}->{'reason'} = $reason;

	dp("count: ".$howmany. ", modulo: ".($howmany % $votelimit));
	if ($howmany > 1 && $howmany % $votelimit == 0) {
		dp("KICK-KING!");
		##$server->send_raw("kick $channel $nick :*BOOT ".$publicvotes->{$nick}->{$channel}->{'reason'}." *");
		doKick($server, $channel, $nick, $publicvotes->{$nick}->{$channel}->{'reason'});
		$publicvotes->{$nick}->{'bootcount'} += 1;
	} else {
		sayit($server, $channel, "($nick) votes: ".($howmany % $votelimit));
	}
}

sub doKick {
	my ($server, $channel, $nick, $reason) = @_;
	$server->send_raw("kick $channel $nick :*BOOT ".$reason."*");
}

sub event_privmsg {
	my ($server, $data, $nick, $address) = @_;
	if($data =~ /^!kick (#[^\s]?) ([^\s]?) (.{1,470})/gi) {
		my $kickchannel = $1;
		my $kicknick = $2;
		my $kickreason = $3 || "";
		if (ifUserFoundFromChannel($kickchannel, $kicknick)) {
			kickPerson($server, $kickchannel, $kicknick, $kickreason);
		}
	}
}

sub badWordFilter {
	my ($msg, @rest) = @_;
	foreach my $badword (@badwords) {
		return 1 if $msg =~ m/$badword/;
	}
	return 0;
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
	
    my $enabled_raw = Irssi::settings_get_str('kickpelle_enabled_channels');
    my @enabled = split(/ /, $enabled_raw);
    return unless grep(/$target/, @enabled);

	if ($msg =~ /^!help kick\b/i || $msg =~ /^!kick$/i) {
		print_help($server, $target);
		return;
	}
	if ($msg =~ /^!kick ([^\s]*) (.*)$/gi)	{
		my $kicknick = $1;		# nick to kick
		my $reason = $2;
		if (ifUserFoundFromChannel($target, $kicknick) == 1) {
			kickPerson($server, $target, $kicknick, $reason, $nick);
		}
	} elsif ($msg =~ /^!kick ([^\s]*)/gi) {
		dp("msg: ".$msg);
		my $kicknick = $1;
		my $reason = "";
		if (ifUserFoundFromChannel($target, $kicknick) == 1) {
			kickPerson($server, $target, $kicknick, $reason, $nick);
		}
	}

	if (badWordFilter($msg)) {
		dp("badword found!");
		#kickPerson($server, $target, $nick, "Bad words!", $server->{nick});
		doKick($server, $target, $nick, "Bad words!");
	}
}

sub da {
	return unless $DEBUG == 1;
	Irssi::print("$myname-debug array:");
	Irssi::print Dumper (@_);
}

sub dp {
	return unless $DEBUG == 1;
	Irssi::print("$myname-debug: @_");
}

Irssi::command_bind('kickpellestats', \&getStats);
Irssi::settings_add_str('kickpelle', 'kickpelle_enabled_channels', '');
Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::signal_add_last('message private', 'event_privmsg');
Irssi::print("kickpelle.pl v. $VERSION -- New commands: /set kickpelle_enabled_channels #1 #2");
