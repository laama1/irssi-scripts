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
my $socket_file = "/tmp/irssi_fmi_weather.sock";
my $timeout_tag;
my $last_meteo = '';
my $last_time;

# create the socket
unlink $socket_file;
my $my_socket = IO::Socket::UNIX->new(Local  => $socket_file,
								   Type   => SOCK_STREAM,
								   Listen => 5) or die $@;
# set this socket as nonblocking so we can check stuff without interrupting
# irssi.
nonblock($my_socket);
$my_socket->autoflush();

# method to set a socket handle as nonblocking
sub nonblock {
	my($fd) = @_;
	my $flags = fcntl($fd, F_GETFL, 0);
	fcntl($fd, F_SETFL, $flags | O_NONBLOCK);
}

# check the socket for data and act upon it
sub check_sock {
	my $msg;
	if (my $client = $my_socket->accept()) {
		$client->recv($msg, 1024);
		echota("Got message from socket: $msg");# if $msg;
		#if ($msg =~ /Aja$/) {
		if ($msg =~ /^Aja/) {
			DP(__LINE__." AJA!");
			if (parse_extrainfo_from_link($fmiURL)) {
				timeout_1h();
			}
		}
	}
}

sub echota {
	my ($texti, @rest) = @_;
	print($IRSSI{name}."> ". $texti);
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
		next unless defined $window->{active}->{type} && $window->{active}->{type} eq 'CHANNEL';

		if($window->{active}->{name} ~~ @enabled) {
			DP(__LINE__." Found! $window->{active}->{name}");
			$window->{active_server}->command("msg $window->{active}->{name} $text");
		}
	}
	return;
}

sub parse_extrainfo_from_link {
	my ($url, @rest) = @_;
	DP(__LINE__.' going stronk!0');
	my $text = KaaosRadioClass::fetchUrl($url);
	my $date = '';
	if ($text =~ /<span class="datetime"(.*?)>(.*?)<\/span>/gis) {
		$date = $2;
		DP(__LINE__.' date found: '.$date);
	}
	DP(__LINE__.' going stronk!1');
	if ($text =~ /<span class="meteotext"(.*?)>(.*?)<\/span>/gis) {
		my $meteotext = $2;
		$meteotext =~ s/<div(.*?)>(.*?)<\/div>//gis;
		$meteotext = KaaosRadioClass::ktrim($meteotext);
		$meteotext = "\002Meteorologin sääkatsaus ($date GMT):\002 ".$meteotext;
		DP(__LINE__.' meteotext: '. $meteotext);
		if ($meteotext ne $last_meteo) {
			msg_to_channel($meteotext);
			$last_meteo = $meteotext;
		}
	} else {
		DP(__LINE__.' NOT FOUND :(');
		return undef;
	}
	return 1;
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
	if ($msg =~ /^!meteo/) {
		if ($last_meteo eq '') {
			fmi_update();
		}
		$server->command("msg $target $last_meteo");
	}
}

sub fmi_update {
	echota("Fetching new weather data...");
	parse_extrainfo_from_link($fmiURL);
}

sub timeout_stop {
	timeout_remove($timeout_tag);
}

sub timeout_1h {
	echota(__LINE__.": Aja1");
	my $command = 'echo "echo \"Aja1\" | nc -U '.$socket_file.'" | at now + 1 hours 2>&1';
	my $retval = `$command`;
}
sub timeout_545 {
	my $command = 'echo "echo \"Aja2\" | nc -U '.$socket_file.'" | at 5:45 2>&1';
	my $retval = `$command`;
}
sub timeout_start {
	timeout_1h();
	#timeout_545();
	$timeout_tag = Irssi::timeout_add(10000, 'check_sock', undef);      # 10 seconds
}

Irssi::command_bind('fmi_update', \&fmi_update, 'fmi_weather');
Irssi::command_bind('fmi_start', \&timeout_start, 'fmi_weather');
Irssi::command_bind('fmi_stop', \&timeout_stop, 'fmi_weather');
Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::settings_add_str('fmi_weather', 'fmi_enabled_channels', 'Add channels where to print meteo.');
	
timeout_start();

print($IRSSI{name}."> v. $VERSION Loaded!");
print($IRSSI{name}."> /set fmi_enabled_channels #channel1 #channel2");
print($IRSSI{name}."> Enabled on: ". Irssi::settings_get_str('fmi_enabled_channels'));
