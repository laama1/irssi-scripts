use strict;
use IO::Socket;
use Fcntl;
use Irssi;
# install next one: 
use Time::Format qw(%strftime);
use Data::Dumper;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;

use vars qw($VERSION %IRSSI);

$VERSION = '0.2';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'LAama1@ircnet',
	name        => 'muistuta.pl',
	description => 'provides an interface to irssi via unix sockets',
	license     => 'GPLv2',
	url         => 'http://quadpoint.org',
	changed     => '2025-10-05',
);

my $socket_file = "/tmp/irssi_muistuta.sock";
my $add_cron_script = "add_cron.sh";
my $DEBUG = 1;
my %timers = ();
my $window_name = 'muistuta';
my $counter = 0;
# delete old socket file if exists
unlink $socket_file;
# create the socket
my $my_socket = IO::Socket::UNIX->new(Local  => $socket_file,
								   Type   => SOCK_STREAM,
								   Listen => 5) or die $@;
chmod 0755, $socket_file;
# set this socket as nonblocking so we can check stuff without interrupting irssi.
nonblock($my_socket);

# method to set a socket handle as nonblocking
sub nonblock {
	my($fd) = @_;
	my $flags = fcntl($fd, F_GETFL, 0);
	fcntl($fd, F_SETFL, $flags | O_NONBLOCK);
}

sub msg_to_channel {
	my ($tag, $target, $nick, $note, @rest) = @_;
	#dp("i here.. tag: $tag, target: $target, nick: $nick, note: $note");

	my @windows = Irssi::windows();
	foreach my $window (@windows) {

		next if $window->{name} eq '(status)';
		next unless defined $window->{active}->{type} && $window->{active}->{type} eq 'CHANNEL';

		if($window->{active}->{name} eq $target && $window->{active_server}->{tag} eq $tag) {
			dp("Found! $window->{active}->{name}");
			$window->{active_server}->command("msg $window->{active}->{name} $nick, muistathan.. $note");
		}
	}
	return;
}

# parse bad characters that might trigger linux commands when using "at"
sub parse_bad {
	my ($word, @test) = @_;
	$word =~ s/\./ /g;	# .	with space
	#$word =~ s/\s.*//;  # multiple spaces
	$word =~ s/"//g;	# "
	$word =~ s/\///g;	# /
	$word =~ s/\|//g;	# |
	$word =~ s/\$//g;	# $
	return $word;
}

sub event_pubmsg {
	my ($server, $msg, $nick, $address, $target) = @_;
	return if $nick eq $server->{nick};		# self test
	return unless $msg =~ /^!muistut/;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday, $yday, $isdst) = localtime(time);
	my ($unit, $value, $note);

	if ($msg =~ /^!muistuta ([1-9])\s?h ?(.*)$/ || $msg =~ /^!muistuta ([1-9])\s?t ?(.*)$/) {
		# 1-9 hours. Try to keep script loaded until that.
		$unit = 'hours';
		$value = $1;
		$note = $2;
		$timers{$nick}{$counter++} = {
			'tag' => Irssi::timeout_add_once(($value*1000*60*60), \&timer_func, $server->{tag}.', '.$target.', '.$nick.', '.$counter.', '.$note),
			'note' => $note
		};
		$server->command("msg -channel $target ööh juu koitan muistaa muistuttaa.. (${value}h)");
	} elsif ($msg =~ /^!muistuta (\d+)\s?sek ?(.*)$/ || $msg =~ /^!muistuta (\d+)\s?s ?(.*)$/) {
		# some seconds
		$unit = 'seconds';
		$value = $1;
		$note = $2;
		$timers{$nick}{$counter++} = {
			'tag' => Irssi::timeout_add_once(($value*1000), \&timer_func, $server->{tag}.', '.$target.', '.$nick.', '.$counter.', '.$note),
			'note' => $note
		};
		$server->command("msg -channel $target juubajuu koitan muistaa muistuttaa.. (${value}s)");
	} elsif ($msg =~ /^!muistuta (\d+)\s?h ?(.*)$/ || $msg =~ /^!muistuta (\d+)\s?t ?(.*)$/) {
		# 10+ hours. create at-command job.
		$unit = 'hours';
		$value = $1;
		$note = $2;
		chomp(my $cron_hour = `date --date="$value $unit" +"%H"`);
		chomp(my $cron_day = `date --date="$value $unit" +"%d"`);
		chomp(my $cron_month = `date --date="$value $unit" +"%m"`);
		create_at_command($server, $target, $nick, $value.' '. $unit, $note);

		$server->command("msg -channel $target jeh juu koitan muistaa muistuttaa.. (${value}h)");
	} elsif ($msg =~ /^!muistuta (\d+)\s?kk ?(.*)$/) {
		# months
		$unit = 'months';
		$value = $1;
		$note = $2;
		chomp(my $cron_hour = `date --date="$value $unit" +"%H"`);
		#$cron_hour = chomp $cron_hour;
		chomp(my $cron_day = `date --date="$value $unit" +"%d"`);
		#$cron_day = chomp $cron_day;
		chomp(my $cron_month = `date --date="$value $unit" +"%m"`);
		#$cron_month = chomp $cron_month;
		#my $cron_year = chomp `date --date="$value $unit" +"%Y"`;
		#$cron_year = chomp $cron_year;
		$note = parse_bad($note);
		create_cronjob($server, $target, $nick, "0", $cron_hour, $cron_day, $cron_month, $note);
		$server->command("msg -channel $target ööh juu koitan muistaa muistuttaa.. Tallensinkohan.. (${value}kk)");
	} elsif ($msg =~ /^!muistuta (\d+)\s?pv ?(.*)$/ || $msg =~ /^!muistuta (\d+)\s?d ?(.*)$/) {
		# days
		$unit = 'days';
		$value = $1;
		$note = $2;
		chomp(my $cron_hour = `date --date="$value $unit" +"%H"`);
		#$cron_hour = chomp $cron_hour;
		chomp(my $cron_day = `date --date="$value $unit" +"%d"`);
		#$cron_day = chomp $cron_day;
		chomp(my $cron_month = `date --date="$value $unit" +"%m"`);
		#$cron_month = chomp $cron_month;
		#my $cron_year = chomp `date --date="$value $unit" +"%Y"`;
		$note = parse_bad($note);
		create_cronjob($server, $target, $nick, "0", $cron_hour, $cron_day, $cron_month, $note);

		$server->command("msg -channel $target ööh juu koitan muistaa muistuttaa.. Tallensinkohan... (${value}pv)");
	} elsif ($msg =~ /^!muistuta (\d+)\s?min ?(.*)$/ || $msg =~ /^!muistuta (\d+)\s?m ?(.*)$/) {
		prind("$msg from: $target, $nick");
		$unit = 'minutes';
		$value = $1;
		$note = $2;
		$note = parse_bad($note);
		$timers{$nick}{$counter++} =  {
			'tag' => Irssi::timeout_add_once(($value*1000*60), \&timer_func, $server->{tag}.', '.$target.', '.$nick.', '.$counter.', '.$note),
			'note' => $note
		};
		$server->command("msg -channel $target ööh juu koitan muistaa muistuttaa.. (${value}m)");
	}
	
	elsif ($msg =~ /!muistutukset/) {
		print_muistutukset();
		#foreach my $data (%timers{$nick}) {
		#	$server->command("msg -channel $target Muistutus: $data => " . $timers{$nick}->{$data}->{'note'} . ", tag: " . $timers{$nick}->{$data}->{'tag'});
		#}

	}

	else {
		$server->command("msg -channel $target Käytä: !muistuta <aika> <viesti>, missä aika on esim. 10s, 5min, 2h, 3pv, 1kk. Esim: !muistuta 10min Käy hakemassa maito.");
		#$server->command("msg -channel $target Katso myös: !muistutukset");
	}
	return;
}

sub timer_func {
	my ($data, @rest) = @_;
	if ($data =~ /(.*?), (.*?), (.*?), (.*?), (.*)$/) {
		my $servertag = $1;
		my $target = $2;
		my $nick = $3;
		my $counter = $4;
		my $note = $5;
		prind("Timer launched: Server tag: $servertag, Target: $target, nick: $nick, counter: $counter, note: $note");
		msg_to_channel($servertag, $target, $nick, $note);
		remove_timer($nick, $counter);
	}
}

sub remove_timer {
	my ($nick, $counter, @rest) = @_;
	if (exists $timers{$nick}{$counter}) {
		Irssi::timeout_remove($timers{$nick}->{'tag'});
		delete $timers{$nick};
		prind("Muistutus poistettu: $nick");
	} else {
		prind("Ei muistutusta nimellä: $nick");
	}
}

sub create_at_command {
	my ($server, $target, $nick, $time, $note, @rest) = @_;
	my $command = 'echo "echo \"'.$server->{tag}.', '.$target.', '.$nick.', '.$note.'\" | nc -U '.$socket_file.'" | at now +'.$time;
	create_window($window_name);
	chomp(my $retval = `$command`);
	printa("At-command created: ".$command.", retval: ". $retval);
	$timers{$nick}{$counter++} = {
		'tag' => 'at_command',
		'note' => $note
	};
}

sub create_cronjob {
	my ($server, $target, $nick, $min, $hour, $dom, $mo, $note, @rest) = @_;
	my $command = 'echo "'.$server->{tag}.', '.$target.', '.$nick.', '.$note.'" | nc -U '.$socket_file;
	create_window($window_name);
	printa("Command: " . $command);
	my $commandline = '/home/laama/.irssi/scripts/irssi-scripts/add_cron.sh '.$min.' '.$hour.' '.$dom.' '.$mo.' * '. $command;
	printa("Commandline: ".$commandline);
	Irssi::command("exec -name create_cronjob -interactive $commandline");

	$timers{$nick}{$counter++} =  {
		'tag' => 'cronjob',
		'note' => $note
	};
}

# check the socket for data and act upon it
sub check_sock {
	my $msg;
	if (my $client = $my_socket->accept()) {
		$client->recv($msg, 1024);
		if ($msg =~ /(.*?), (.*?), (.*?), (.*?), (.*)$/) {
			my $tag = $1;
			my $target = $2;
			my $nick = $3;
			my $counter = $4;
			my $note = $5;
			prind("Got message from socket: tag: $tag, target: $target, nick: $nick, counter: $counter, note: $note");
			remove_timer($nick, $counter);
			msg_to_channel($tag, $target, $nick, $note);
		}
	}
}

sub print_muistutukset {
	my ($data, @rest) = @_;
	da(__LINE__, 'Timers:', %timers);
	create_window($window_name);
	printa("At queue:");
	Irssi::command("exec -name atq -interactive atq");
	foreach my $data (%timers) {
		printa("Muistutus: $data => " . $timers{$data}->{'note'} . ", tag: " . $timers{$data}->{'tag'});
	}
}

sub create_window {
    my ($window_name) = @_;
    my $window = Irssi::window_find_name($window_name);
    unless ($window) {
        prind("Create new window: $window_name");
        Irssi::command("window new hidden");
        Irssi::command("window name $window_name");
    }
    Irssi::command("window goto $window_name");
}

sub prind {
	my ($msg, @rest) = @_;
	print("%G".$IRSSI{name}.">%n " . $msg);
}

# print to active window
sub printa {
	my ($msg, @rest) = @_;
	Irssi::active_win()->print("%G".$IRSSI{name}.">%n " . $msg);
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

my $timer_socket = Irssi::timeout_add(500, \&check_sock, []);

Irssi::signal_add('message public', 'event_pubmsg');
Irssi::command_bind('muistutukset', 'print_muistutukset', 'muistuta');
#Irssi::signal_add('message private', 'event_privmsg');
prind("$IRSSI{name} v$VERSION loaded.");
