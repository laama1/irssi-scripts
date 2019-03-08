use warnings;
use strict;
use Irssi;
use KaaosRadioClass;				# LAama1 7.3.2019
use Data::Dumper;
use vars qw($VERSION %IRSSI);

$VERSION = '0.2';
%IRSSI = (
        authors     => 'LAama1',
        contact     => 'LAama1@Ircnet',
        name        => 'Tamagotchi',
        description => 'Tamagotchi-botti',
        license     => 'BSD',
        url         => '',
        changed     => $VERSION
);

my @foods = ('leipä', 'nakki', 'kastike', 'smoothie', 'maito', 'kaura', 'liha', 'limppu', 'grill', 'makkara', 'lettu', 'pirtelö', 'avocado', 'ruoka');
my @foodanswer_words = ('*mums mums*', '*nams nams*', '*burp*', '*pier*', '*moar*', '*noms*');
my $foodcounter = 0;

my @loves = ('ihq', 'rakas', '*purr*', 'mieletön', '<3', 'pr0n', 'pron', 'hyvää');
my @loveanswer_words = ('*purr*', '<3', '*daa*', '*pier*');
my $lovecounter = 0;

my @drugs = ('kalja', 'bisse', 'hiisi', 'pieru', 'viina', 'heroiini', 'bongi');
my @druganswer_words = ('^_^', '-_-', 'o_O', 'O_o', '._.', '8-)');
my $drugcounter = 0;

my @hates = ('twitter', 'vittu', 'perkele', 'vitun', 'paska');
#my @hateanswer_words = ('');
my $hatecounter = 0;

my @positiveanswer_words = ('miu', 'mau', 'mou', 'yea', 'yay', 'yoy');
my @negativeanswer_words = ('PSSHH!', 'ZaHH!');

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
}

sub pubmsg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;
	return if ($nick eq $serverrec->{nick});	# self-test
	#return if $nick eq 'kaaosradio';			# ignore this nick
	my @targets = split(/ /, Irssi::settings_get_str('tamagotchi_enabled_channels'));
    return unless $target ~~ @targets;
	
	if ( $msg =~ /^!tama/i) {
		msg_channel($serverrec, $target, "ruoka: $foodcounter, rakkaus: $lovecounter, päihteet: $drugcounter, viha: $hatecounter");
		return;
	}

	if (match_word($msg, @foods)) {
		$foodcounter += 1;
		my $rand = int(rand(scalar @foodanswer_words));
		my $answer = $foodanswer_words[$rand];
		msg_channel($serverrec, $target, $answer);
		Irssi::print("tamagotchi from $nick on channel $target, foodcounter: $foodcounter");
		return;
	}

	if (match_word($msg, @drugs)) {
		$drugcounter += 1;
		my $frand = rand(scalar @druganswer_words);
		my $rand = int($frand);
		da('frand', $frand, 'rand', $rand);
		my $answer = $druganswer_words[$rand];
		msg_channel($serverrec, $target, $answer);
		Irssi::print("tamagotchi from $nick on channel $target, drugcounter: $drugcounter");
		return;
	}

	if (match_word($msg, @loves)) {
		$lovecounter += 1;
		my $frand = rand(scalar @loveanswer_words);
		my $rand = int($frand);
		da('frand', $frand, 'rand', $rand);
		my $answer = $loveanswer_words[$rand];
		msg_channel($serverrec, $target, $answer);
		Irssi::print("tamagotchi from $nick on channel $target, lovecounter: $lovecounter");
		return;
	}


	if (match_word($msg, @hates)) {
		$hatecounter += 1;
		my $frand = rand(scalar @negativeanswer_words);
		my $rand = int($frand);
		da('frand', $frand, 'rand', $rand);
		my $answer = $negativeanswer_words[$rand];
		msg_channel($serverrec, $target, $answer);
		Irssi::print("tamagotchi from $nick on channel $target, hatecounter: $hatecounter");
		return;
	}
}

Irssi::settings_add_str('tamagotchi', 'tamagotchi_enabled_channels', '');
Irssi::signal_add_last('message public', 'pubmsg');
#Irssi::signal_add_last('message irc action', 'pubmsg');

Irssi::print("tamagotchi v. $VERSION loaded");
Irssi::print("Enabled channels: ". Irssi::settings_get_str('tamagotchi_enabled_channels'));
