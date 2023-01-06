# skripti lataa yleareena-linkin takaa löytyvän videon
# LAama1 4.4.2020
use strict;
use warnings;
use Irssi;
#use KaaosRadioClass;
use JSON;
use Data::Dumper;
use vars qw($VERSION %IRSSI);
$VERSION = '20230106';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'ircnet: LAama1',
	name        => 'fetch_areena.pl',
	description => 'Download video and audio from YLE Areena or yle.fi.',
	license     => 'Public Domain',
	url         => '',
	changed     => $VERSION,
);


my $runningnumber = 0;
#if you have Finnish proxy, use it here.
#my $proxy = "--proxy 10.7.0.1:3128";
my $download_dir = "/mnt/music/areena";
#my $ylescript = 'yle-dl -qq --vfat --no-overwrite --destdir '.$download_dir.' --maxbitrate best';
my $ylescript = 'yle-dl -qq --vfat --destdir '.$download_dir.' --maxbitrate best';
my $execscript = 'exec -msg yle-dl -name ';

print($IRSSI{name}.'> download dir: '.$download_dir);

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	if ($msg =~ /(https?:\/\/areena\.yle\.fi\/\S+)/i || 
		$msg =~ /(https?:\/\/yle\.fi\S+)/i || 
		$msg =~ /(https?:.*\.yle\.fi\S+)/i) {
		if (my $count = cmd_check_if_exist($1)) {
			#$server->command("msg -channel $target Found $count items. Downloading..");
			print($IRSSI{name}."> Found $count items. Downloading...");
			cmd_start_dl($1);
		}
	}
}

# signal is sent from urltitle.pl
sub sig_yle_url {
	my ($server, $target, $rimpsu, @rest) = @_;
	print($IRSSI{name}."> Yle_url signal received");
	my ($title, $desc) = get_title_desc($rimpsu);
	if ($title) {
		my $responsetext = "$title \002Kuvaus:\002 $desc";
		$responsetext =~ s/(.{300})(.*)/$1 .../;
		$server->command("msg -channel $target $responsetext");
	}
}

# return first episode title
sub get_title_desc {
	my ($yleurl, @rest) = @_;
	my $output = `yle-dl --showmetadata ${yleurl} 2>/dev/null`;
	if ($output eq "") { return; }
	my $json = JSON->new->utf8;
	$json->convert_blessed(1);
	$json = decode_json($output);
	foreach my $item (@$json) {
		debu("episode title: ".$item->{'episode_title'});
		return $item->{episode_title}, $item->{description};
	}
}

sub cmd_check_if_exist {
	my ($url, @rest) = @_;
	debu('checking: '. $url);
	
	my $output = `yle-dl -V --showmetadata ${url} 2>/dev/null`;
	if ($output eq "") { return; }

	my $json = JSON->new->utf8;
	$json->convert_blessed(1);
	$json = decode_json($output);
	my $resultcount = scalar @$json;
	return $resultcount;
}

sub cmd_start_dl {
	my ($url, @rest) = @_;
	debu('fetching: '. $url);
	$runningnumber++;
	Irssi::command($execscript .'yle-dl'. $runningnumber. " $ylescript $url");
	#Irssi::command("exec -close yle");	# detach
	# -interactive
}

sub exec_new {
	debu('exec_new');
	#print(Dumper(@_));
}

sub exec_remove {
	debu('exec_remove');
	#print(Dumper(@_));
}

sub exec_input {
	debu('exec_input');
	#print(Dumper(@_));
}

sub debu {
	my ($text, @rest) = @_;
	print($IRSSI{name}.'> '. $text);
}

Irssi::signal_add("exec new", 'exec_new');
Irssi::signal_add("exec remove", 'exec_remove');
Irssi::signal_add("exec input", 'exec_input');

Irssi::signal_add('message public', 'sig_msg_pub');
Irssi::signal_add('yle_url', 'sig_yle_url');
Irssi::print($IRSSI{name}.' v. '. $IRSSI{changed});
