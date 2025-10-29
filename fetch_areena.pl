# skripti lataa yleareena-linkin takaa löytyvät videot ja äänet.
# LAama1 4.4.2020
use strict;
use warnings;
use Irssi;
use JSON;
use Data::Dumper;
use vars qw($VERSION %IRSSI);
$VERSION = '2025-10-27';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'fetch_areena.pl',
	description => 'Download video and audio from YLE Areena or yle.fi.',
	license     => 'Public Domain',
	url         => '',
	changed     => $VERSION,
);

my $DEBUG = 1;
my $runningnumber = 0;
#if you have Finnish proxy, use it here.
#my $userpass = 'roxylady:Proxy_P455u';
#my $proxy = " --proxy ${userpass}@83.148.240.11:31280";
my $proxy = '';
my $download_dir = $ENV{"HOME"} . "/public_html/areena";
my $ylescript = 'yle-dl -qq --vfat --restrict-filename-no-spaces --destdir '.$download_dir.' --maxbitrate best' . $proxy;
#my $execscript = 'exec -interactive -name yle-dl_';
my $execscript = 'exec -window -name yle-dl_';
my $logfile = Irssi::get_irssi_dir() . '/scripts/yle.log';
my $kanava1 = '#salamolo';
prind('Download dir: '.$download_dir);
my $processes = {};

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;

	if ($msg =~ /(https?:\/\/areena\.yle\.fi\/\S+)/i || 
		$msg =~ /(https?:\/\/yle\.fi\S+)/i || 
		$msg =~ /(https?:.*\.yle\.fi\S+)/i) {
		my $count = 0;
		if ($count = cmd_check_if_exist($1)) {
			create_window('yle-dl');
			#debu(__LINE__ . ": Found $count items. Starting download.");
			cmd_start_dl($1, $count, find_window_refnum($server, $target));
		}
	}
}

sub find_window_refnum {
	my ($server, $channel, @rest) = @_;
	my $server_tag = $server->{tag};
	my @windows = Irssi::windows();
	
	foreach my $window (@windows) {
		next if $window->{name} eq '(status)';
		next unless $window->{active}->{type} eq 'CHANNEL';
		next unless $window->{active}->{server}->{tag} eq $server_tag;

		if($window->{active}->{name} eq $channel) {
			return $window->{refnum};
		}
	}
	return -1;
}

sub print_window_data {
	my $window = Irssi::active_win();
	print Dumper $window;
	print 'Tag: ' .$window->active_server->tag;
	print 'Refnum: ' . $window->{refnum};
	print 'Channel name: ' . $window->active->{visible_name};
	print 'Channel server tag: ' . $window->active->server->tag
}

# signal is sent from urltitle3.pl
sub sig_yle_url {
	my ($server, $target, $rimpsu, @rest) = @_;
	prind('yle_url signal received, string: ' . $rimpsu);
	Irssi::signal_stop();
	my ($region, $title, $desc) = get_title_desc($rimpsu);
	if ($title or $desc) {
		my $responsetext = "\002Region:\002 $region \002Title:\002 $title \002Desc:\002 $desc";
		$responsetext =~ s/(.{300})(.*)/$1 .../;		# shorten desc over 300 chars
		$server->command("msg -channel $target $responsetext");
	}
}

# return first found item title and description
sub get_title_desc {
	my ($yleurl, @rest) = @_;
	my $output = `yle-dl --showmetadata ${yleurl} 2>>${logfile}`;
	if ($output eq '') {
		debu(__LINE__ . ' No metadata found.');
		return;
	}
	my $json = JSON->new->utf8;
	$json->convert_blessed(1);
	$json = decode_json($output);
	my $resultcount = scalar @$json;
	my $extrastring = '';
	if ($resultcount > 1) {
		$extrastring = " (löytyi $resultcount)";
	}
	foreach my $item (@$json) {
		# TODO: tell something about the rest of the episodes too?
		my $region = $item->{region};
		prind('Episode title: ' . $item->{episode_title} . ', episode description: ' . $item->{description});
		return $region, $item->{episode_title} . $extrastring, $item->{description};
	}
}

sub create_window {
    my ($window_name) = @_;
    my $window = Irssi::window_find_name($window_name);
    unless ($window) {
        prind("Create new window: $window_name");
        Irssi::command("window new hidden");
        Irssi::command("window name $window_name");
		debu("Window created: " . Irssi::active_win()->{name});
    }
    Irssi::command("window goto $window_name");
}

# check if metadata available and how many items
sub cmd_check_if_exist {
	my ($url, @rest) = @_;
	create_window('yle-dl');
	prind('Checking YLE url for metadata: '. $url);
	my $temptime = time();
	my $output = `yle-dl -V --showmetadata ${url} 2>${logfile}`;
	if ($output eq '') { return; }

	my $json = JSON->new->utf8;
	$json->convert_blessed(1);
	$json = decode_json($output);
	
	#debu(__LINE__ . ' JSON data: ' . Dumper($json));
	my $resultcount = scalar @$json;
	debu('Metadata found in ' . (time() - $temptime) . ' seconds. Itemcount: ' . $resultcount);
	return $resultcount;
}

sub cmd_start_dl {
	return;	# Dont start downloads automatically for now.
	my ($url, $count, $window_number) = @_;
	$runningnumber += 1;
	create_window('yle-dl');
	Irssi::command($execscript . "${runningnumber}_${count}_$window_number $ylescript $url");
}

# https://fossies.org/dox/irssi-1.4.5/fe-exec_8h_source.html
sub exec_new {
	my ($res) = @_;
	my $process_name = $res->{name};
	if ($process_name !~ /^yle-dl/) {
		return;
	}

	my $runningnum = -1;
	my $itemcount = -1;
	my $winnum = -1;
	my $server = '';
	my $channel = '';

	if ($process_name =~ /_(\d+)_(\d+)_(\d+)$/) {
		$runningnum = $1;
		$itemcount = $2;
		$winnum = $3;
		my $target_window = Irssi::window_find_refnum($winnum);
		if (defined $target_window) {
			$server = $target_window->{active}->{server}->{tag};
			$channel = $target_window->{active}->{visible_name};
		}
	}

	$processes->{$res->{pid}}->{name} = $process_name;
	$processes->{$res->{pid}}->{timestamp} = time();
	my $extrastring = '';
	if ($itemcount > 1) {
		$extrastring = " ($itemcount items)";
	}
	Irssi::server_find_tag($server)->command("msg $channel $process_name starting download${extrastring}.");
	Irssi::window_find_refnum($winnum)->print("\00312" . $IRSSI{name} . ">\003 $process_name starting download${extrastring}.");
}

sub exec_remove {
	my ($res, $status, @rest) = @_;
	my $process_name = $res->{name};
	if ($process_name !~ /^yle-dl/) {
		return;
	}

	my $runningnum = -1;
	my $itemcount = -1;
	my $winnum = -1;
	my $server = '';
	my $channel = '';

	if ($process_name =~ /_(\d+)_(\d+)_(\d+)$/) {
		$runningnum = $1;
		$itemcount = $2;
		$winnum = $3;
		my $target_window = Irssi::window_find_refnum($winnum);
		if (defined $target_window) {
			$server = $target_window->{active}->{server}->{tag};
			$channel = $target_window->{active}->{visible_name};
		}
	}
	create_window('yle-dl');

	debu(__LINE__ . ' exec_remove, pid: '. $res->{pid} . ', args: '. $res->{args} . ', silent: '. $res->{silent} . 
	' shell: '. $res->{shell} . ', channel: ' . $channel . ', server tag: ' . $server .
	#' target_win: '. Dumper($res->{target_win}) . 
	', status: '. $status);

	my $elapsed = time() - $processes->{$res->{pid}}->{timestamp};

	if ($status == 0 && $winnum != -1) {
		Irssi::server_find_tag($server)->command("msg $channel $process_name finished in $elapsed seconds.");
	} elsif ($winnum != -1) {
		Irssi::server_find_tag($server)->command("msg $channel $process_name failed with status $status after $elapsed seconds.");
	} else {
		debu(__LINE__ . ' No valid window number found in process name.');
	}
	
	delete $processes->{$res->{pid}};
}

# Data the process will output (errores, when errors redirected to stdout)
sub exec_input {
	my ($res, $text, @rest) = @_;
	$text =~ s/\t/  /;
	prind('exec_input text: ' . $text);
	debu(Dumper(__LINE__, $res));
}

sub debu {
	my ($text, @rest) = @_;
	return unless $DEBUG;
	create_window('yle-dl');
	Irssi::active_win()->print($IRSSI{name}.'> '. $text);
}

sub prind {
	my ($text, @test) = @_;
	print("\00311" . $IRSSI{name} . ">\003 ". $text);
}

Irssi::signal_add("exec new", 'exec_new');
Irssi::signal_add("exec remove", 'exec_remove');
Irssi::signal_add("exec input", 'exec_input');

Irssi::signal_add('message public', 'sig_msg_pub');
Irssi::signal_add('yle_url', 'sig_yle_url');
Irssi::command_bind('window_info', 'print_window_data', 'fetch_areena');
prind('v. '. $IRSSI{changed} . ' loaded.');
