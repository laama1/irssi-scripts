use strict;
use warnings;
use Irssi;
use vars qw($VERSION %IRSSI);
use Data::Dumper;
use JSON;
use POSIX;
use DateTime;
#require "$ENV{HOME}/.irssi/scripts/irssi-scripts/KaaosRadioClass.pm";
use KaaosRadioClass;

$VERSION = '0.1';
%IRSSI = (
	authors => 'LAama1',
	contact => 'LAama1@ircnet',
	name => 'fingrid',
	description => 'Suomen sähkönkulutuksen tiedot',
	license => 'BSD',
	url => 'http://www.kaaosradio.fi',
	changed => '2023-08-18',
);

=pod
https://data.fingrid.fi/open-data-api/
https://data.fingrid.fi/en/pages/apis

variableID's:
74  Sähköntuotanto suomessa, tuntikohtainen
75  Tuulivoimatuotanto, tuntienergiatieto
90  Ruotsi-Ahvenanmaa, reaaliaika
89  Ruotsi-Suomi, reaaliaika
124 Sähkön kulutus, tuntikohtainen
177 Taajuus, reaaliaika
180 Viro-Suomi, reaaliaika
181 Tuulivoiman tuotanto, reaaliaikainen (MWh/h)
182 Lämpötila Jkl, reaaliaika
186 Sähköntuotanto, yli-/alijäämä, kumulatiivinenn
187 Norja-Suomi, reaaliaika
188 Ydinvoimatuotanto, reaaliaika
191 Vesivoimatuotanto, reaaliaika
192 Sähköntuotanto Suomessa, reaaliaika
193 Sähkönkulutus Suomessa, reaaliaika
194 Sähkön nettotuonti/vienti, reaaliaika
195 Venäjä-Suomi, reaaliaika
198 Sähköntuotanto, yli-/alijäämä
209 Sähköjärjestelmän käyttötilanne, liikennevalo, reaaliaika
248 Aurinkovoiman tuotantoennuste, tuntikohtainen
267 Aurinkovoimaennusteessa käytetty kokonaiskapasiteetti
306 
336 Sähköpula, tilannetieto

icons:
☢️ radioactive
🔌 töpseli
🌊 water wave
💨 wind blow
=cut


my $DEBUG = 1;
#my $variable_id = 0;
#my $apiurl = 'https://api.fingrid.fi/v1/variable/'.$variable_id.'/event/json';
my $sahkourl = 'https://api.porssisahko.net/v1/price.json?date=';   # 2023-08-18&hour=14';

my $apikey;
our $localdir = $ENV{HOME}."/.irssi/scripts/irssi-scripts/";
open( AK, '<', $localdir . 'fingrid_api.key') or die "$!";
while (<AK>) { $apikey = $_; }
chomp($apikey);
close(AK);

sub get_fingrid_url {
    my ($variable_id, @rest) = @_;
    return 'https://api.fingrid.fi/v1/variable/event/json/177,181,188,191,192,193,209,248,267,336';
}

sub get_sahko_url {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday, $yday, $isdst) = gmtime(time);
    #my $datestring = strftime "%Y-%m-%d", gmtime time;
    my $datestring = DateTime->now->ymd;
    #my $timestring = strftime "%H", gmtime time;
    my $timestring = DateTime->now->hour;
    # FIXME: hardcoded timezone +3
    my $newurl = $sahkourl . $datestring . '&hour=' .($timestring+3);
    Irssi::print($IRSSI{name} . '> newurl: ' . $newurl);
    return $newurl;
}

sub get_aurinkovoima_arvio {
    my $dt = DateTime->now;
    my $dura_begin = DateTime::Duration->new(hours => -1);
    my $timestring_begin = ($dt + $dura_begin)->iso8601 . 'Z';
    my $timestring_end = DateTime->now->iso8601 . 'Z';
    my $aurinkourl = 'https://api.fingrid.fi/v1/variable/248/events/json?start_time=' . $timestring_begin . '&end_time=' .$timestring_end;
    my $jsondata = fetch_fingrid_data($aurinkourl);
    foreach my $data (@$jsondata) {
        return $data->{value};
    }
}

sub get_help {
	return '!sähkö tulostaa kanavalle tietoja Suomen sähköverkon tilasta. Data haetaan Fingridin rajapinnasta. Sähkön hinta tulee muualta!"';
}

sub pub_msg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;

	return if ($nick eq $serverrec->{nick});   #self-test
	if ($msg =~ /(!help sähkö)/sgi) {
		return if KaaosRadioClass::floodCheck();
		my $help = get_help();
		$serverrec->command("MSG $target $help");
	} elsif ($msg =~ /(!sähkö)/sgi) {
		return if KaaosRadioClass::floodCheck();
		my $json = fetch_fingrid_data(get_fingrid_url());
        my $av_arvio = get_aurinkovoima_arvio();
        my $price = '';
        if ($price = fetch_price_data()) {
             $price = 'Pörssisähkön hinta veroineen: '.$price.'c/kWh.'
        } else {
            $price = 'Sähkön hintatietoa ei saatu.'
        };
        
		my $newdata = parse_sahko_data($json, $av_arvio);
		
		$serverrec->command("MSG $target $price $newdata");
		Irssi::print($IRSSI{name}.": request from $nick on channel $target");
	}
}

sub parse_sahko_data {
    my ($jsondata, $av_arvio, @rest) = @_;
    #print Dumper $jsondata;
    my $tuotanto = '';      # 192
    my $kulutus = '';       # 193
    my $tuulivoima = '';    # 181
    my $taajuus = '';       # 177
    my $ydinvoima = '';     # 188
    my $vesivoima = '';     # 191
    my $liikennevalo = '';  # 209
    my $aurinkoennuste = '';    # 248 and 267
    my $aurinkokapa = '';   # 267
    my $sahkopula = '';     # 336
    foreach my $element (@$jsondata) {
        if ($element->{variable_id} == 192) {
            $tuotanto = $element->{value} . 'MW';
        } elsif ($element->{variable_id} == 193) {
            $kulutus = $element->{value} . 'MW';
        } elsif ($element->{variable_id} == 181) {
            $tuulivoima = '💨 ' . $element->{value} . 'MW';
        } elsif ($element->{variable_id} == 177) {
            $taajuus = $element->{value} . 'Hz';
        } elsif ($element->{variable_id} == 188) {
            $ydinvoima = '☢️ ' . $element->{value} . 'MW';
        } elsif ($element->{variable_id} == 191) {
            $vesivoima = '🌊 ' . $element->{value} . 'MW';
        } elsif ($element->{variable_id} == 209) {
            my $lv_temp = $element->{value};
            if ($lv_temp > 0) {
                $liikennevalo = $lv_temp . '!';
            }
            print($IRSSI{name} . '> liikennevalo: ' . $lv_temp);
        } elsif ($element->{variable_id} == 267) {
            # solar production capacity
            $aurinkokapa =  $element->{value} . 'MW';
        } elsif ($element->{variable_id} == 248) {
            #$aurinkoennuste = '😎 ' . $element->{value} . '/';
        } elsif ($element->{variable_id} == 336) {
            $sahkopula = $element->{value};
        }
    }
    $aurinkoennuste = '😎 ' . $av_arvio . '/';
    return "Kokonaiskulutus: $kulutus. Tuotanto: $tuotanto, $ydinvoima, $tuulivoima, $vesivoima, ${aurinkoennuste}${aurinkokapa} ~${taajuus}";
}

sub fetch_price_data {
    my $uri = get_sahko_url();
    my $json_string = KaaosRadioClass::getJSON($uri);
    return undef if $json_string eq '-1';
    return $json_string->{price};
}

sub fetch_fingrid_data {
    my ($url, @rest) = @_;
    my $uri = URI->new($url);
    my $ua = LWP::UserAgent->new;
    $ua->default_header('x-api-key' => $apikey);
    my $res = $ua->get($uri);
    if ($res->is_success) {
        my $json_decd = decode_json($res->decoded_content);
        return $json_decd;
    }
    return;
}

Irssi::signal_add_last('message public', 'pub_msg');
