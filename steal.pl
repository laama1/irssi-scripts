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
    name        => 'Steal money simple',
    description => 'React to !steal and add stolen money to total pile, saving to file',
    license     => 'Public Domain',
    url         => '#salamolo',
    changed     => $VERSION
);

my $helptext = 'Usage: !steal, set steal target with !steal set <unit> <target>';
# default values:
my $steal_target = 'Putin';
my $monetary_unit = 'rubles';
my $database_file = Irssi::get_irssi_dir() . '/scripts/irssi-scripts/steal.db';


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
        my $dbh = KaaosRadioClass::connectSqlite($database_file);
        
        if (line_exists($dbh, $monetary_unit, $steal_target)) {
            increase_value($dbh, $monetary_unit, $steal_target, $amount);
        } else {
            create_new_line($dbh, $monetary_unit, $steal_target, $amount);
        }

        my $total = get_total_amount($dbh, $monetary_unit, $steal_target);
        sayit($server, $target, "$nick stole $amount $monetary_unit from $steal_target! Total stolen: $total $monetary_unit");
    }
}

sub create_sqlite_db {
    if ($database_file && !-e $database_file) {
        open my $fh, '>', $database_file or die "Could not create database file: $!";
        close $fh;
        my $dbh = DBI->connect("dbi:SQLite:dbname=$database_file","","");
        $dbh->do("CREATE TABLE IF NOT EXISTS steals (id INTEGER PRIMARY KEY, unit TEXT, target TEXT, total_amount INTEGER, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)");
    }
    return;
}

sub line_exists {
    my ($dbh, $unit, $target) = @_;
    my $sql = "SELECT total_amount FROM steals WHERE unit = ? AND target = ?";
    my @data = KaaosRadioClass::readLineFromOpenDB($dbh, $sql, ($unit, $target));
    print Dumper(\@data);
    return scalar(@data) > 0;
    #return defined $row ? $row->{total_amount} : undef;
}

sub increase_value {
    my ($dbh, $unit, $target, $amount) = @_;
    my $sql = "UPDATE steals SET total_amount = total_amount + $amount WHERE unit = '$unit' AND target = '$target'";
    my $rv = KaaosRadioClass::writeToOpenDB($dbh, $sql);
    if($rv ne 0) {
        print "DBI Error: $rv";
    } else {
        print "Updated total for $target by adding $amount $unit";
    }
}

sub create_new_line {
    my ($dbh, $unit, $target, $total) = @_;
    my $sql = "INSERT INTO steals (unit, target, total_amount) VALUES ('$unit', '$target', $total)";
    my $rv = KaaosRadioClass::writeToOpenDB($dbh, $sql);
    if($rv ne 0) {
        print "DBI Error: $rv";
    } else {
        print "Created new line for $target with $total $unit";
    }
}

sub get_total_amount {
    my ($dbh, $unit, $target) = @_;

    my $sql = "SELECT total_amount FROM steals WHERE unit = '$unit' AND target = '$target'";
    my @data = KaaosRadioClass::readLineFromOpenDB($dbh, $sql);
    print Dumper(\@data);
    my $row = $data[0];
    return defined $row ? $row : 0;
}

create_sqlite_db();
Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::print("$IRSSI{name} loaded. Use !steal to steal money.");
