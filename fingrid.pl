use Irssi;
use vars qw($VERSION %IRSSI);
use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';  # Terminal expects UTF-8
use POSIX;
use Data::Dumper;
use JSON;
use DateTime;
use Time::HiRes;
use HTTP::Headers;
use LWP::UserAgent;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;

$VERSION = '0.2';
%IRSSI = (
	authors => 'LAama1',
	contact => 'LAama1@ircnet',
	name => 'fingrid',
	description => 'Suomen sähkönkulutuksen tiedot',
	license => 'BSD',
	url => 'http://www.kaaosradio.fi',
	changed => '2026-02-22',
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
my $timeout_tag;
my $DEBUG = 1;
#my $pid;
my $server_t;   # for fork processes
my $target_t;   # for fork processes

#my $sahkohintaurl = 'https://api.porssisahko.net/v1/price.json?date=';   # 2023-08-18&hour=14';

# sahkohinta-api.fi
my $sahkohintaurl = 'https://www.sahkohinta-api.fi/api/v1/halpa?tunnit=12&tulos=sarja&aikaraja=';
my $sahkohintatanaan = 'https://www.sahkonhintatanaan.fi/api/v1/prices/';
# https://www.sahkonhintatanaan.fi/api/v1/prices/2025/11-23.json
#my $sahkohintaurl = 'https://kd.8-b.fi/test.json?';
my $katkourl = 'https://sqtb-api.azureedge.net/outagemap/tailored/summary/';
my $pricedata = {};
my $katkodata = {};
my $forked = 0;
my $borked = 0;
#my $forked_sk = 0;

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

sub create_fingrid_url {
    my $dt = DateTime->now; # UTC
    my $dura_begin = DateTime::Duration->new(minutes => -15);
    my $dura_end = DateTime::Duration->new(minutes => 15);
    my $startTime = ($dt + $dura_begin)->strftime('%Y-%m-%dT%H:%MZ');
    my $endTime = ($dt + $dura_end)->strftime('%Y-%m-%dT%H:%MZ');
    #my $temp = "https://data.fingrid.fi/api/data?datasets=177,181,188,191,192,193,209,336&pageSize=1&sortBy=startTime&sortOrder=desc&startTime=$start_time";
    #my $temp = "https://data.fingrid.fi/api/data?datasets=177,181,188,191,192,193,209,336&sortBy=startTime&sortOrder=desc&startTime=$start_time";
    my $temp = "https://data.fingrid.fi/api/data?pageSize=10&datasets=177,181,188,191,192,193,209,248,336&sortBy=startTime&sortOrder=desc&startTime=$startTime&endTime=$endTime";
    return $temp;
}

# obsolete
sub create_porssisahko_url {
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

    my $newurl = $sahkohintaurl . $datestring . '&hour=' .($timestring);
    return $newurl;
}

sub get_sahkohinta_api_url {
    my $datetime = DateTime->now(time_zone => 'Europe/Helsinki');
    my $duration = DateTime::Duration->new(hours => 12);
    my $enddatetime = $datetime + $duration;

    my $datetimestring = $datetime->strftime('%Y-%m-%dT%H:00');
    $datetimestring .= '_';
    $datetimestring .= $enddatetime->strftime('%Y-%m-%dT%H:00');

    my $newurl = $sahkohintaurl . $datetimestring;
    return $newurl;
}

sub create_sahkohinta_tanaan_url {
    my $datetime = DateTime->now(time_zone => 'Europe/Helsinki');
    my $yearstring = $datetime->strftime('%Y/%m-%d');
    my $newurl = $sahkohintatanaan . $yearstring . '.json';
    return $newurl;
}

# 15 minute interval in data availability
sub get_aurinkovoima_arvio {
    if ((time - $av_last_updated) < (60*15) && $av_arvio != 0) {
        return $av_arvio;
    }
    my $dt = DateTime->now; # UTC
    my $dura_begin = DateTime::Duration->new(minutes => -16);
    my $timestring_begin = ($dt + $dura_begin)->strftime('%Y-%m-%dT%H:%MZ');
    my $timestring_end = $dt->strftime('%Y-%m-%dT%H:%MZ');
    my $aurinkourl = 'https://data.fingrid.fi/api/datasets/248/data?sortOrder=desc&sortBy=startTime&startTime=' . $timestring_begin . '&endTime=' .$timestring_end;

    #my $aurinkourl = 'https://data.fingrid.fi/api/datasets/248/data/latest';
    my $jsondata = fetch_fingrid_api_data($aurinkourl, 1);
    return -1 if $jsondata eq '-1';
    $av_arvio = $jsondata->{value};
    $av_last_updated = time;
    return $av_arvio;
}

# safe 24h interval
sub get_aurinkokapasiteetti {
    if ((time - $ak_last_updated) < (60*60*12) && $aurinkokapa != 0) {
        return $aurinkokapa;
    }
    #my $url = "https://data.fingrid.fi/api/datasets/267/data/latest";
    my $dt = DateTime->now; # UTC
    my $dura_begin = DateTime::Duration->new(minutes => -120);
    my $startTime = ($dt + $dura_begin)->strftime('%Y-%m-%dT%H:%MZ');
    my $endTime = $dt->strftime('%Y-%m-%dT%H:%MZ');
    my $url = "https://data.fingrid.fi/api/datasets/267/data/?sortOrder=desc&sortBy=startTime&starTime=$startTime&endTime=$endTime";

    my $jsondata = fetch_fingrid_api_data($url, 0);
    return -1 if $jsondata == -1;
    my $json_ref = $jsondata->{data};
    foreach my $data (@$json_ref) {
        next unless defined $data->{datasetId};
        $aurinkokapa = $data->{value};
        $ak_last_updated = time;
        return $aurinkokapa;
    }
    return -1;
}

sub get_help {
	return '!sähkö tulostaa kanavalle tietoja Suomen sähköverkon tilasta. Data haetaan Fingridin rajapinnasta. Sähkön hinta tulee muualta!"';
}

sub pub_msg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;
    my $mynick = quotemeta $serverrec->{nick};
	return if ($nick eq $mynick);   #self-test

    $msg = Encode::decode('UTF-8', $msg);
	if ($msg =~ /^\!help sähkö/sgi) {
		return if KaaosRadioClass::floodCheck();
		my $help = get_help();
		$serverrec->command("MSG $target $help");
	} elsif ($msg =~ /^\!sähkö$/sgi || $msg =~ /^\!sahko$/sgi) {
        #prind("sähkö request from $nick on channel $target") if $DEBUG;
		return if KaaosRadioClass::floodCheck();
		$forked = 0;	# DIRTY HACK
        $target_t = $target;
        $server_t = $serverrec;

        do_fingrid();
        do_sahkonhinta();
		prind("!sähkö request from $nick on channel $target");
	} elsif ($msg =~ /^\!sahkokatko[t]? (.*)/sgi || $msg =~ /^\!sähkökatko[t]? (.*)/sgi) {
        my $searchword = $1;
        #prind('got: '. $searchword) if $DEBUG;
        return if KaaosRadioClass::floodCheck();
        #prind("sähkökatkot request from $nick on channel $target, search for: $searchword");
        $target_t = $target;
        $server_t = $serverrec;
        do_sahkokatkot($searchword);
        prind("!sähkökatko request from $nick on channel $target, done");
    } elsif ($msg =~ /^!sähkökatko[t]?$/sgi || $msg =~ /^!sahkokatko[t]?$/sgi) {
        return if KaaosRadioClass::floodCheck();
        #prind("sähkökatkot request from $nick on channel $target");
        $target_t = $target;
        $server_t = $serverrec;
        do_sahkokatkot('');  # empty searchword
        prind("!sähkökatkot request from $nick on channel $target, done");
    }
}

sub do_fingrid {
    return if $borked;
    my ($rh, $wh);
    pipe($rh, $wh);  # read handle, write handle
    my $pid = fork();
    $borked = 1;
    if (!defined $pid) {
        prindw("Cannot fork: $!");
    } elsif ($pid == 0) {
        # child

        my $aurinkokapa2 = get_aurinkokapasiteetti();
        #my $newdata = parse_fingrid_data($av_arvio);
        my $jsondata = fetch_fingrid_api_data(create_fingrid_url(), 0);
        my $printstring = parse_sahko_data($jsondata, $aurinkokapa2);
        print $wh $printstring;
        close $wh;
        POSIX::_exit(1); # Exit child process
    } else {
        # parent
        close $wh;
        #prind("Parent process, forked a child with PID: $pid");
        Irssi::pidwait_add($pid);
        my $pipetag;
        my @args = ($rh, \$pipetag);
        $pipetag = Irssi::input_add(fileno($rh), INPUT_READ, \&pipe_input_fingrid, \@args);
    }
}

sub do_sahkonhinta {
    return if $forked;
    prind("Fetching price data...");
    my ($rh, $wh);
    pipe($rh, $wh);  # read handle, write handle
    my $timestamp = DateTime->now(time_zone => 'Europe/Helsinki');
    my $tz_offset = $timestamp->strftime('%z');
    $tz_offset =~ s/(\d{2})(\d{2})/$1:$2/; # +0200 --> +02:00
    $timestamp = $timestamp->strftime('%Y-%m-%dT%H:00:00') . $tz_offset;

    my $timestamp2 = DateTime->now(time_zone => 'Europe/Helsinki');
    my $duration = DateTime::Duration->new(hours => 1); # 1 hour duration
    $timestamp2 += $duration;
    $timestamp2 = $timestamp2->strftime('%Y-%m-%dT%H:00:00') . $tz_offset;

	my $timestamp3 = DateTime->now(time_zone => 'Europe/Helsinki');
	$timestamp3 += ($duration + $duration);
	$timestamp3 = $timestamp3->strftime('%Y-%m-%dT%H:00:00') . $tz_offset;
    if (defined($pricedata->{$timestamp}) && defined($pricedata->{$timestamp2}) && defined($pricedata->{$timestamp3}) ) {
        prind("Using saved price data..");
        process_price_data($pricedata, $timestamp, $timestamp2, $timestamp3);
        return;
    }
    KaaosRadioClass::df(__LINE__ . " fg: sahkohinta_api_url: " . get_sahkohinta_api_url());
    my $pid = fork();
    $forked = 1;

    if (!defined $pid) {
        prindw("Cannot fork: $!");
    } elsif ($pid == 0) {
        # child process
        $pricedata = fetch_price_data2();
        KaaosRadioClass::df(__LINE__ . " fg: " . Dumper(\$pricedata));
        print $wh encode_json($pricedata) if $pricedata;
        close $wh;
        POSIX::_exit(1); # Exit child process
    } else {
        # parent
        close $wh;
        Irssi::pidwait_add($pid);
        my $pipetag;
        my @args = ($rh, \$pipetag, $timestamp, $timestamp2, $timestamp3);
        $pipetag = Irssi::input_add(fileno($rh), INPUT_READ, \&pipe_input_price, \@args);
    }
}

sub do_sahkokatkot($) {
    my ($searchword, @rest) = @_;
    #return if $forked_sk;
    prind(__LINE__ . ": Fetching power outage data...") if $DEBUG;
    my $h = HTTP::Headers->new;
    $h->header('Accept-Encoding' => 'gzip,deflate,br', 'Host' => 'sqtb-api.azureedge.net');
    my $jsondata = KaaosRadioClass::getJSON($katkourl, $h);
    KaaosRadioClass::df(__LINE__ . " fg: " . Dumper $jsondata) if $DEBUG;
    if ($jsondata ne '-1') {
        my $printstring = parse_sahkokatkot_data($searchword, $jsondata);
        msg_channel($printstring);
    } else {
        msg_channel("Sähkökatkotietoja ei saatu.");
    }
}

sub create_timestamps {

}

sub parse_sahkokatkot_data {
    my ($searchword, $jsondata, @rest) = @_;
    my $json_areas = $jsondata->{areas};
    my $json_companies = $jsondata->{companies};
    my $printstring = '';
    my %result_hash;

    foreach my $element (@$json_areas) {

        my $area = $element->{name};
        my $alias = $element->{alias};
        
        my $faults = $element->{fault} || 0;
        my $maxday = $element->{maxday};
        my $url = $element->{outagemap} || '';

        $result_hash{$area} =  {
            'alias' => $alias,
            'faults' => $faults,
            'maxday' => $maxday,
            'url' => $url
        }
    }

    foreach my $element (@$json_companies) {
        my $company = $element->{name};
        my $alias = $element->{alias};
        my $faults = $element->{fault} || 0;
        my $maxday = $element->{maxday} || 0;
        my $url = $element->{outagemap} || '';

        $result_hash{$company} =  {
            'alias' => $alias,
            'faults' => $faults,
            'maxday' => $maxday,
            'url' => $url
        }
    }

    #foreach my $key (keys %result_hash) {
    my $index = 0;
    foreach my $key (sort { $result_hash{$b}->{faults} <=> $result_hash{$a}->{faults} } keys %result_hash) {
        my $value = $result_hash{$key};
        my $alias = $value->{alias};
        my $faults = $value->{faults};
        my $maxday = $value->{maxday};
        my $url = $value->{url};
        if ($searchword eq '') {
            prind(__LINE__ . " area/city: " . $key) if $DEBUG;
            $printstring .= "\002$key:\002 Sähköttä nyt: $faults (max tänään: $maxday) $url ";
        }
        $index++;
        last if $index > 5; # max 5 items
    }

    prind("printstring: $printstring") if $DEBUG;
    return $printstring;
}

sub parse_sahko_data($$) {
    my ($jsondata, $aurinkokapa, @rest) = @_;
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
            #prind('liikennevalo: ' . $lv_temp);
        } elsif ($element->{datasetId} == 267) {
            # solar production capacity
            $aurinkokapa =  $element->{value} . 'MW';
        } elsif ($element->{datasetId} == 248) {
            $aurinkoennuste = $element->{value};
        } elsif ($element->{datasetId} == 336) {
            $sahkopula = $element->{value};
        }
    }
    $aurinkoennuste = '😎 ' . $aurinkoennuste . '/' . $aurinkokapa . 'MW';
    #$aurinkoennuste = $aurinkoennuste . '/' . $aurinkokapa . 'MW';
    return "\002Kokonaiskulutus:\002 $kulutus. \002Tuotanto:\002 $tuotanto, $ydinvoima, $tuulivoima, $vesivoima, ${aurinkoennuste} ~${taajuus}";
}

sub fetch_price_data2 {
    #my $url = get_sahkohinta_api_url();
    my $url = create_sahkohinta_tanaan_url();
    my $json_data = '-1';
    KaaosRadioClass::df(__LINE__ . " fg: Fetching price data from URL: $url") if $DEBUG;
    my $h = HTTP::Headers->new;
    $h->header('User-Agent' => 'curl/8.15.0');
    $json_data = KaaosRadioClass::getJSON($url, $h);
    if ($json_data ne '-1' and $json_data ne '-2') {
        foreach my $data (@$json_data) {
            #my $timestamp = $data->{aikaleima_suomi};
            #my $price = $data->{hinta};
            my $timestamp = $data->{time_start};
            my $price = $data->{EUR_per_kWh};
            $pricedata->{$timestamp} = $price;
            KaaosRadioClass::df(__LINE__ . " fg: Fetched price data: $timestamp => $price") if $DEBUG;
        }
        return $pricedata;
    } else {
        KaaosRadioClass::df(__LINE__ . " fg: JSON data not found. " . $json_data) if $DEBUG;
    }
    return undef;
}

sub pipe_input_price($$$$$) {
    my ($rh, $pipetage, $time1, $time2, $time3) = @{$_[0]};
    KaaosRadioClass::df(__LINE__ . " fg: pipe_input_price called... pipetage: " . Dumper(\$pipetage) . ', time1: ' . $time1 . ', time2: ' . $time2 . ', time3: ' . $time3) if $DEBUG;
    my $data;
    {
        select($rh);
        local $/;
        select(CLIENTCRAP);
        $data = <$rh>;
        close($rh);
    }

    Irssi::input_remove($$pipetage);
    KaaosRadioClass::df(__LINE__ . " fg: pipe_input_price data received: " . Dumper(\$data)) if $DEBUG;
    return unless $data;

	my $jsoni = JSON->new->utf8;
	$jsoni->convert_blessed(1);
    $jsoni = decode_json($data);
    $pricedata = decode_json($data);
    KaaosRadioClass::df(__LINE__ . ' fg: jsoni: ' . Dumper $jsoni) if $DEBUG;
    process_price_data($pricedata, $time1, $time2, $time3);
    $forked = 0;
}

sub pipe_input_fingrid($$$$) {
    my ($rh, $pipetage, $time1, $time2) = @{$_[0]};
    KaaosRadioClass::df(__LINE__ . " fg: pipe input fingrid called... pipetage: " . Dumper(\$pipetage)) if $DEBUG;
    my $data;
    {
        select($rh);
        local $/;
        select(CLIENTCRAP);
        $data = <$rh>;
        close($rh);
    }

    Irssi::input_remove($$pipetage);
    $borked = 0;
    KaaosRadioClass::df(__LINE__ . " fg: pipe_input_fingrid data received: " . Dumper(\$data)) if $DEBUG;
    return unless $data;
    msg_channel($data);
}

# not in use yet 2026-02-16
sub pipe_input_katkot($$) {
    my ($rh, $pipetage) = @{$_[0]};
    my $data;
    {
        select($rh);
        local $/;
        select(CLIENTCRAP);
        $data = <$rh>;
        close($rh);
    }

    Irssi::input_remove($$pipetage);
    #$forked_sk = 0;
    KaaosRadioClass::df(__LINE__ . " fg: pipe_input_katkot data received: " . Dumper(\$data)) if $DEBUG;
    return unless $data;
    msg_channel($data);
}

sub process_price_data($$$$) {
    my ($pricedata, $time1, $time2, $time3) = @_;
    my $msg = 'Pörssisähkön hintatietoa ei saatu.';
    my $timenow_dt = DateTime->now(time_zone => 'Europe/Helsinki');
    my $timenow = $timenow_dt->strftime('%H:00');
    KaaosRadioClass::df(__LINE__ . " fg: " . Dumper $pricedata) if $DEBUG;
    if (defined $pricedata->{$time1}) {
        my $price1 = sprintf("%.2f", $pricedata->{$time1}*100);
        $msg = "\002Pörssisähkön hinta (Alv 0%, 1h ka.) (klo. $timenow):\002 " . $price1 . 'c/kWh';
    }
    if (defined $pricedata->{$time2}) {
        my $price2 = sprintf("%.2f", $pricedata->{$time2}*100);
        $msg .= ", \002+1h:\002 " . $price2 . 'c/kWh';
    }
	if (defined $pricedata->{$time3}) {
		my $price3 = sprintf("%.2f", $pricedata->{$time3}*100);
		$msg .= ", \002+2h:\002 " . $price3 . 'c/kWh';
    }
    msg_channel($msg);
}

sub fetch_fingrid_api_data {
    my ($url, $firstTime, @rest) = @_;
    sleep(2) unless $firstTime;
    KaaosRadioClass::df(__LINE__ . " fg: fingrid url: $url") if $DEBUG;
    my $h = HTTP::Headers->new;
    $h->header('x-api-key' => $apikey);
    return KaaosRadioClass::getJSON($url, $h);
}

sub timeout_start {
    #fetch_price_data2();
	#$timeout_tag = Irssi::timeout_add(1*1000 *60*60, 'fetch_price_data2', undef);      # 1 hours
}

sub msg_channel {
    my ($text, @rest) = @_;
    $text && $server_t->command("MSG $target_t $text");
}

sub prind {
	my ($text, @test) = @_;
	print CLIENTCRAP "\0033" . $IRSSI{name} . ">\003 ". $text;
}
sub prindw {
	my ($text, @test) = @_;
	print CLIENTCRAP "\0034" . $IRSSI{name} . ">\003 ". $text;
}

timeout_start();

prind('Public commands:');
prind('!sähkö tai !sahko - Pörssisähkön hinta sekä sähkön tuotanto- ja kulutustietoja.');
prind('!sähkökatkot tai !sahkokatkot [hakusana] - Sähkökatkotiedot');

prind("$IRSSI{name} $VERSION loaded.");
Irssi::signal_add_last('message public', 'pub_msg');
