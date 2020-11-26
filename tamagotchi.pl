use warnings;
use strict;
use Irssi;
use Data::Dumper;
use vars qw($VERSION %IRSSI);
use DBI;			# https://metacpan.org/pod/DBI


$VERSION = "20200911";
%IRSSI = (
        authors     => 'LAama1',
        contact     => 'LAama1@Ircnet',
        name        => 'Tamagotchi',
        description => 'Tamagotchi-botti',
        license     => 'BSD',
        url         => '',
        changed     => $VERSION
);

my $db = Irssi::get_irssi_dir(). "/scripts/tamagotchi.db";
my $playerstats;

my $levelpoints = 20;	# how many points between levels
my @ybernicks = ('super','mega','giga','hyper','ultra','moar_','god_','dog','bug','human', 'trump');
my $nicktail = '^_^';

my @foods = ('leipä', 'nakki', 'kastike', 'smoothie', 'maito', 'kaura', 'liha', 'limppu', 'grill', 'makkara', 'lettu', 'pirtelö', 'avocado', 'ruoka', 'chili', 'silli', 'kuha', 'kanansiipi');
my @foodanswer_words = ('*mums mums*', '*nams nams*', '*burp*', '*pier*', '*moar*', '*noms*', '*nams*', 'mums nams', 'moms mums', 'noms nams', 'nam', 'kelpaa');
my $foodcounter = 0;
my @foodnicks = ('munchlax', 'snorlax', 'swinub', 'piloswine', 'mamoswine');

my @loves = ('ihq', 'rakas', 'purr', 'mieletön', '<3', 'pr0n', 'pron', 'porn', 'hyvää', 'chill', 'siisti', 'elin', 'koodi');
my @loveanswer_words = ('*purr*', '<3', '*daa*', '*pier*', '*uuh*', 'uuh <3');
my $lovecounter = 0;
my @lovenicks = ('luvdisc', 'pikatsu', 'pantisy', 'soul');

my @drugs = ('kalja', 'bisse', 'hiisi', 'pieru', 'viina', 'heroiini', 'bongi', 'juoppo', 'kahvi');
my @druganswer_words = ('^_^', '-_-', 'o_O', 'O_o', '._.', '8-)', '(--8', 'i need');
my $drugcounter = 0;
my @drugnicks = ('psyduck', 'golduck', 'spoink', 'grumpig', 'kamatotsy');

my @hates = ('twitter', 'vittu', 'perkele', 'vitun', 'paska', 'jumal', 'kapitalismi', 'raha');
#my @hateanswer_words = ('');
my $hatecounter = 0;
my @hatenicks = ('satan_', 'devil_', 'demon_', 'antichrist_', 'mephistopheles');

my @positiveanswer_words = ('miu', 'mau', 'mou', 'yea', 'yay', 'yoy');
my @negativeanswer_words = ('PSSHH!', 'ZaHH!', 'hyi', '~ngh~', 'ite', 'fak', 'fok', 'ei!', 'EI!', 'fek', 'fik');

unless (-e $db) {
	unless(open FILE, '>'.$db) {
		Irssi::print($IRSSI{name}.": Error, unable to create file: $db");
		die;
	}
	close FILE;
	createDB();
	Irssi::print($IRSSI{name}.": Database file created.");
}
readFromDb();
#read_db();

sub da {
	print Dumper(@_);
	return;
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

# TODO
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
	Irssi::print($IRSSI{name}.' change_nick: '. $newnick);
	$server->command("NICK $newnick");
	return;
}

# return $level (current level number) if levelup
sub if_lvlup {
	my ($counter, @rest) = @_;
	my $modulo = $counter % $levelpoints;
	if ($modulo == 0) {
		# level up
		Irssi::print($IRSSI{name}.': level up! ('.count_level($counter).')');
		return count_level($counter);
	}
	return 0;
}

sub count_level {
	my ($counter, @nicks, @rest) = @_;
	return int($counter / $levelpoints);
}

sub evolve {
	my ($server, $target, $level, $trigger, @nicks, @rest) = @_;
	my $newnick = '';
	#Irssi::print(__LINE__.':tamagotchi.pl newnick count: '. ($level % scalar(@nicks)));
	$newnick = @nicks[($level % scalar @nicks)-1];

	if ($level > scalar @nicks ) {
		Irssi::print(__LINE__.':tamagotchi.pl extralevel float: '. (($level-1) / scalar @nicks ));
		my $extralevel = int(($level-1) / scalar @nicks );
		$newnick = $ybernicks[($extralevel-1)] . $newnick;
	}
	msg_channel($server, $target, "*${trigger}ing* ($level)");
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
		my $foodlvl = count_level($foodcounter, @foodnicks);
		my $lovelvl = count_level($lovecounter, @lovenicks);
		my $druglvl = count_level($drugcounter, @drugnicks);
		my $hatelvl = count_level($hatecounter, @hatenicks);
		msg_channel($serverrec, $target, "ruoka: $foodcounter ($foodlvl), rakkaus: $lovecounter ($lovelvl), päihteet: $drugcounter ($druglvl), viha: $hatecounter ($hatelvl)");
		return;
	}
	
	return if ($msg =~ /\?$/);		# return if line ends with '?'

	if (match_word($msg, @foods)) {
		$foodcounter += 1;
		msg_random($serverrec, $target, @foodanswer_words);
		evolve($serverrec, $target, count_level($foodcounter, @foodnicks), 'FooD', @foodnicks) if (if_lvlup($foodcounter));
		increaseValue('food');
		Irssi::print("tamagotchi from $nick on channel $target, foodcounter: $foodcounter");
	} elsif (match_word($msg, @drugs)) {
		$drugcounter += 1;
		msg_random($serverrec, $target, @druganswer_words);
		evolve($serverrec, $target, count_level($drugcounter, @drugnicks), 'dRuGg', @drugnicks) if (if_lvlup($drugcounter));
		increaseValue('drugs');
		Irssi::print("tamagotchi from $nick on channel $target, drugcounter: $drugcounter");
	} elsif (match_word($msg, @loves)) {
		$lovecounter += 1;
		msg_random($serverrec, $target, @loveanswer_words);
		evolve($serverrec, $target, count_level($lovecounter, @lovenicks), 'LovE', @lovenicks) if(if_lvlup($lovecounter));
		increaseValue('love');
		Irssi::print("tamagotchi from $nick on channel $target, lovecounter: $lovecounter");
	} elsif (match_word($msg, @hates)) {
		$hatecounter += 1;
		msg_random($serverrec, $target, @negativeanswer_words);
		evolve($serverrec, $target, count_level($hatecounter, @hatenicks), 'HaT', @hatenicks) if(if_lvlup($hatecounter));
		increaseValue('hate');
		Irssi::print("tamagotchi from $nick on channel $target, hatecounter: $hatecounter");
	}
}

sub createDB {
	my $dbh = KaaosRadioClass::connectSqlite($db);
	my $sql = "CREATE TABLE if not exists tama
			    (FEATURE text not null,
				AMOUNT int default 0,
				FEATURETIME int default 0);";

	my $rv = KaaosRadioClass::writeToOpenDB($dbh, $sql);
	if($rv ne 0) {
   		Irssi::print ($IRSSI{name}." DBI Error: ". $rv);
	} else {
   		Irssi::print($IRSSI{name}." Table tama created successfully");
		my $time = time;
		$sql = "INSERT INTO tama (FEATURE, FEATURETIME) values ('love', $time)";
		$rv = KaaosRadioClass::writeToOpenDB($dbh, $sql);
		$sql = "INSERT INTO tama (FEATURE, FEATURETIME) values ('hate', $time)";
		$rv = KaaosRadioClass::writeToOpenDB($dbh, $sql);
		$sql = "INSERT INTO tama (FEATURE, FEATURETIME) values ('drugs', $time)";
		$rv = KaaosRadioClass::writeToOpenDB($dbh, $sql);
		$sql = "INSERT INTO tama (FEATURE, FEATURETIME) values ('food', $time)";
		$rv = KaaosRadioClass::writeToOpenDB($dbh, $sql);
	}
	KaaosRadioClass::closeDB($dbh);
}

sub increaseValue {
	my $item = shift;
	my $time = time;
	my $sql = "UPDATE tama SET AMOUNT = AMOUNT+1, FEATURETIME = $time WHERE FEATURE = '$item'";
	my $rc = KaaosRadioClass::writeToDB($db, $sql);
}

sub readFromDb {
	my $sql = 'SELECT * FROM tama';
	my @results = read_db($sql);
	#my @results = KaaosRadioClass::bindSQL($db, $sql);
	print "results next:";
	#da(@results);
	foreach my $result (@results) {
		print $IRSSI{name}.': '.$result->{FEATURE} . ' '.$result->{AMOUNT};
		if ($result->{FEATURE} eq 'love') {
			$lovecounter = $result->{AMOUNT};
		} elsif ($result->{FEATURE} eq 'food') {
			$foodcounter = $result->{AMOUNT};
		} elsif ($result->{FEATURE} eq 'drugs') {
			$drugcounter = $result->{AMOUNT};
		} elsif ($result->{FEATURE} eq 'love') {
			$lovecounter = $result->{AMOUNT};
		}
	}
}

sub read_db {
	my ($sql, @rest) = @_;
	my $dbh = DBI->connect("dbi:SQLite:dbname=$db",'','', {RaiseError => 1, AutoCommit => 1});
	#my $dbh = KaaosRadioClass::connectSqlite($db);							# DB handle
	my $sth = $dbh->prepare($sql) or return $dbh->errstr;	# Statement handle
	$sth->execute() or return $dbh->errstr;
	my @results;
	my $idx = 0;
	while(my $row = $sth->fetchrow_hashref) {
		push @results, $row;
		$idx++;
	}
	$sth->finish();
	$dbh->disconnect();
	return @results;
}

Irssi::settings_add_str('tamagotchi', 'tamagotchi_enabled_channels', '');
Irssi::signal_add_last('message public', 'pubmsg');
#Irssi::signal_add_last('message irc action', 'pubmsg');

Irssi::print("tamagotchi v. $VERSION loaded");
Irssi::print('Enabled channels: '. Irssi::settings_get_str('tamagotchi_enabled_channels'));
