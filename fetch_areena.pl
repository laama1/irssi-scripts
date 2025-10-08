# skripti lataa yleareena-linkin takaa löytyvät videot ja äänet.
# LAama1 4.4.2020
use strict;
use warnings;
use Irssi;
use JSON;
use Data::Dumper;
use vars qw($VERSION %IRSSI);
$VERSION = '2025-10-05';
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
#my $userpass = 'roxylady:Proxy_P455u';
#if you have Finnish proxy, use it here.
#my $proxy = " --proxy ${userpass}@83.148.240.11:31280";
my $proxy = '';
my $download_dir = "/mnt/music/areena";
#my $ylescript = 'yle-dl -qq --vfat --no-overwrite --destdir '.$download_dir.' --maxbitrate best';
my $ylescript = 'yle-dl -qq --vfat --destdir '.$download_dir.' --maxbitrate best' . $proxy;
#my $execscript = 'exec -msg yle-dl -name ';
#my $execscript = 'exec -window -name yledl ';
my $execscript = 'exec -interactive -name yledl ';
my $logfile = Irssi::get_irssi_dir() . '/scripts/yle.log';

prind('download dir: '.$download_dir);

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	if ($msg =~ /(https?:\/\/areena\.yle\.fi\/\S+)/i || 
		$msg =~ /(https?:\/\/yle\.fi\S+)/i || 
		$msg =~ /(https?:.*\.yle\.fi\S+)/i) {
		if (my $count = cmd_check_if_exist($1)) {
			#$server->command("msg -channel $target Found $count items. Downloading..");
			create_window('yledl');
			prind("Found $count items. Downloading: " . $1);
			cmd_start_dl($1);
		}
	}
}

# signal is sent from urltitle3.pl
sub sig_yle_url {
	my ($server, $target, $rimpsu, @rest) = @_;
	prind('Yle_url signal received');
	my ($title, $desc) = get_title_desc($rimpsu);
	if ($title) {
		my $responsetext = "$title \002Kuvaus:\002 $desc";
		$responsetext =~ s/(.{300})(.*)/$1 .../;
		$server->command("msg -channel $target $responsetext");
	}
}

# return first found item title and description
sub get_title_desc {
	my ($yleurl, @rest) = @_;
	my $output = `yle-dl --showmetadata ${yleurl} 2>${logfile}`;
	if ($output eq '') {
		debu(__LINE__ . ' No metadata found');
		return;
	}
	my $json = JSON->new->utf8;
	$json->convert_blessed(1);
	$json = decode_json($output);
	foreach my $item (@$json) {
		debu(__LINE__ . ' episode title: ' . $item->{episode_title} . ', episode description: ' . $item->{description});
		return $item->{episode_title}, $item->{description};
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

# check if metadata available and how many items
sub cmd_check_if_exist {
	my ($url, @rest) = @_;
	debu(__LINE__ . ': checking yle url: '. $url);
	
	my $output = `yle-dl -V --showmetadata ${url} 2>${logfile}`;
	if ($output eq '') { return; }

	my $json = JSON->new->utf8;
	$json->convert_blessed(1);
	$json = decode_json($output);
	my $resultcount = scalar @$json;
	return $resultcount;
}

sub cmd_start_dl {
	my ($url, @rest) = @_;
	$runningnumber++;
	debu(__LINE__ . ': fetching: '. $url .' runningnumber: '. $runningnumber);
	create_window('yledl');
	#Irssi::command($execscript. $runningnumber. " $ylescript $url");
	Irssi::command($execscript . "$ylescript $url");
	#Irssi::command("exec -close yle");	# detach
	# -interactive
}

sub exec_new {
	debu('exec_new');
	debu(Dumper(@_));
}

sub exec_remove {
	debu('exec_remove');
	debu(Dumper(@_));
}

sub exec_input {
	my ($info, $line, @rest) = @_;
	$line =~ s/\t/  /;
	prind('exec_input: '. $line);
}

sub debu {
	my ($text, @rest) = @_;
	print($IRSSI{name}.'> '. $text) if $DEBUG;
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
prind('v. '. $IRSSI{changed} . ' loaded.');
