use strict;
use warnings;

use Irssi;
use vars qw($VERSION %IRSSI);
#use Irssi::Irc;
use Data::Dumper;
use XML::LibXML;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;

$VERSION = '0.1';
%IRSSI = (
	authors => 'LAama1',
	contact => 'LAama1@ircnet',
	name => 'hamqsl',
	description => 'Radiokeli -skripti.',
	license => 'BSD',
	url => 'http://www.kaaosradio.fi',
	changed => '2019-05-23',
);

my $DEBUG = 1;

my $parser = XML::LibXML->new();

sub get_help {
	return '!hams tulostaa kanavalle Radiosäästä kertovia tietoja osoitteesta http://hamqsl.com"';
}

sub pub_msg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;
	#return unless ($msg =~ /$serverrec->{nick}/i);
	#return unless ($target ~~ @channels);
	return if ($nick eq $serverrec->{nick});   #self-test
	if ($msg =~ /(!help hams)/sgi) {
		return if KaaosRadioClass::floodCheck();
		my $help = get_help();
		$serverrec->command("MSG $target $help");
	} elsif ($msg =~ /(!hams)/sgi) {
		print("1");
		return if KaaosRadioClass::floodCheck();
		print("2");
		my $xml = fetch_hams_data();
        print("3");
		my $newdata = parse_hams_data($xml);
		print("4");
		$serverrec->command("MSG $target $newdata");
		Irssi::print($IRSSI{"name"}.": request from $nick on channel $target");
	}
}

sub parse_hams_data {
    my ($xmlobj, @rest) = @_;
    my $solarflux = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/solarflux'));
    my $aindex = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/aindex'));
    my $kindex = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/kindex'));
    my $xray = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/xray'));
    my $sunspots = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/sunspots'));
	my $heliumline = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/heliumline'));
    my $protonflux = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/protonflux'));
    my $electronflux = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/electonflux'));
    my $solarwind = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/solarwind'));
    my $magfield = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/magneticfield'));
	my $returnstring = "Solar Flux: $solarflux, A_ind: $aindex, K_ind (kp): $kindex, Xray: $xray" .
		", Sunspot number: $sunspots, Proton Flux: ${protonflux}, Electron Flux: ${electronflux}e/cm²/s, Solar Wind: ${solarwind}km/s, Heliumline: ${heliumline}p/cm²/s, " .
		"Magnetic field: ${magfield}nT";
    return $returnstring;
    #Irssi::print(Dumper($solarflux));
}

sub fetch_hams_data {
    my $url = 'http://www.hamqsl.com/solarxml.php';
    my $textdata = KaaosRadioClass::fetchUrl($url, 0);
    my $dom = $parser->load_xml(string => $textdata);
    #Irssi::print(Dumper($dom));
    return $dom;
    #return KaaosRadioClass::getXML($url);
}


Irssi::signal_add_last('message public', 'pub_msg');

