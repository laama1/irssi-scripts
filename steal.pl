use Irssi;
use warnings;
use strict;
use utf8;
binmode STDOUT, ':utf8';
binmode STDIN, ':utf8';
use vars qw($VERSION %IRSSI);

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

my $helptext = 'Usage: !steal';
my $total_file = Irssi::get_irssi_dir() . '/scripts/irssi-scripts/total_stolen.txt';

sub sayit {
    my ($server, $target, $saywhat) = @_;
    $server->command("MSG $target $saywhat");
    return;
}

sub get_total {
    if (-e $total_file) {
        open my $fh, '<', $total_file or return 0;
        my $val = <$fh> // 0;
        close $fh;
        chomp $val;
        return $val =~ /^(\d+)$/ ? $1 : 0;
    }
    return 0;
}

sub save_total {
    my ($total) = @_;
    open my $fh, '>', $total_file or return;
    print $fh $total;
    close $fh;
}

sub event_pubmsg {
    my ($server, $msg, $nick, $address, $target) = @_;
    if ($msg =~ /^!steal\b/) {
        my $amount = int(rand(100)) + 1; # Steal 1-100
        my $total = get_total();
        $total += $amount;
        save_total($total);
        sayit($server, $target, "$nick stole $amount rubles from Putin! Total stolen: $total rubles");
    }
}

Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::print("$IRSSI{name} loaded. Use !steal to steal money.");
