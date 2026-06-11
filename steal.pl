use Irssi;
use warnings;
use strict;
use utf8;
binmode STDOUT, ':utf8';
binmode STDIN, ':utf8';
use DBI;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2026-03-01
use KaaosRadioClass;
use vars qw($VERSION %IRSSI);
use Data::Dumper;

$VERSION = '2025-09-13';
%IRSSI = (
    authors     => 'LAama1',
    contact     => 'ircnet: LAama1',
    name        => 'Steal',
    description => 'React to !steal and add stolen money to total pile, saving to file',
    license     => 'Public Domain',
    url         => '#salamolo',
    changed     => $VERSION
);

my $helptext = 'Usage: !steal, !steal top, !steal set <unit> <target>';
# default values:
my $steal_target = 'Putin';
my $monetary_unit = 'rubles';

my $database_file = $KaaosRadioClass::scriptDir . '/steal.db';
my $DEBUG = 1;
my $dbh;

sub sayit {
    my ($server, $target, $saywhat) = @_;
    $server->command("MSG $target $saywhat");
    return;
}

sub event_pubmsg {
    my ($server, $msg, $nick, $address, $target) = @_;
    if ($msg =~ /^!steal set\s+(\w+) (.*)$/) {
        ($monetary_unit, $steal_target) = ($1, $2);
        sayit($server, $target, "Steal target set to $steal_target with unit $monetary_unit");
        return;
    } elsif ($msg =~ /^!steal help\b/) {
        sayit($server, $target, $helptext);
        return;
    } elsif ($msg !~ /^!steal\b/) {
        # Not a steal command, ignore
        return;
    }
    if ($msg =~ /^!steal$/) {
        my $amount = int(rand(120)) + 1; # Steal 1-120
        $dbh = KaaosRadioClass::connectSqlite($database_file);

        #print __LINE__ . ": DBH: " . Dumper($dbh) if $DEBUG;
        my $total = 0;
        
        if ($total = line_exists()) {
            #print __LINE__ . ": Line exists for $steal_target with unit $monetary_unit, increasing value by $amount" if $DEBUG;
            #increase_value($dbh, $amount, $total);
            $total = increase_value($amount, $total);
        } else {
            #print __LINE__ . ": Line does not exist for $steal_target with unit $monetary_unit, creating new line with $amount" if $DEBUG;
            #$total = create_new_line($dbh, $amount);
            $total = create_new_line($amount);
        }

        #my $total = get_total_amount($dbh);
        sayit($server, $target, "$nick stole $amount $monetary_unit from $steal_target! Total stolen: $total $monetary_unit");
    } elsif ($msg =~ /^!steal top$/) {
        my @top = get_top_ten();
        my $response = "\002Top 10 steal victims:\002 ";
        foreach my $entry (@top) {
            $response .= "$entry->[1] ($entry->[2] $entry->[3]), ";
        }
        sayit($server, $target, $response);
    }
}

sub create_sqlite_db {
    if ($database_file && !-e $database_file) {
        open my $fh, '>', $database_file or die "Could not create database file: $!";
        close $fh;
    }
    my $dbh = DBI->connect("dbi:SQLite:dbname=$database_file","","");
    $dbh->do("CREATE TABLE IF NOT EXISTS steals (id INTEGER PRIMARY KEY, unit TEXT NOT NULL, target TEXT NOT NULL, total_amount INTEGER, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, latest_steal DATETIME )");
    $dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS idx_steals_target_unit ON steals(target, unit)");
    $dbh->disconnect();
    prind("SQLite database initialized at $database_file");
    return;
}

sub line_exists {
    my $sql = "SELECT total_amount FROM steals WHERE unit = ? AND target = ? LIMIT 1";
    my @data = readLineFromOpenDB($dbh, $sql, $monetary_unit, $steal_target);
    return scalar(@data) > 0 ? $data[0] : undef;
}

sub get_total_amount {
    my $sql = "SELECT total_amount FROM steals WHERE unit = ? AND target = ? LIMIT 1";
    my @data = readLineFromDataBase($database_file, $sql, $monetary_unit, $steal_target);
    my $row = $data[0];
    return defined $row ? $row : 0;
}

sub increase_value {
    # increase value and return new total
    my ($amount, $total) = @_;
    my $newvalue = int($amount + $total);
    #my $sql = "UPDATE steals SET total_amount = total_amount + ? WHERE unit = ? AND target = ?";
    #my $rv = writeToOpenDB($dbh, $sql, int($amount), $monetary_unit, $steal_target);
    my $sql = "UPDATE steals SET total_amount = $newvalue, latest_steal = CURRENT_TIMESTAMP WHERE unit = '$monetary_unit' AND target = '$steal_target'";
    my $rv = writeToDB($database_file, $sql);
    if($rv ne 0) {
        prindw("DBI Error: $rv");
        return 'error';
    } else {
        prind("Updated total for $steal_target by adding $amount $monetary_unit");
    }
    return $newvalue;
}

sub create_new_line {
    # create new steal target to the database
    my ($total) = @_;
    my $dbh = connectSqlite($database_file);
    #my $sql = "INSERT INTO steals (unit, target, total_amount) VALUES (?, ?, ?)";
    #my $rv = writeToOpenDB($dbh, $sql, $monetary_unit, $steal_target, int($total));
    my $sql = "INSERT INTO steals (unit, target, total_amount) VALUES ('$monetary_unit', '$steal_target', $total)";
    my $rv = writeToDB($database_file, $sql);
    if($rv ne 0) {
        prindw("DBI Error: $rv");
        return 'error';
    } else {
        print "Created new line for $steal_target with $total $monetary_unit";
    }
    return $total;
}

sub get_top_ten {
    my $sql = "SELECT id, target, total_amount, unit FROM steals order by total_amount desc limit 10";
    my @data = bindSQL($database_file, $sql);
    return @data;
}

sub load_latest_steal {
    my $sql = "SELECT unit, target from steals order by latest_steal desc limit 1";
    my @data = readLineFromDataBase($database_file, $sql);
    if (scalar(@data) > 0) {
        ($monetary_unit, $steal_target) = ($data[0], $data[1]);
        prind("Loaded latest steal target: $steal_target with unit $monetary_unit");
    }
}

sub prind {
	my ($text, @rest) = @_;
	print "\00313" . $IRSSI{name} . ">\003 " . $text;
}

sub prindw {
	my ($text, @rest) = @_;
	print "\0034" . $IRSSI{name} . ">\003 " . $text;
}

create_sqlite_db();
load_latest_steal();
Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::print("$IRSSI{name} loaded. Use !steal to steal money.");
