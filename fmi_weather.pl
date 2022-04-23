use warnings;
use strict;
use Irssi;
use utf8;
use KaaosRadioClass;
use IO::Socket;
use Fcntl;

#use Data::Dumper;
#use DateTime::Format::Strptime;
#use Time::Piece;
#use Encode qw/encode decode/;

# http://www.perl.com/pub/1998/12/cooper-01.html

use vars qw($VERSION %IRSSI);
$VERSION = '2022-01-31';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'fmi_weather.pl',
	description => 'Fetch data from fmi.fi',
	license     => 'Public Domain',
	url         => 'https://8-b.fi',
	changed     => $VERSION,
);

my $DEBUG = 1;
my $fmiURL = 'https://www.fmi.fi';
my $socket = "/tmp/irssi_fmi_weather.sock";
my $timeout_tag;
my $last_meteo;
my $last_time;

# create the socket
unlink $socket;
my $server = IO::Socket::UNIX->new(Local  => $socket,
								   Type   => SOCK_STREAM,
								   Listen => 5) or die $@;
# set this socket as nonblocking so we can check stuff without interrupting
# irssi.
nonblock($server);

# method to set a socket handle as nonblocking
sub nonblock {
	my($fd) = @_;
	my $flags = fcntl($fd, F_GETFL, 0);
	fcntl($fd, F_SETFL, $flags | O_NONBLOCK);
}

# check the socket for data and act upon it
sub check_sock {
	my $msg;
	if (my $client = $server->accept()) {
		$client->recv($msg, 10);
		DP("Got message from socket: $msg") if $msg;
		if ($msg =~ /Aja$/) {
			DP("AJA!");
			parse_extrainfo_from_link($fmiURL);
			timeout_1h();
		}
	}
}

sub DP {
	return unless $DEBUG == 1;
	print($IRSSI{name}." debug> @_");
	return;
}

sub DA {
	return unless $DEBUG == 1;
	print($IRSSI{name}." array>");
	print Dumper (@_);
	return;
}

sub print_help {
	my ($server, $targe, @rest) = @_;
	my $help = 'fmi-weather -skripti hakee päivän Meteorologin sääkatsauksen.';
	return;
}

sub msg_to_channel {
	my ($text, @rest) = @_;
	my $enabled_raw = Irssi::settings_get_str('fmi_enabled_channels');
	my @enabled = split / /, $enabled_raw;

	my @windows = Irssi::windows();
	foreach my $window (@windows) {
		next if $window->{name} eq '(status)';
		next unless $window->{active}->{type} eq 'CHANNEL';

		if($window->{active}->{name} ~~ @enabled) {
			DP(__LINE__." Found! $window->{active}->{name}");
			$window->{active_server}->command("msg $window->{active}->{name} $text");
		}
	}
	return;
}

sub parse_extrainfo_from_link {
	my ($url, @rest) = @_;
	my $text = KaaosRadioClass::fetchUrl($url);
	my $date = '';
	if ($text =~ /<span class="datetime"(.*?)>(.*?)<\/span>/gis) {
		$date = $2;
	}
	if ($text =~ /<span class="meteotext"(.*?)>(.*?)<\/span>/gis) {
		my $meteotext = $2;
		$meteotext =~ s/<div(.*?)>(.*?)<\/div>//gis;
		$meteotext = KaaosRadioClass::ktrim($meteotext);
		$meteotext = 'Meteorologin sääkatsaus ('.$date.' GMT): '.$meteotext;
		DP(__LINE__.' meteotext: '. $meteotext);
		if ($meteotext ne $last_meteo) {
			msg_to_channel($meteotext);
			$last_meteo = $meteotext;
		}
	} else {
		DP(__LINE__.' NOT FOUND :(');
	}
	return;
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
	if ($msg =~ /^!meteo/) {
		$server->command("msg $target $last_meteo");
	}
}


sub timeout_stop {
	timeout_remove($timeout_tag);
}

sub timeout_1h {
	my $command = 'echo "echo \"Aja\" | nc -U '.$socket.'" | at now + 1 hours';
	my $retval = `$command`;
}
sub timeout_545 {
	my $command = 'echo "echo \"Aja\" | nc -U '.$socket.'" | at 5:45';
	my $retval = `$command`;
}
sub timeout_start {
	timeout_1h();
	#timeout_545();
	$timeout_tag = Irssi::timeout_add(10000, 'check_sock', undef);      # 10 seconds
}

Irssi::command_bind('fmi_update', \&parse_extrainfo_from_link, 'fmi_weather');
Irssi::command_bind('fmi_start', \&timeout_start, 'fmi_weather');
Irssi::command_bind('fmi_stop', \&timeout_stop, 'fmi_weather');
Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::settings_add_str('fmi_weather', 'fmi_enabled_channels', 'Add channels where to print meteo.');
	
timeout_start();

print($IRSSI{name}."> v. $VERSION Loaded!");
print($IRSSI{name}."> /set fmi_enabled_channels #channel1 #channel2");
print($IRSSI{name}."> Enabled on: ". Irssi::settings_get_str('fmi_enabled_channels'));