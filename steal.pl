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
    name        => 'Steal money',
    description => 'React to !steal and add stolen money to total pile, saving to file',
    license     => 'Public Domain',
    url         => '#salamolo',
    changed     => $VERSION
);

my $helptext = 'Usage: !steal, set steal target with !steal set <unit> <target>';
# default values:
my $steal_target = 'Putin';
my $monetary_unit = 'rubles';
#my $database_file = Irssi::get_irssi_dir() . '/scripts/irssi-scripts/steal.db';
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
        return; # Not a steal command, ignore
    }
    if ($msg =~ /^!steal\b/) {
        my $amount = int(rand(120)) + 1; # Steal 1-120
        $dbh = KaaosRadioClass::connectSqlite($database_file);

        #print __LINE__ . ": DBH: " . Dumper($dbh) if $DEBUG;
        my $total = 0;
        
        if ($total = line_exists()) {
            print __LINE__ . ": Line exists for $steal_target with unit $monetary_unit, increasing value by $amount" if $DEBUG;
            #increase_value($dbh, $amount, $total);
            increase_value($amount, $total);
        } else {
            print __LINE__ . ": Line does not exist for $steal_target with unit $monetary_unit, creating new line with $amount" if $DEBUG;
            #$total = create_new_line($dbh, $amount);
            $total = create_new_line($amount);
        }

        #my $total = get_total_amount($dbh);
        sayit($server, $target, "$nick stole $amount $monetary_unit from $steal_target! Total stolen: $total $monetary_unit");
    }
}

sub create_sqlite_db {
    if ($database_file && !-e $database_file) {
        open my $fh, '>', $database_file or die "Could not create database file: $!";
        close $fh;
    }
    my $dbh = DBI->connect("dbi:SQLite:dbname=$database_file","","");
    $dbh->do("CREATE TABLE IF NOT EXISTS steals (id INTEGER PRIMARY KEY, unit TEXT NOT NULL, target TEXT NOT NULL, total_amount INTEGER, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)");
    $dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS idx_steals_target_unit ON steals(target, unit)");
    $dbh->disconnect();
    Irssi::print("SQLite database initialized at $database_file");
    return;
}

sub line_exists {
    #print __LINE__ . " if line_exists: unit: >$monetary_unit<, target: >$steal_target<" if $DEBUG;
    my $sql = "SELECT total_amount FROM steals WHERE unit = ? AND target = ? LIMIT 1";
    my @data = readLineFromOpenDB($dbh, $sql, $monetary_unit, $steal_target);
    print __LINE__ . ': ' . Dumper(\@data) if $DEBUG;
    return scalar(@data) > 0 ? $data[0] : undef;
}

sub get_total_amount {
    my $sql = "SELECT total_amount FROM steals WHERE unit = ? AND target = ? LIMIT 1";
    my @data = readLineFromDataBase($database_file, $sql, $monetary_unit, $steal_target);
    print __LINE__ . ': ' . Dumper(\@data) if $DEBUG;
    my $row = $data[0];
    return defined $row ? $row : 0;
}

sub increase_value {
    my ($amount, $total) = @_;
    my $newvalue = int($amount + $total);
    #my $sql = "UPDATE steals SET total_amount = total_amount + ? WHERE unit = ? AND target = ?";
    #my $rv = writeToOpenDB($dbh, $sql, int($amount), $monetary_unit, $steal_target);
    my $sql = "UPDATE steals SET total_amount = $newvalue WHERE unit = '$monetary_unit' AND target = '$steal_target'";
    print (__LINE__ . ": increase_value: SQL: $sql") if $DEBUG;
    my $rv = writeToDB($database_file, $sql);
    print __LINE__ . ": increase_value: newvalue: $newvalue, amount: $amount, unit: >$monetary_unit<, target: >$steal_target<, RV: $rv" if $DEBUG;
    if($rv ne 0) {
        print "DBI Error: $rv";
        return 'error';
    } else {
        print "Updated total for $steal_target by adding $amount $monetary_unit";
    }
    return $newvalue;
}

sub create_new_line {
    my ($total) = @_;
    my $dbh = connectSqlite($database_file);
    #my $sql = "INSERT INTO steals (unit, target, total_amount) VALUES (?, ?, ?)";
    #my $rv = writeToOpenDB($dbh, $sql, $monetary_unit, $steal_target, int($total));
    my $sql = "INSERT INTO steals (unit, target, total_amount) VALUES ('$monetary_unit', '$steal_target', $total)";
    my $rv = writeToDB($database_file, $sql);
    print __LINE__ . ": create_new_line: total: $total, unit: >$monetary_unit<, target: >$steal_target<, RV: $rv" if $DEBUG;
    if($rv ne 0) {
        print "DBI Error: $rv";
        return 'error';
    } else {
        print "Created new line for $steal_target with $total $monetary_unit";
    }
    return $total;
}


create_sqlite_db();
Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::print("$IRSSI{name} loaded. Use !steal to steal money.");
