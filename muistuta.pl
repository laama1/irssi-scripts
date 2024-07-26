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

$VERSION = '0.1';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'LAama1@ircnet',
	name        => 'muistuta',
	description => 'provides an interface to irssi via unix sockets',
	license     => 'GPLv2',
	url         => 'http://quadpoint.org',
	changed     => '2022-01-09',
);

my $socket_file = "/tmp/irssi_muistuta.sock";
my $add_cron_script = "add_cron.sh";
my $DEBUG = 1;
my $timer = '';
# delete old
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

	if ($msg =~ /^!muistuta ([1-9])h ?(.*)$/) {
		# 1-9 hours. Try to keep script loaded until that.
		$unit = 'hours';
		$value = $1;
		$note = $2;
		$timer = Irssi::timeout_add_once(($value*1000*60*60), \&timer_func, $server->{tag}.', '.$target.', '.$nick.', '.$note);
		$server->command("msg -channel $target ööh juu koitan muistaa muistuttaa.. (${value}h)");
	} elsif ($msg =~ /^!muistuta (\d+)sek ?(.*)$/ || $msg =~ /^!muistuta (\d+)s ?(.*)$/) {
		# some seconds
		$unit = 'seconds';
		$value = $1;
		$note = $2;
		$timer = Irssi::timeout_add_once(($value*1000), \&timer_func, $server->{tag}.', '.$target.', '.$nick.', '.$note);
		$server->command("msg -channel $target ööh juu koitan muistaa muistuttaa.. (${value}s)");
	} elsif ($msg =~ /^!muistuta (\d+)h ?(.*)$/) {
		# 10+ hours. create a cron job.
		$unit = 'hours';
		$value = $1;
		$note = $2;
		my $cron_hour = `date --date="$value $unit" +"%H"`;
		my $cron_day = `date --date="$value $unit" +"%d"`;
		my $cron_month = `date --date="" +"%m"`;
		create_at_command($server, $target, $nick, $value.' '. $unit, $note);
		$server->command("msg -channel $target ööh juu koitan muistaa muistuttaa.. (${value}h)");
	} elsif ($msg =~ /^!muistuta (\d+)kk ?(.*)$/) {
		# months
		$unit = 'months';
		$value = $1;
		$note = $2;
		my $cron_hour = `date --date="$value $unit" +"%H"`;
		$cron_hour = chomp $cron_hour;
		my $cron_day = `date --date="$value $unit" +"%d"`;
		$cron_day = chomp $cron_day;
		my $cron_month = `date --date="$value $unit" +"%m"`;
		$cron_month = chomp $cron_month;
		#my $cron_year = chomp `date --date="$value $unit" +"%Y"`;
		#$cron_year = chomp $cron_year;
		$note = parse_bad($note);
		create_cronjob($server, $target, $nick, "0", $cron_hour, $cron_day, $cron_month, $note);
		$server->command("msg -channel $target ööh juu koitan muistaa muistuttaa.. Tallensinkohan.. (${value}kk)");
	} elsif ($msg =~ /^!muistuta (\d+)pv ?(.*)$/ || $msg =~ /^!muistuta (\d+)d ?(.*)$/) {
		# days
		$unit = 'days';
		$value = $1;
		$note = $2;
		my $cron_hour = `date --date="$value $unit" +"%H"`;
		$cron_hour = chomp $cron_hour;
		my $cron_day = `date --date="$value $unit" +"%d"`;
		$cron_day = chomp $cron_day;
		my $cron_month = `date --date="$value $unit" +"%m"`;
		$cron_month = chomp $cron_month;
		#my $cron_year = chomp `date --date="$value $unit" +"%Y"`;
		$note = parse_bad($note);
		create_cronjob($server, $target, $nick, "0", $cron_hour, $cron_day, $cron_month, $note);
		$server->command("msg -channel $target ööh juu koitan muistaa muistuttaa.. Tallensinkohan... (${value}pv)");
	} elsif ($msg =~ /^!muistuta (\d+)min ?(.*)$/ || $msg =~ /^!muistuta (\d+)m ?(.*)$/) {
		echota("$msg from: $target, $nick");
		$unit = 'minutes';
		$value = $1;
		$note = $2;
		$note = parse_bad($note);
		$timer = Irssi::timeout_add_once(($value*1000*60), \&timer_func, $server->{tag}.', '.$target.', '.$nick.', '.$note);
		$server->command("msg -channel $target ööh juu koitan muistaa muistuttaa.. (${value}m)");
	}
	
	elsif ($msg =~ /!muistutukset/) {
		Irssi::command("exec -name atq -interactive atq");
	}
	return;
}

sub timer_func {
	my ($data, @rest) = @_;
	echota("timer_func Data: $data");
	if ($data =~ /(.*?), (.*?), (.*?), (.*)$/) {
		my $servertag = $1;
		my $target = $2;
		my $nick = $3;
		my $note = $4;
		echota("Tag: $servertag, Target: $target, nick: $nick, note: $note");
		msg_to_channel($servertag, $target, $nick, $note);
	}
}

sub create_at_command {
	my ($server, $target, $nick, $time, $note, @rest) = @_;
	my $command = 'echo "echo \"'.$server->{tag}.', '.$target.', '.$nick.', '.$note.'\" | nc -U '.$socket_file.'" | at now +'.$time;
	my $retval = `$command`;
	echota("at-komento luotu: ".$command.", retval: ". $retval);
}

sub create_cronjob {
	my ($server, $target, $nick, $min, $hour, $dom, $mo, $note, @rest) = @_;
	my $command = 'echo "'.$server->{tag}.', '.$target.', '.$nick.', '.$note.'" | nc -U '.$socket_file;
	echota("Command: ".$command. "<");
	my $commandline = '/home/laama/.irssi/scripts/irssi-scripts/add_cron.sh '.$min.' '.$hour.' '.$dom.' '.$mo.' * '. $command;
	echota("Commandline: ".$commandline);
	Irssi::command("exec -name create_cronjob -interactive $commandline")
	#my $retval = `/home/laama/.irssi/scripts/irssi_scripts/add_cron.sh $min $hour $dom $mo $command $note`;
	#echota("cron-rivi luotu, retval: ". $retval . "<");
}

# check the socket for data and act upon it
sub check_sock {
	my $msg;
	if (my $client = $my_socket->accept()) {
		$client->recv($msg, 1024);
		echota("Got message from socket: $msg") if $msg;
		if ($msg =~ /(.*?), (.*?), (.*?), (.*)$/) {
			my $tag = $1;
			my $target = $2;
			my $nick = $3;
			my $note = $4;
			echota("Tag: $tag, Target: $target, nick: $nick, note: $note");
			msg_to_channel($tag, $target, $nick, $note);
		}
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

my $timer = Irssi::timeout_add(250, \&check_sock, []);

Irssi::signal_add('message public', 'event_pubmsg');
#Irssi::signal_add('message private', 'event_privmsg');
