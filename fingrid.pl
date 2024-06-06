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
use Time::HiRes;

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
248 Aurinkovoiman tuotantoennuste, tuntikohtainen. 36h ennuste, av_arvio
267 Aurinkovoimaennusteessa käytetty kokonaiskapasiteetti, aurinkokapa
306 
336 Sähköpula, tilannetieto

icons:
☢️ radioactive
🔌 töpseli
🌊 water wave
💨 wind blow
=cut

my $counter = 0;
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

#my @datasets = qw(177 181 188 191 192 193 209 248 267 336);
my @datasets = qw(177 181 188 191 192 193 267);
my $aurinkokapa = 0;
my $av_arvio = 0;
my $av_last_updated = 0;
my $ak_last_updated = 0;

sub get_fingrid_url {
    my ($dataset_id, @rest) = @_;
    #return 'https://api.fingrid.fi/v1/variable/event/json/177,181,188,191,192,193,209,248,267,336';
    #return 'https://data.fingrid.fi/api/data?datasets=177,181,188,191,192,193,209,248,267,336';
    return "https://data.fingrid.fi/api/datasets/$dataset_id/data/latest";
}

sub get_fingrid_url2 {
    my $dt = DateTime->now;
    my $dura_begin = DateTime::Duration->new(minutes => -5);
    #my $start_time = ($dt + $dura_begin)->iso8601 . 'Z';
    my $start_time = ($dt + $dura_begin)->strftime('%Y-%m-%dT%H:%MZ');
    #my $temp = "https://data.fingrid.fi/api/data?datasets=177,181,188,191,192,193,209,336&pageSize=1&sortBy=startTime&sortOrder=desc&startTime=$start_time";
    my $temp = "https://data.fingrid.fi/api/data?datasets=177,181,188,191,192,193,209,336&sortBy=startTime&sortOrder=desc&startTime=$start_time";
    Irssi::print('temp: ' . $temp);
    return $temp;
}

sub get_porssisahko_url {
    my ($offset, @rest) = @_;
    my $datetime = DateTime->now(time_zone => 'Europe/Helsinki');
    my $datestring = $datetime->ymd;
    my $timestring = $datetime->hour;
    my @localtime = localtime();

    # Get the current GMT time
    my @gmtime = gmtime;

    # Calculate the time difference in hours
    my $timezone = ($localtime[2] - $gmtime[2]);
    $timestring += $offset if defined $offset;

    my $newurl = $sahkourl . $datestring . '&hour=' .($timestring);
    print($IRSSI{name} . '> pörssisähkö-url (timezone: '.$timezone.'h, offset: '.$datetime->offset.'): ' . $newurl);
    return $newurl;
}

# 15 minute interval
sub get_aurinkovoima_arvio {
    if (time - $av_last_updated < (60*15) && $av_arvio != 0) {
        return $av_arvio;
    }
    my $dt = DateTime->now;
    my $dura_begin = DateTime::Duration->new(hours => -1);
    my $timestring_begin = ($dt + $dura_begin)->strftime('%Y-%m-%dT%H:%MZ');
    my $timestring_end = $dt->strftime('%Y-%m-%dT%H:%MZ');
    my $aurinkourl = 'https://data.fingrid.fi/api/datasets/248/data?start_time=' . $timestring_begin . '&end_time=' .$timestring_end;
    my $jsondata = fetch_fingrid_data($aurinkourl, 1);
    #return $jsondata->{data}[0][0]->{value};

    foreach my $data ($jsondata->{data}[0]) {
        # latest data is first on list
        print __LINE__ . ', aurinkovoima arvio next:';
        print Dumper $data;
        $av_arvio = $data->{value};
        #return $data->{value};
        $av_last_updated = time;
        return $av_arvio;
    }
}

sub get_aurinkokapasiteetti {
    if (time - $ak_last_updated < (60*60*24) && $aurinkokapa != 0) {
        return $aurinkokapa;
    }
    my $url = "https://data.fingrid.fi/api/datasets/267/data/latest";
    my $jsondata = fetch_fingrid_data($url, 0);
    print __LINE__ .': aurinkokapa value dump next';
    print Dumper $jsondata->{value};
    $aurinkokapa = $jsondata->{value};
    $ak_last_updated = time;
    return $aurinkokapa;


    #foreach my $data ($jsondata->{data}) {
    #    $aurinkokapa = $data->{value};
    #    Irssi::print('aurinkokapa: ' . $aurinkokapa);
    #    $ak_last_updated = time;
    #    return $aurinkokapa;
    #}
}

sub get_help {
	return '!sähkö tulostaa kanavalle tietoja Suomen sähköverkon tilasta. Data haetaan Fingridin rajapinnasta. Sähkön hinta tulee muualta!"';
}

sub pub_msg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;

	return if ($nick eq $serverrec->{nick});   #self-test
	if ($msg =~ /^(!help sähkö)/sgi) {
		return if KaaosRadioClass::floodCheck();
		my $help = get_help();
		$serverrec->command("MSG $target $help");
	} elsif ($msg =~ /^(!sähkö)/sgi) {
		return if KaaosRadioClass::floodCheck();
        my $av_arvio2 = get_aurinkovoima_arvio();
        my $aurinkokapa2 = get_aurinkokapasiteetti();
        my $price = fetch_price_data();
        
        my $json = fetch_fingrid_data(get_fingrid_url2(), 0);
		my $newdata = parse_sahko_data($json, $av_arvio2);
        #my $newdata = parse_fingrid_data($av_arvio);
		
		$serverrec->command("MSG $target $price $newdata");
		print($IRSSI{name}."> request from $nick on channel $target");
	}
}

sub parse_sahko_data {
    my ($jsondata, $av_arvio, @rest) = @_;
    #print Dumper $jsondata;
    my $tuotanto = '';          # 192
    my $kulutus = '';           # 193
    my $tuulivoima = '';        # 181
    my $taajuus = '';           # 177
    my $ydinvoima = '';         # 188
    my $vesivoima = '';         # 191
    my $liikennevalo = '';      # 209
    my $aurinkoennuste = '';    # 248
    my $aurinkokapa2 = '';       # 267
    my $sahkopula = '';         # 336
    my $json_ref = $jsondata->{data};
    foreach my $element (@$json_ref) {
        next unless defined $element->{datasetId};
        if ($element->{datasetId} == 192) {
            $tuotanto = $element->{value} . 'MW';
        } elsif ($element->{datasetId} == 193) {
            $kulutus = $element->{value} . 'MW';
        } elsif ($element->{datasetId} == 181) {
            $tuulivoima = '💨 ' . $element->{value} . 'MW';
        } elsif ($element->{datasetId} == 177) {
            $taajuus = $element->{value} . 'Hz';
        } elsif ($element->{datasetId} == 188) {
            $ydinvoima = '☢️ ' . $element->{value} . 'MW';
        } elsif ($element->{datasetId} == 191) {
            $vesivoima = '🌊 ' . $element->{value} . 'MW';
        } elsif ($element->{datasetId} == 209) {
            my $lv_temp = $element->{value};
            if ($lv_temp > 0) {
                $liikennevalo = $lv_temp . '!';
            }
            print($IRSSI{name} . '> liikennevalo: ' . $lv_temp);
        } elsif ($element->{datasetId} == 267) {
            # solar production capacity
            $aurinkokapa =  $element->{value} . 'MW';
        #} elsif ($element->{datasetId} == 248) {
            #$aurinkoennuste = '😎 ' . $element->{value} . '/';
        } elsif ($element->{datasetId} == 336) {
            $sahkopula = $element->{value};
        }
    }
    $aurinkoennuste = '😎 ' . $av_arvio . '/' . $aurinkokapa;
    return "\002Kulutus:\002 $kulutus. \002Tuotanto:\002 $tuotanto, $ydinvoima, $tuulivoima, $vesivoima, ${aurinkoennuste}, ~${taajuus}";
}

sub parse_fingrid_data {
    my ($av_arvio, @rest) = @_;
    #tuotanto 192
    #kulutus 193
    #tuulivoima 181
    #taajuus 177
    #ydinvoima 188
    #vesivoima 191
    #liikennevalo 209
    #aurinkoennuste 248 and 267
    #aurinkokapa 267
    #sahkopula 336

    my $returnvalue = '';
    my $tot = 'tot: ';
    my $kulutus = 'Kulutus: ';
    my $tuuli = '💨 ';
    my $taajuus = '';
    my $ydinvoima = '☢️ ';
    my $vesi = '🌊 ';
    my $liikennevalo = '';
    #my $aurinkokapa = '';
    my $sahkopula = '';

    foreach my $dataset_id (@datasets) {
        next if $dataset_id == 267 && $aurinkokapa != 0;
        my $element = fetch_fingrid_data("https://data.fingrid.fi/api/datasets/$dataset_id/data/latest", 0);
        next unless defined $element->{datasetId};
        #print __LINE__ . ', dataset id: ' . $element->{datasetId};
        #print Dumper $element;
        if ($element->{datasetId} == 192) {
            $tot .= $element->{value} . 'MW';
        } elsif ($element->{datasetId} == 193) {
            $kulutus .= $element->{value} . 'MW';
        } elsif ($element->{datasetId} == 181) {
            $tuuli .= $element->{value} . 'MW';
        } elsif ($element->{datasetId} == 177) {
            $taajuus = '~' . $element->{value} . 'Hz';
        } elsif ($element->{datasetId} == 188) {
            $ydinvoima .= $element->{value} . 'MW';
        } elsif ($element->{datasetId} == 191) {
            $vesi .= $element->{value} . 'MW';
        } elsif ($element->{datasetId} == 209) {
            print __LINE__ . ' liikennevalo: ' . $element->{value};
            my $lv_temp = $element->{value};
            if ($lv_temp > 1) {
                $returnvalue .= ' Liikennevalo: ' . $lv_temp . '! ';
            }
            print($IRSSI{name} . '> liikennevalo: ' . $lv_temp);

        } elsif ($element->{datasetId} == 267) {
            print __LINE__ . ' aurinkokapa: ' . $element->{value};
            # solar production capacity
            $aurinkokapa =  $element->{value} . 'MW';
            #$returnvalue .= '😎 ' . $av_arvio . '/' . $aurinkokapa;
        #} elsif ($element->{datasetId} == 248) {
            #$aurinkoennuste = '😎 ' . $element->{value} . '/';
        } elsif ($element->{datasetId} == 336) {
            print __LINE__ . ' sähköpula: ' . $element->{value};
            $sahkopula = $element->{value};
            if ($sahkopula > 0) {
                $returnvalue .= ' Sähköpula: ' . $sahkopula;
            }
        }
    }
    $returnvalue = "Tuotanto: $tot, $ydinvoima, $vesi, $tuuli, $taajuus, ";
    $returnvalue .= '😎 ' . $av_arvio . '/' . $aurinkokapa . '. ';
    $returnvalue .= $kulutus;
    Irssi::print(__LINE__. ' returnvalue: ' . $returnvalue);
    return $returnvalue;
}

sub fetch_price_data {
    my $returnvalue = '';
    my $uri = get_porssisahko_url();
    my $json_string = KaaosRadioClass::getJSON($uri);
    return 'Pörssisähkön hintatietoa ei saatu.' if $json_string eq '-1';
    $returnvalue = "\002Hinta:\002 " . $json_string->{price};

    my $json_string2 = KaaosRadioClass::getJSON(get_porssisahko_url(1));
    return $returnvalue if $json_string2 eq '-1';
    $returnvalue .= 'c, +1h: ' . $json_string2->{price} . 'c.';
    return $returnvalue;
}

sub fetch_fingrid_data {
    my ($url, $firstTime, @rest) = @_;
    #Time::HiRes::sleep 1.3 unless $firstTime == 1;
    sleep(2);
    print ("ur lafter sleep: $url" );
    my $uri = URI->new($url);
    my $ua = LWP::UserAgent->new;
    $ua->default_header('x-api-key' => $apikey);
    my $res = $ua->get($uri);
    if ($res->is_success) {
        my $json_decd = JSON->new->utf8;
        $json_decd->convert_blessed(1);
        $json_decd = decode_json($res->decoded_content);
        #print __LINE__ . ' fetched fingrid data succesfully';
        #print Dumper $json_decd;
        return $json_decd;
    }
    Irssi::print($IRSSI{name} . '> not success: ('.$url.') ' . $res->status_line);
    #print Dumper $res;
    return;
}

Irssi::signal_add_last('message public', 'pub_msg');