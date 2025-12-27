use warnings;
use strict;
use Irssi;
use utf8;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;
use IO::Socket;
use Fcntl;
use JSON;
use Data::Dumper;
use DateTime::Format::Strptime;
use Number::Format qw(:subs :vars);
my $fi = new Number::Format(-decimal_point => ',', -thousands_sep => ' ');

# http://www.perl.com/pub/1998/12/cooper-01.html

use vars qw($VERSION %IRSSI);
$VERSION = '2025-05-02';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'fmi_weather.pl',
	description => 'Fetch data from fmi.fi',
	license     => 'Public Domain',
	url         => 'https://8-b.fi',
	changed     => $VERSION,
);

my $DEBUG = 0;
my $fmiURL = 'https://www.fmi.fi';
my $socket_file = "/tmp/irssi_fmi_weather.sock";
my $timeout_tag;
my $last_meteo = '';
fmi_update();
my $last_time;

my $users = {};
#my $fmi_script = "/home/laama/code/python/fmi1.py";
my $fmi_script = Irssi::get_irssi_dir() . '/scripts/irssi-scripts/fmi1.py';"";
# create the socket
unlink $socket_file;
my $my_socket = IO::Socket::UNIX->new(Local  => $socket_file,
								   Type   => SOCK_STREAM,
								   Listen => 5) or die $@;
# set this socket as nonblocking so we can check stuff without interrupting irssi.
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
		chomp($msg);
		prind("Got message from socket: $msg");# if $msg;
		if ($msg =~ /^Aja/) {
			if (parse_extrainfo_from_link($fmiURL)) {
				timeout_1h();
			}
		}
	}
}

sub prind {
	my ($text, @rest) = @_;
	print("\00310" . $IRSSI{name} . "\003> ". $text);
}
sub DP {
	return unless $DEBUG == 1;
	print($IRSSI{name}." debug> @_");
	return;
}

sub DA {
	return unless $DEBUG == 1;
	print($IRSSI{name}." array>");
	print Dumper @_;
	return;
}

# @TODO
sub print_help {
	my ($server, $targe, @rest) = @_;
	my $help = 'fmi-weather -skripti hakee päivän Meteorologin sääkatsauksen. Hakee myös säätiedot fmi.fi:stä';
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
		next unless ($window->{active_server}->{tag} eq "IRCNet");	# HACK, print on ircnet only
		if (index ($enabled_raw, $window->{active}->{name}) ne "-1") {
			DP(__LINE__ . " Found matching channel! $window->{active}->{name} at position: " . index ($enabled_raw, $window->{active}->{name}));
			$window->{active_server}->command("msg $window->{active}->{name} $text");
		}
	}
	return;
}

sub parse_extrainfo_from_link {
	my ($url, @rest) = @_;
	my $text = KaaosRadioClass::fetchUrl($url);
	my $date = '';
	if ($text =~ /Meteorologin sääkatsaus/) {
		# scroll the cursor to right position
	}
	# old: if ($text =~ /<span class="datetime"(.*?)>(.*?)<\/span>/gis) {
	if ($text =~ /<div class="font-bold">(.*?)<\/div>/is) {
	# example: <div class="font-bold">7.11.2025 21:50</div>
		$date = $1;

		# argument example: Tue, 04 Sep 2018 22:37:34 +0300 (using "%a, %d %b %Y %H:%M:%S %z")
		# We need: 15.3.2023 15:56
		my $formatter = DateTime::Format::Strptime->new(
        	pattern  => '%d.%m.%Y %H:%M',
			on_error => 'croak',
			time_zone => 'UTC'
    	);
		my $dt = $formatter->parse_datetime($date);
		$dt->set_time_zone('Europe/Helsinki');
		$date = $dt->strftime('%d.%m. %H:%M');
	}

	# old: if ($text =~ /<span class="meteotext"(.*?)>(.*?)<\/span>/gis) {
	if ($text =~ /<div class="text-blueberry">(.*?)<\/div>/gis) {
	# example: <div class="text-blueberry"><!----> Vesisadealue, joka yltää  Pohjanmaalta kaakonkulmalle, heikkenee ja kuihtuu yöllä, kuitenkin tihkusade jatkuu.  Myöhään iltapäivällä sadealue saapuu lännestä maan keskivaiheille, Kainuussa, Koillismaalla ja Etelä-Lapissa sataa hieman lunta, muualla vettä.</div>
		my $meteotext = $1;
		$meteotext =~ s/<div(.*?)>(.*?)<\/div>//gis;		# div inside span
		$meteotext =~ s/<!---->//gis;						# remove comments
		$meteotext =~ s/<(.*?)>//gis;						# remove any other html tags
		$meteotext = KaaosRadioClass::ktrim($meteotext);
		$meteotext = "\002Meteorologin sääkatsaus ($date):\002 ".$meteotext;
		DP(__LINE__.' meteotext: '. $meteotext);
		if ($meteotext ne $last_meteo) {
			msg_to_channel($meteotext);
			$last_meteo = $meteotext;
		}
	} else {
		return undef;
	}
	return 1;
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
	my $json = JSON->new->utf8;
	$json->convert_blessed(1);
	my $sayline = '';

	if ($msg =~ /^!meteo/) {
		if (get_channel_title($server, $target) =~ /npv?\:/i) {
			return;
		}
		$sayline = $last_meteo;
	} elsif ($msg =~ /^!f (.*)$/ || $msg =~ /^!fmi (.*)$/) {
		my $searchword = $1;
		check_user_city($searchword, $nick);
		my $result = `$fmi_script "$searchword"`;
		$json = decode_json($result);
		$sayline = getSayLine($json);
	} elsif ($msg =~ /^!fe (.*)$/ || $msg =~ /^!fmie (.*)$/) {
		my $searchword = $1;
		check_user_city($searchword, $nick);
		my $result = `$fmi_script "$searchword" ennustus`;
		$json = decode_json($result);
		$sayline = getSayLineEnnustus($json);
	} elsif ($msg eq '!f' || $msg eq '!fmi' && $users->{$nick}) {
		my $result = `$fmi_script "$users->{$nick}"`;
		$json = decode_json($result);
		$sayline = getSayLine($json);
	} elsif ($msg eq '!fe' || $msg eq '!fmie' && $users->{$nick}) {
		my $result = `$fmi_script "$users->{$nick}" ennustus`;
		$json = decode_json($result);
		$sayline = getSayLineEnnustus($json);
	}

	$server->command("msg $target $sayline") if $sayline;
}

sub getSayLine {
	my ($json, @rest) = @_;
	if (defined $json->{'status'} && $json->{'status'} eq 'error') {
		return $json->{'message'};
	}
	DA($json);
	my $sayline = '';
	$sayline .= "\002" .$json->{'place'} . ": ";
	$sayline .= '(' . $json->{'time'} . ")\002 ";
	$sayline .= $json->{'temperature'} . ', ';
	$sayline .= '(~ ' . $json->{'feels_like'} . '), ';
	$sayline .= 'Kosteus: ' . $json->{'humidity'} . ', ';
	$sayline .= '💧: ' . $json->{'precipitation_amount'} . ', ';
	$sayline .= '💨: ' . $json->{'wind_speed'} . ' ';
	$sayline .= '(' . $json->{'wind_gust'} . ') m/s, ';
	$sayline .= $json->{'pressure'} . ', ';
	$sayline .= '☁️ : ' . $json->{'cloud_cover'};
	return $sayline;
}

sub getSayLineEnnustus {
	my ($json, @rest) = @_;
	my $sayline = '';
	$sayline .= "\002" .$json->{place} . ":\002 ";
	my $json_ref = $json->{forecasts};
	foreach my $item (sort keys %$json_ref) {
		my $item = $json_ref->{$item};
		my $time = $item->{time};
		my $temperature = $item->{temperature};
		my $precipitation_amount = $item->{precipitation_amount};
		my $wind_speed = $item->{wind_speed};
		my $wind_gust = $item->{wind_gust};
		my $cloud_cover = $item->{cloud_cover};
		my $feels_like = $item->{feels_like};
		$sayline .= "\002$time:\002 ";
		$sayline .= "🌡️: " . $temperature . ", (~ $feels_like)";
		$sayline .= "💧: " . $precipitation_amount . ", ";
		#$sayline .= "💨: " . $wind_speed . ' (' . $wind_gust . ') m/s, ';
		$sayline .= '☁️ : ' . $cloud_cover . ", ";
	}
	print($sayline);
	return $sayline;
}	

sub check_user_city {
	my ($checkcity, $nick, @rest) = @_;
	$checkcity = KaaosRadioClass::ktrim($checkcity);
	if (!$checkcity) {
		if (defined $users->{$nick}) {
			dp(__LINE__ . ': ei löytynyt cityä syötteestä, vanha tallessa oleva: ' . $users->{$nick});
			return $users->{$nick};
		} else {
			return undef;
		}
	} else {
		$users->{$nick} = $checkcity;
		return $checkcity;
	}
}

sub event_priv {
	my ($server, $msg, $nick, $address) = @_;
	return if ($nick eq $server->{nick});	#self-test
	event_pubmsg($server, $msg, $nick, $address, $nick);
}

sub get_channel_title {
	my ($server, $channel) = @_;
	my $chanrec = $server->channel_find($channel);
	return '' unless defined $chanrec;
	return $chanrec->{topic};
}

sub fmi_update {
	prind("Fetching new weather data...");
	parse_extrainfo_from_link($fmiURL);
}

sub timeout_stop {
	prind("Stopping timeout: " . $timeout_tag);
	Irssi::timeout_remove($timeout_tag);
}

sub timeout_1h {
	DP("Aja 1h");
	prind('Creating new "at" run at "now +1 hours"..');
	my $command = 'echo "echo \"Aja1\" | nc -U '.$socket_file.'" | at now +1 hours 2>&1';
	my $retval = `$command`;
	DP $retval;
}
sub timeout_545 {
	my $command = 'echo "echo \"Aja2\" | nc -U '.$socket_file.'" | at 5:45 2>&1';
	my $retval = `$command`;
}
sub timeout_start {
	prind("Starting 5 sec timeout_add for reading the socket for new data...");
	timeout_1h();	# start only once
	#timeout_545();
	$timeout_tag = Irssi::timeout_add(5000, 'check_sock', undef);      # every 5 seconds
}

Irssi::command_bind('fmi_update', \&fmi_update, 'fmi_weather');
Irssi::command_bind('fmi_start', \&timeout_start, 'fmi_weather');
Irssi::command_bind('fmi_stop', \&timeout_stop, 'fmi_weather');
Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::signal_add_last('message private', 'event_priv');
Irssi::settings_add_str('fmi_weather', 'fmi_enabled_channels', '');

timeout_start();

prind("v. $VERSION Loaded!");
prind("/set fmi_enabled_channels #channel1 #channel2");
prind("Enabled on: ". Irssi::settings_get_str('fmi_enabled_channels'));
