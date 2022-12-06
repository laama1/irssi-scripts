use Irssi;
use Irssi::Irc;
use DBI;
use DBI qw(:sql_types);
use warnings;
use strict;
use utf8;
#use KaaosRadioClass;		# LAama1 30.12.2016
use Data::Dumper;


use vars qw($VERSION %IRSSI);
$VERSION = '20190321';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'LAama1@ircnet',
	name        => 'vaihdatopic',
	description => 'Vaihda topic kanavalla.',
	license     => 'Public Domain',
	url         => '#salamolo',
	changed     => $VERSION
);

my $channels = '#salamolo2';
my $myname = 'vaihdatopic.pl';
my $DEBUG = 1;
my $oldTopic = '';
my $helptext_long = 'Vaihda kanavan topic kirjoittamalla !topic <topic> kanavalla tai privassa !topic <#kanava> <topic>.';
my $helptext_short = 'Topic-skriptin help: !help topic';

sub msgit {
	my ($server, $nick, $text, @rest) = @_;
	$server->command("MSG $nick $text");
}

# Say it public to a channel. Params: $server, $target, $saywhat
sub sayit {
	my ($server, $target, $saywhat) = @_;
	$server->command("MSG $target $saywhat");
}

sub changeTopic {
	my ($server, $target, $topic, @rest) = @_;
	my $channelObj = $server->channel_find($target);
	$oldTopic = $channelObj->{topic};
	dp(__LINE__.": changeTopic target: $target, new topic: $topic, current topic: $oldTopic");
	return if $topic eq $oldTopic;
	$server->send_raw("topic $target :$topic");
}

sub event_privmsg {
	my ($server, $data, $nick, $address) = @_;
	if($data =~ /^!topic\s(.{1,470})/gi)	{
		my $newtopic = $1;		# command the user has entered
		$server->command("MSG $channels New topic: $newtopic");
		changeTopic($server, $channels, $newtopic);
	}
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;

    my $enabled_raw = Irssi::settings_get_str('vaihdatopic_enabled_channels');
    my @enabled = split(/ /, $enabled_raw);
    return unless grep(/$target/, @enabled);

	if ($msg =~ /^\!help vaihda/i) {
		sayit($server, $target, $helptext_short);
		Irssi::print("$myname: !help request from $nick on $target.");
		return;
	} elsif ($msg =~ /^!help topic$/i) {
		Irssi::print("$myname: !help topic request from $nick on $target.");
		sayit($server, $target, $helptext_long);
		return;
	}
	if($data =~ /^!topic$/gi) {			# if !topic
		#return if KaaosRadioClass::floodCheck() == 1;
		sayit($server, $target, "Kanavan nykyinen oletus-topic on: $oldTopic");
		Irssi::print("$myname: !topic request from $nick on $target.");
	} elsif($msg =~ /^!topic\s(.{1,470})/gi)	{
		my $newtopic = $1;
		changeTopic($server, $target, $newtopic);
		Irssi::print("$myname: !topic request from $nick on $target.");
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

Irssi::settings_add_str('vaihdatopic', 'vaihdatopic_enabled_channels', '');
Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::signal_add_last('message private', 'event_privmsg');
Irssi::print("vaihdatopic.pl v. $VERSION -- New commands: /set vaihdatopic_enabled_channels #1 #2");
Irssi::print('vaihdatopic.pl channels: '. Irssi::settings_get_str('vaihdatopic_enabled_channels'));