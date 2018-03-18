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
$VERSION = "2018-03-16";
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
my $votelimit = 2;		# how many votes needed to kick someone
my $publicvotes = {};
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
	$server->command("MSG $target $saywhat");
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
		dp("window name:");
		dp($window->{active}->{name});
		if($window->{active}->{name} eq $channel) {
			dp("Found! $window->{active}->{name}");
			dp("what if...");
			#da($window);
			my @nicks = $window->{active}->nicks();
			da(@nicks);
			foreach my $comparenick (@nicks) {
				if ($comparenick->{nick} eq $nick) {
					dp("found it! feel free to kick him");
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
	my ($server, $channel, $nick, $reason, @rest) = @_;
	dp("target: $channel, nick: $nick, reason: $reason");
	$publicvotes->{$nick}->{$channel}->{'votecount'} += 1;
	my $howmany = $publicvotes->{$nick}->{$channel}->{'votecount'};
	$publicvotes->{$nick}->{'when'} = localtime(time());
	dp("count: ".$howmany. ", modulo: ".($howmany % $votelimit));
	if ($howmany > 1 && $howmany % $votelimit == 0) {
		dp("KICK-KING!");
		$server->send_raw("kick $channel $nick :*BOOT $reason*");
		$publicvotes->{$nick}->{'bootcount'} += 1;
	}
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

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
	
    my $enabled_raw = Irssi::settings_get_str('kickpelle_enabled_channels');
    my @enabled = split(/ /, $enabled_raw);
    return unless grep(/$target/, @enabled);
	#return unless $target ~~ @channels;
	
	#return unless $target eq $channels;
	if ($msg =~ /^!help kick\b/i || $msg =~ /^!kick$/i) {
		print_help($server, $target);
		return;
	}
	if ($msg =~ /^!kick ([^\s]*) (.*)$/gi)	{
		my $kicknick = $1;		# nick to kick
		my $reason = $2;
		if (ifUserFoundFromChannel($target, $kicknick) == 1) {
			kickPerson($server, $target, $kicknick, $reason);
		}
	} elsif ($msg =~ /^!kick ([^\s]*)/gi) {
		dp("msg: ".$msg);
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
