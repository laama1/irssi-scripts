use warnings;
use strict;
use Irssi;
#use KaaosRadioClass;				# LAama1 7.3.2019
use Data::Dumper;
use vars qw($VERSION %IRSSI);

$VERSION = "20191003";
%IRSSI = (
        authors     => 'LAama1',
        contact     => 'LAama1@Ircnet',
        name        => 'Tamagotchi',
        description => 'Tamagotchi-botti',
        license     => 'BSD',
        url         => '',
        changed     => $VERSION
);

my $levelpoints = 25;	# how many points between levels
my @ybernicks = ('super', 'mega', 'giga', 'hyper', 'ultra', 'moar', 'god');
my $nicktail = '^_^';

my @foods = ('leipä', 'nakki', 'kastike', 'smoothie', 'maito', 'kaura', 'liha', 'limppu', 'grill', 'makkara', 'lettu', 'pirtelö', 'avocado', 'ruoka', 'chili', 'silli', 'kuha', 'kanansiipi');
my @foodanswer_words = ('*mums mums*', '*nams nams*', '*burp*', '*pier*', '*moar*', '*noms*', '*nams*', 'mums nams', 'moms mums', 'noms nams');
my $foodcounter = 0;
my $foodlevel = 0;
my @foodnicks = ('munchlax', 'snorlax', 'swinub', 'piloswine', 'mamoswine');

my @loves = ('ihq', 'rakas', '*purr*', 'mieletön', '<3', 'pr0n', 'pron', 'hyvää', 'chill');
my @loveanswer_words = ('*purr*', '<3', '*daa*', '*pier*', '*uuh*', 'uuh <3');
my $lovecounter = 0;
my $lovelevel = 0;
my @lovenicks = ('luvdisc', 'pikatsu', 'pantisy', 'soul');

my @drugs = ('kalja', 'bisse', 'hiisi', 'pieru', 'viina', 'heroiini', 'bongi', 'juoppo', 'kahvi');
my @druganswer_words = ('^_^', '-_-', 'o_O', 'O_o', '._.', '8-)');
my $drugcounter = 0;
my $druglevel = 0;
my @drugnicks = ('psyduck', 'golduck', 'spoink', 'grumpig', 'kamatotsy');

my @hates = ('twitter', 'vittu', 'perkele', 'vitun', 'paska', 'jumal');
#my @hateanswer_words = ('');
my $hatecounter = 0;
my $hatelevel = 0;
my @hatenicks = ('satan_', 'devil_', 'demon_', 'antichrist_', 'mephistopheles');

my @positiveanswer_words = ('miu', 'mau', 'mou', 'yea', 'yay', 'yoy');
my @negativeanswer_words = ('PSSHH!', 'ZaHH!', 'hyi', '~ngh~', 'ite');

sub da {
	print Dumper(@_);
}

sub match_word {
	my ($sentence, @compare, @rest) = @_;
	if (grep { index($sentence, $_) > 0 } @compare ) {
		return 1;
	}
	return 0;
}

sub msg_channel {
	my ($serverrec, $target, $line, @rest) = @_;
	$serverrec->command("MSG $target $line");
	return;
}

sub msg_random {
	my ($server, $target, @words) = @_;
	my $rand = int(rand(scalar @words));
	msg_channel($server, $target, $words[$rand]);
	return;
}

sub if_nick_in_use {
	my ($server, $nick, @rest) = @_;
	da('whois1:', $server->send_raw("whois $nick"));
	da('who2:', $server->send_raw("who :$nick"));
	return;
}

sub change_nick {
	my ($server, $newnick, @rest) = @_;
	#if_nick_in_use($server, $newnick);
	$newnick .= $nicktail;
	Irssi::print('tamagotchi.pl change_nick: '. $newnick);
	$server->command("NICK $newnick");
	return;
}

# return $level (current level number) if levelup
sub count_level {
	my ($counter, @nicks, @rest) = @_;
	my $modulo = $counter % $levelpoints;
	my $level = int($counter / $levelpoints);
	#Irssi::print(__LINE__.':tamagotchi.pl count_level: modulo: '. $modulo. ', level: '. $level.' (counter: '. $counter. ', levelpoints: '. $levelpoints.')');
	if ($modulo == 0) {
		# level up
		Irssi::print(__LINE__.':tamagotchi.pl: level up! ('.$level.')');
		return $level;
	}
	return 0;
}

sub evolve {
	my ($server, $target, $level, @nicks, @rest) = @_;
	my $newnick = '';
	#Irssi::print(__LINE__.':tamagotchi.pl newnick count: '. ($level % scalar(@nicks)));
	$newnick = @nicks[($level % scalar(@nicks))-1];

	if ($level > scalar(@nicks)) {
		Irssi::print(__LINE__.':tamagotchi.pl extralevel float: '. (($level-1) / scalar(@nicks)));
		#my $extralevel = int($level / scalar(@nicks));
		my $extralevel = int(($level-1) / scalar(@nicks));
		$newnick = $ybernicks[($extralevel-1)] . $newnick;
	}
	msg_channel($server, $target, '*EvolVing*');
	change_nick($server, $newnick);
	return;
}

sub pubmsg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;
	return if ($nick eq $serverrec->{nick});	# self-test
	#return if $nick eq 'kaaosradio';			# ignore this nick
	my @targets = split(/ /, Irssi::settings_get_str('tamagotchi_enabled_channels'));
    return unless $target ~~ @targets;

	if ($msg =~ /^!tama/i) {
		msg_channel($serverrec, $target, "ruoka: $foodcounter, rakkaus: $lovecounter, päihteet: $drugcounter, viha: $hatecounter");
		return;
	}
	
	return if ($msg =~ /\?$/);		# return if line ends with '?'

	if (match_word($msg, @foods)) {
		$foodcounter += 1;
		msg_random($serverrec, $target, @foodanswer_words);
		my $curlevel = count_level($foodcounter, @foodnicks);
		evolve($serverrec, $target, $curlevel, @foodnicks) if($curlevel > 0);
		Irssi::print("tamagotchi from $nick on channel $target, foodcounter: $foodcounter\n");
	} elsif (match_word($msg, @drugs)) {
		$drugcounter += 1;
		msg_random($serverrec, $target, @druganswer_words);
		my $curlevel = count_level($drugcounter, @drugnicks);
		evolve($serverrec, $target, $curlevel, @drugnicks) if ($curlevel > 0);
		Irssi::print("tamagotchi from $nick on channel $target, drugcounter: $drugcounter\n");
	} elsif (match_word($msg, @loves)) {
		$lovecounter += 1;
		msg_random($serverrec, $target, @loveanswer_words);
		my $curlevel = count_level($lovecounter, @lovenicks);
		evolve($serverrec, $target, $curlevel, @lovenicks) if($curlevel > 0);
		Irssi::print("tamagotchi from $nick on channel $target, lovecounter: $lovecounter\n");
	} elsif (match_word($msg, @hates)) {
		$hatecounter += 1;
		msg_random($serverrec, $target, @negativeanswer_words);
		my $curlevel = count_level($hatecounter, @hatenicks);
		evolve($serverrec, $target, $curlevel, @hatenicks) if($curlevel > 0);
		Irssi::print("tamagotchi from $nick on channel $target, hatecounter: $hatecounter\n");
	}
}

Irssi::settings_add_str('tamagotchi', 'tamagotchi_enabled_channels', '');
Irssi::signal_add_last('message public', 'pubmsg');
#Irssi::signal_add_last('message irc action', 'pubmsg');

Irssi::print("tamagotchi v. $VERSION loaded");
Irssi::print("Enabled channels: ". Irssi::settings_get_str('tamagotchi_enabled_channels'));
