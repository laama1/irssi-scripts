use strict;
#use IO::Socket;
#use Fcntl;
use Irssi;
# install next one: 
#use Time::Format qw(%strftime);
use Data::Dumper;
use KaaosRadioClass;

use vars qw($VERSION %IRSSI);

$VERSION = '0.1';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'LAama1@ircnet',
	name        => 'Icecast file listener',
	description => 'provides an interface to irssi via normal file',
	license     => 'BSD',
	url         => 'http://8-b.fi',
	changed     => '2022-03-04',
);

my $filename = "/tmp/irssi_icecast_bridge";
my $DEBUG = 1;
my $timer = '';

unlink $filename;
open FH, ">$filename";
print FH "";
close FH;
chmod 0777, $filename;

sub msg_to_channel {
	my ($tag, $target, $note, @rest) = @_;
	#dp("i here.. tag: $tag, target: $target, nick: $nick, note: $note");

	my @windows = Irssi::windows();
	foreach my $window (@windows) {

		next if $window->{name} eq '(status)';
		next unless $window->{active}->{type} eq 'CHANNEL';
		if($window->{active}->{name} eq $target && $window->{active_server}->{tag} eq $tag) {
			dp("Found! $window->{active}->{name}");
			$window->{active_server}->command("msg $window->{active}->{name} $note");
		}
	}
	return;
}

# check the socket for data and act upon it
sub check_file_icecast {
	my $msg = KaaosRadioClass::readLastLineFromFilename($filename);
	if ($msg ne '' && $msg ne '-3') {
		echota("Got message from file: $msg");
		if ($msg =~ /(.*?)$/) {
			my $data = $1;
            my $channel = "#salamolo";
            my $tag = "nerv";
			echota("Tag: $tag, Channel: $channel, data: $data");
			msg_to_channel($tag, $channel, $data);
		}
        KaaosRadioClass::writeToFile($filename, '');
	}
}

sub parse_mesg {
	my ($mesg, @rest) = @_;
}

sub echota {
	my ($msg, @rest) = @_;
	print("%G".$IRSSI{name}.">%n ".$msg);
}

sub dp {
	return unless $DEBUG == 1;
	print("%R".$IRSSI{name}." debug >%n @_");
	return;
}

sub da {
	return unless $DEBUG == 1;
	print("%R".$IRSSI{name}." debug>%n ");
	print(Dumper(@_));
	return;
}

my $timer = Irssi::timeout_add(1000, \&check_file_icecast, []);