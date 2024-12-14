use Irssi;
use vars qw($VERSION %IRSSI);
use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';  # Terminal expects UTF-8
use POSIX;
use Data::Dumper;
use JSON;
use POSIX;
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
	changed => '2024-07-09',
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
my $sahkohintaurl = 'https://sahkohinta-api.fi/api/v1/halpa?tunnit=12&tulos=sarja&aikaraja=';
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
    my $dura_begin = DateTime::Duration->new(minutes => -5);
    my $start_time = ($dt + $dura_begin)->strftime('%Y-%m-%dT%H:%MZ');
    #my $temp = "https://data.fingrid.fi/api/data?datasets=177,181,188,191,192,193,209,336&pageSize=1&sortBy=startTime&sortOrder=desc&startTime=$start_time";
    my $temp = "https://data.fingrid.fi/api/data?datasets=177,181,188,191,192,193,209,336&sortBy=startTime&sortOrder=desc&startTime=$start_time";
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
    my $jsondata = fetch_fingrid_api_data($aurinkourl, 1);
    return -1 if $jsondata eq '-1';
    my $json_ref = $jsondata->{data};
    foreach my $data (@$json_ref) {
        # latest data is first on list, because sortOrder=desc
        $av_arvio = $data->{value};
        $av_last_updated = time;
        return $av_arvio;
    }
}

# safe 24h interval, because total capacity does not change often
sub get_aurinkokapasiteetti {
    if ((time - $ak_last_updated) < (60*60*24) && $aurinkokapa != 0) {
        return $aurinkokapa;
    }
    my $url = "https://data.fingrid.fi/api/datasets/267/data/latest";
    my $jsondata = fetch_fingrid_api_data($url, 0);
    return -1 if $jsondata == -1;
    #print __LINE__ .': aurinkokapa value dump next' if $DEBUG;
    #print Dumper $jsondata->{value} if $DEBUG;
    $aurinkokapa = $jsondata->{value};
    $ak_last_updated = time;
    return $aurinkokapa;
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

        my $av_arvio2 = get_aurinkovoima_arvio();
        print ("av_arvio2: $av_arvio2");
        #my $aurinkokapa2 = get_aurinkokapasiteetti();
        #my $newdata = parse_fingrid_data($av_arvio);
        my $jsondata = fetch_fingrid_api_data(create_fingrid_url(), 0);
        my $printstring = parse_sahko_data($jsondata, $av_arvio2);


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
    my $now = time;
    my $returnvalue = 'Pörssisähkön hintatietoa ei saatu.';
    my $timestamp = DateTime->now(time_zone => 'Europe/Helsinki');
    $timestamp = $timestamp->strftime('%Y-%m-%dT%H:00');

    my $timestamp2 = DateTime->now(time_zone => 'Europe/Helsinki');
    my $duration = DateTime::Duration->new(hours => 1);
    $timestamp2 += $duration;
    $timestamp2 = $timestamp2->strftime('%Y-%m-%dT%H:00');

    if (defined($pricedata->{$timestamp}) && defined($pricedata->{$timestamp2})) {
        prind("Using saved price data..");
        process_price_data($pricedata, $timestamp, $timestamp2);
        return;
    }

    my $pid = fork();
    $forked = 1;

    if (!defined $pid) {
        prindw("Cannot fork: $!");
    } elsif ($pid == 0) {
        # child process
        $pricedata = fetch_price_data2();
        print $wh encode_json($pricedata);
        close $wh;
        POSIX::_exit(1); # Exit child process
    } else {
        # parent
        close $wh;
        prind(__LINE__ . ": Parent process, forked a child with PID: $pid") if $DEBUG;
        Irssi::pidwait_add($pid);
        my $pipetag;
        my @args = ($rh, \$pipetag, $timestamp, $timestamp2);
        $pipetag = Irssi::input_add(fileno($rh), INPUT_READ, \&pipe_input, \@args);
    }
}

sub do_sahkokatkot($) {
    my ($searchword, @rest) = @_;
    #return if $forked_sk;
    prind(__LINE__ . ": Fetching power outage data...") if $DEBUG;
    my $h = HTTP::Headers->new;
    $h->header('Accept-Encoding' => 'gzip,deflate,br', 'Host' => 'sqtb-api.azureedge.net');
    my $jsondata = KaaosRadioClass::getJSON($katkourl, $h);
    #print Dumper $jsondata if $DEBUG;
    if ($jsondata ne '-1') {
        my $printstring = parse_sahkokatkot_data($searchword, $jsondata);
        msg_channel($printstring);
    } else {
        msg_channel("Sähkökatkotietoja ei saatu.");
    }
}

sub parse_sahkokatkot_data {
    my ($searchword, $jsondata, @rest) = @_;
    my $json_areas = $jsondata->{areas};
    my $json_companies = $jsondata->{companies};
    my $printstring = '';
    #prind(__LINE__ . ": did we get anything? searchword, searchword: " . $searchword) if $DEBUG;
    foreach my $element (@$json_areas) {
        #print Dumper ($element) if $DEBUG;
        my $area = $element->{name};
        my $alias = $element->{alias};
        
        my $faults = $element->{fault} || 0;
        my $maxday = $element->{maxday};
        my $url = $element->{outagemap} || '';
        #prind(__LINE__ . " area: " . $area . ', searchword: ' . $searchword . ", faults: $faults, maxday: $maxday") if $DEBUG;
        if ($area =~ /$searchword/i || $alias =~ /$searchword/i) {
            prind(__LINE__ . " area: " . $area . ', alias: ' . $alias . ', faults: ' . $faults . ', maxday: ' . $maxday . ', url: '. $url) if $DEBUG;
            $printstring .= "\002$area:\002 Sähköttä nyt: $faults (max tänään: $maxday) $url ";
            #last;
        }
    }
    #prind(__LINE__ . ': done part 1.. printstring: '. $printstring) if $DEBUG;

    foreach my $element (@$json_companies) {
        my $company = $element->{name};
        my $alias = $element->{alias};
        my $faults = $element->{fault} || 0;
        my $maxday = $element->{maxday};
        my $url = $element->{outagemap} || '';
        if ($company =~ /$searchword/i || $alias =~ /$searchword/i) {
            prind(__LINE__ . " company: " . $company) if $DEBUG;
            $printstring .= "\002$company:\002 Sähköttä nyt: $faults (max tänään: $maxday) $url ";
            #last;
        }
    }

    prind("printstring: $printstring") if $DEBUG;
    return $printstring;
}

sub parse_sahko_data($$) {
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
            prind('liikennevalo: ' . $lv_temp);
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
    return "\002Kokonaiskulutus:\002 $kulutus. \002Tuotanto:\002 $tuotanto, $ydinvoima, $tuulivoima, $vesivoima, ${aurinkoennuste}, ~${taajuus}";
}

sub fetch_price_data2 {
    my $url = get_sahkohinta_api_url();
    my $json_data = '-1';
    $json_data = KaaosRadioClass::getJSON($url);
    if ($json_data ne '-1') {
        foreach my $data (@$json_data) {
            my $timestamp = $data->{aikaleima_suomi};
            my $price = $data->{hinta};
            $pricedata->{$timestamp} = $price;
        }
        return $pricedata;
    } else {
        prindw("JSON data not found.");
    }
}

sub pipe_input($$) {
    my ($rh, $pipetage, $time1, $time2) = @{$_[0]};
    my $data;
    {
        select($rh);
        local $/;
        select(CLIENTCRAP);
        $data = <$rh>;
        close($rh);
    }

    Irssi::input_remove($$pipetage);
    return unless $data;

    $pricedata = decode_json($data);
    process_price_data($pricedata, $time1, $time2);
    $forked = 0;
}

sub pipe_input_fingrid($$$$) {
    my ($rh, $pipetage, $time1, $time2) = @{$_[0]};
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
    return unless $data;
    msg_channel($data);
}

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
    return unless $data;
    msg_channel($data);
}


sub process_price_data($$$) {
    my ($pricedata, $time1, $time2) = @_;
    my $msg = 'Pörssisähkön hintatietoa ei saatu.';
    my $timenow = DateTime->now(time_zone => 'Europe/Helsinki');
    $timenow = $timenow->strftime('%H:00');

    if (defined $pricedata->{$time1}) {
        my $price1 = sprintf("%.2f", $pricedata->{$time1});
        $msg = "\002Pörssisähkön hinta (Alv 0%) (klo. $timenow):\002 " . $price1 . 'c/kwh';
    }
    if (defined $pricedata->{$time2}) {
        my $price2 = sprintf("%.2f", $pricedata->{$time2});
        $msg .= ", \002+1h:\002 " . $price2 . 'c/kwh';
    }
    msg_channel($msg);
}

sub fetch_fingrid_api_data {
    my ($url, $firstTime, @rest) = @_;
    sleep(2) unless $firstTime;
    prind("fingrid url: $url");
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
prind("$IRSSI{name} v$VERSION loaded.");
Irssi::signal_add_last('message public', 'pub_msg');