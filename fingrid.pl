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
use DateTime::Format::ISO8601;

$VERSION = '0.2';
my $DEBUG = 0;
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

#my $pid;
my $server_t;   # for fork processes
my $target_t;   # for fork processes
#my $alv = 1.255;  # tax 1 + 25.5 %
my $alv = 1.0;  # porssisahko.net will return price with tax included
my $marginal = 2.93; # tax snt / kwh

my $porssisahako_net_url = 'https://api.porssisahko.net/v2/latest-prices.json';   # dates are UTC';
my $sahkohintatanaan = 'https://api.porssisahko.net/v1/price.json?date=';   # 2023-08-18&hour=14';

# sahkohinta-api.fi
my $sahkohintaurl = 'https://www.sahkohinta-api.fi/api/v1/halpa?tunnit=12&tulos=sarja&aikaraja=';
#my $sahkohintatanaan = 'https://www.sahkonhintatanaan.fi/api/v1/prices/';
# https://www.sahkonhintatanaan.fi/api/v1/prices/2025/11-23.json

my $katkourl = 'https://sqtb-api.azureedge.net/outagemap/tailored/summary/';
my $pricedata = {};
my $katkodata = {};
my $forked = 0;
my $borked = 0;
#my $forked_sk = 0;
my $sahkokatkobuffer = {
    timestamp => 0,
    data => ""
};
my $apikey;
our $localdir = $ENV{HOME}."/.irssi/scripts/irssi-scripts/";
my $logfile = $localdir . "fingrid.log";
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

sub create_sahkohinta_api_url {
    my $datetime = DateTime->now(time_zone => 'Europe/Helsinki');
    my $duration = DateTime::Duration->new(hours => 12);
    my $enddatetime = $datetime + $duration;

    my $datetimestring = $datetime->strftime('%Y-%m-%dT%H:00');
    $datetimestring .= '_';
    $datetimestring .= $enddatetime->strftime('%Y-%m-%dT%H:00');

    my $newurl = $sahkohintaurl . $datetimestring;
    return $newurl;
}

sub create_porssisahko_net_url {
    return $porssisahako_net_url;
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
	if ($msg =~ /^\!help sähkö/sgi || $msg =~ /^\?s[aä]hk[oö]/sgi) {
		return if floodCheck();
		my $help = get_help();
		$serverrec->command("MSG $target $help");
	} elsif ($msg =~ /^\!s[aä]hk[oö]$/sgi) {
        #prindd("sähkö request from $nick on channel $target") if $DEBUG;
		return if floodCheck();
		$forked = 0;	# DIRTY HACK
        $target_t = $target;
        $server_t = $serverrec;

        do_fingrid();
		prindd("!sähkö request from $nick on channel $target");
	} elsif ($msg =~ /^\!sahkokatko[t]? (.*)/sgi || $msg =~ /^\!sähkökatko[t]? (.*)/sgi) {
        my $searchword = $1;
        #prindd('got: '. $searchword) if $DEBUG;
        return if floodCheck();
        #prindd("sähkökatkot request from $nick on channel $target, search for: $searchword");
        $target_t = $target;
        $server_t = $serverrec;
        do_sahkokatkot($searchword);
        prindd("!sähkökatko request from $nick on channel $target, done");
    } elsif ($msg =~ /^!sähkökatko[t]?$/sgi || $msg =~ /^!sahkokatko[t]?$/sgi) {
        return if floodCheck();
        #prindd("sähkökatkot request from $nick on channel $target");
        $target_t = $target;
        $server_t = $serverrec;
        do_sahkokatkot('');  # empty searchword
        prindd("!sähkökatkot request from $nick on channel $target, done");
    }
}

sub do_fingrid {
    return if $borked;
    my ($fg_rh, $fg_wh);
    pipe($fg_rh, $fg_wh);  # read handle, write handle
    my $pid = fork();
    $borked = 1;
    if (!defined $pid) {
        prinddw("Cannot fork: $!");
    } elsif ($pid == 0) {
        # child

        my $aurinkokapa2 = get_aurinkokapasiteetti();
        #my $newdata = parse_fingrid_data($av_arvio);
        my $jsondata = fetch_fingrid_api_data(create_fingrid_url(), 0);
        my $printstring = parse_fingrid_sahko_data($jsondata, $aurinkokapa2);
        print $fg_wh $printstring;
        close $fg_wh;
        POSIX::_exit(1); # Exit child process
    } else {
        # parent
        close $fg_wh;
        #prindd("Parent process, forked a child with PID: $pid");
        Irssi::pidwait_add($pid);
        my $pipetag;
        my @args = ($fg_rh, \$pipetag);
        $pipetag = Irssi::input_add(fileno($fg_rh), INPUT_READ, \&pipe_input_fingrid, \@args);
    }
}

sub do_sahkokatkot($) {
    my ($searchword, @rest) = @_;
    #return if $forked_sk;
    my $timestamp = localtime;
    prindd(__LINE__ . ": Fetching power outage data...") if $DEBUG;
    my $h = HTTP::Headers->new;
    $h->header('Accept-Encoding' => 'gzip,deflate,br', 'Host' => 'sqtb-api.azureedge.net');
    my $jsondata = getJSON($katkourl, $h);
    #df(__LINE__ . " fg: " . Dumper $jsondata) if $DEBUG;
    if ($jsondata ne '-1') {
        my $printstring = parse_sahkokatkot_data($searchword, $jsondata);
        msg_channel($printstring);
        $sahkokatkobuffer->{timestamp} = $timestamp;
        $sahkokatkobuffer->{data} = $jsondata;
    } elsif ($sahkokatkobuffer->{timestamp} > 0 && $sahkokatkobuffer->{timestamp} - $timestamp < 120) {
        my $printstring = parse_sahkokatkot_data($searchword, $sahkokatkobuffer->{data});
        msg_channel($printstring);
    } else {
        msg_channel("Sähkökatkotietoja ei saatu.");
    }
}


sub parse_sahkokatkot_data {
    my ($searchword, $jsondata, @rest) = @_;
    my $json_areas = $jsondata->{areas};
    my $json_companies = $jsondata->{companies};
    my $printstring = 'Näytetään 5 suurinta. Katkoja/kokonaisasiakasmäärä (suluissa päivän max). ';
    my %result_hash;

=pod
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
=cut
    foreach my $element (@$json_companies) {
        my $company = $element->{name};
        my $alias = $element->{alias};
        my $faults = $element->{fault} || 0;
        my $maxday = $element->{maxday} || 0;
        my $url = $element->{outagemap} || '';
        my $customers = $element->{customers} || 0;

        $result_hash{$company} =  {
            'alias' => $alias,
            'faults' => $faults,
            'maxday' => $maxday,
            'url' => $url,
            'customers' => $customers
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
        my $customers = $value->{customers};
        if ($searchword eq '' && $faults > 0) {
            prindd(__LINE__ . " area/city: " . $key) if $DEBUG;
            $printstring .= "\002$key:\002 $faults/$customers ($maxday) $url - ";
        }
        $index++;
        last if $index > 5; # max 5 items
    }

    prindd("printstring: $printstring") if $DEBUG;
    return $printstring;
}

sub parse_fingrid_sahko_data($$) {
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
            #prindd('liikennevalo: ' . $lv_temp);
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


sub pipe_input_fingrid($$$$) {
    my ($rh, $pipetage, $time1, $time2) = @{$_[0]};
    #df(__LINE__ . " fg: pipe input fingrid called... pipetage: " . Dumper(\$pipetage)) if $DEBUG;
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
    #df(__LINE__ . " fg: pipe_input_fingrid data received: " . Dumper(\$data)) if $DEBUG;
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
    #df(__LINE__ . " fg: pipe_input_katkot data received: " . Dumper(\$data)) if $DEBUG;
    return unless $data;
    msg_channel($data);
}

sub fetch_fingrid_api_data {
    my ($url, $firstTime, @rest) = @_;
    sleep(2) unless $firstTime;
    #df(__LINE__ . " fg: fingrid url: $url") if $DEBUG;
    my $h = HTTP::Headers->new;
    $h->header('x-api-key' => $apikey);
    return getJSON($url, $h);
}


sub msg_channel {
    my ($text, @rest) = @_;
    $text && $server_t->command("MSG $target_t $text");
}

sub prind {
    my ($text, @test) = @_;
    print("\0032" . $IRSSI{name} . ">\003 ". $text);
}

sub prindd {
	my ($text, @test) = @_;
    create_window('sahko');
	Irssi::active_win()->print("\0033" . $IRSSI{name} . ">\003 ". $text);
}

sub create_window {
    my ($window_name) = @_;
    my $window = Irssi::window_find_name($window_name);
    unless ($window) {
        #prindd("Create new window: $window_name");
        Irssi::command("window new hidden");
        Irssi::command("window name $window_name");
        Irssi::active_win()->print("Created new window: $window_name");
    }
    Irssi::command("window goto $window_name");
}

prind('Public commands:');
prind('!sähkö tai !sahko - Pörssisähkön hinta sekä sähkön tuotanto- ja kulutustietoja.');
prind('!sähkökatkot tai !sahkokatkot [hakusana] - Sähkökatkotiedot');

prind("$IRSSI{name} $VERSION loaded.");
Irssi::signal_add_last('message public', 'pub_msg');
