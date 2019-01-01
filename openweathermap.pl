use warnings;
use strict;
use Irssi;
use utf8;
use JSON;
use DateTime;
use POSIX;
use Time::Piece;

use Math::Trig; # for apparent temp

#use Switch 'Perl6';
#use open ':std', ':encoding(UTF-8)';
binmode(STDIN,  ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
#binmode STDOUT, ":encoding(utf8)";
#binmode STDIN, ":encoding(utf8)";
#binmode STDERR, ":encoding(utf8)";
#binmode FILE, ':utf8';
#use open ':std', ':encoding(utf8)';

use Data::Dumper;
#use Encode;

use KaaosRadioClass;				# LAama1 13.11.2016

use vars qw($VERSION %IRSSI);
$VERSION = '20181028';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'LAama1',
	name        => 'openweathermap',
	description => 'Fetches weather data from openweathermap.org',
	license     => 'Fublic Domain',
	url         => 'http://kaaosradio.fi',
	changed     => $VERSION
);

my $apikey = '4c8a7a171162e3a9cb1a2312bc8b7632';
my $url = 'https://api.openweathermap.org/data/2.5/weather?q=';
my $forecastUrl = 'https://api.openweathermap.org/data/2.5/forecast?q=';
my $areaUrl = 'https://api.openweathermap.org/data/2.5/find?cnt=5&lat=';
my $DEBUG = 1;
my $DEBUG1 = 0;
my $DEBUG_decode = 0;
my $myname = 'openweathermap.pl';
my $db = Irssi::get_irssi_dir(). '/scripts/openweathermap.db';
my $dbh;	# database handle

=pod
UTF8 emojis:
⛈️ Cloud With Lightning and Rain
☁️ Cloud
🌩️ Cloud With Lightning
🌧️ Cloud With Rain
🌨️ Cloud With Snow
❄️ Snow flake
🌪️ Tornado
🌫️ Fog
🌁 Foggy (city)
⚡ High Voltage

☔ Umbrella With Rain Drops
🌂 closed umbrella
🌈 rainbow
🌥️ Sun Behind Large Cloud
⛅ Sun Behind Cloud
🌦️ Sun Behind Rain Cloud
🌤️ Sun Behind Small Cloud

🌄 sunrise over mountains
🌅 sunrise
🌇 sunset over buildings
🌞 Sun With Face
☀️ Sun
🌆 cityscape at dusk
🌉 bridge at night
🌃 night with stars

🌊 water wave
🌀 cyclone
🌬️ wind
💨 dashing away
🍂 fallen leaf
🌋 volcano
🌏 earth globe asia australia
🌟 glowing star
🌠 shooting star
🎆 fireworks

🌌 milky way
🌛 first quarter moon face
🌝 full moon face
🌜 last quarter moon face
🌚 new moon face
🌙 crescent moon
🌑 new moon
🌓 first quarter moon
🌖 Waning gibbous moon
🌒 waxing crescent moon
🌔 waxing gibbous moon

🦄 Unicorn Face
=cut


unless (-e $db) {
	unless(open FILE, '>:utf8',$db) {
		Irssi::print("$myname: Unable to create or write file: $db");
		die;
	}
	close FILE;
	if (CREATEDB() == 0) {
		Irssi::print("$myname: Database file created.");
	}
}

# Data type
sub replace_scandic_letters {
	my ($row, @rest) = @_;
	dd("replace_scandic_letters row: $row");

	#if ($row) {
	$row =~ s/ä/ae/g;
	$row =~ s/Ä/ae/g;
	$row =~ s/ö/oe/g;
	$row =~ s/Ö/oe/g;
	$row =~ s/Ã¤/ae/g;
	$row =~ s/Ã¶/oe/g;
	#$row =~ s/\s+/ /gi;
	#$row =~ s/\’//g;
	#}
	dd("replace_scandic_letters row after: $row");
	return $row;
}

sub replace_with_emoji {
	my ($string, @rest) = @_;
	$string =~ s/fog|mist/🌫️ /ui;
	$string =~ s/wind/💨 /ui;
	$string =~ s/snow/❄️ /ui;
	if (is_sun_up()) {
		$string =~ s/overcast clouds/🌥️ /ui;
		$string =~ s/clear sky/☀️ /ui;
	}
	return $string;
}

sub is_sun_up {
	my ($sunrise, $sunset, $tz, @rest) = @_;
	my $comparetime = localtime;
	if ($comparetime > $sunset || $comparetime < $sunrise) {
		dp('SUN ... IS ... DOWN!!');
		return 0;
	}
	return 1;
}

sub get_sun_moon {
	my ($sunrise, $sunset, $tz, @rest) = @_;
	if (is_sun_up($sunrise, $sunset)) {
		return '🌞';
	}
	return conway();
}

sub conway {
	# John Conway method
	#my ($y,$m,$d);
	chomp(my $y = `date +%Y`);
	chomp(my $m = `date +%m`);
	chomp(my $d = `date +%d`);

	my $r = $y % 100;
	$r %= 19;
	if ($r > 9) { $r-= 19; }
	$r = (($r * 11) % 30) + $m + $d;
	if ($m < 3) { $r += 2; }
	$r -= 8.3;              # year > 2000

	$r = ($r + 0.5) % 30;	#test321
	my $age = $r;
	$r = 7/30 * $r + 1;

=pod
      0: 'New Moon'        🌑
      1: 'Waxing Crescent' 🌒
      2: 'First Quarter',  🌓
      3: 'Waxing Gibbous', 🌔
      4: 'Full Moon',      🌕
      5: 'Waning Gibbous', 🌖
      6: 'Last Quarter',   🌗
      7: 'Waning Crescent' 🌘
=cut

	my @moonarray = ('🌑', '🌒', '🌓', '🌔', '🌕', '🌖', '🌗', '🌘');
	return $moonarray[$r];
}

sub CREATEDB {
	$dbh = KaaosRadioClass::connectSqlite($db);
    #my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", { RaiseError => 1 },) or die DBI::errstr;

	my $stmt = qq/CREATE TABLE IF NOT EXISTS CITIES (ID int, NAME TEXT, COUNTRY text, PVM INT, LAT TEXT, LON TEXT, PRIMARY KEY(ID, NAME))/;
	
	my $rv = KaaosRadioClass::writeToOpenDB($dbh, $stmt);
	if($rv != 0) {
   		Irssi::print ("$myname: DBI Error $rv");
		return -1;
	} else {
   		Irssi::print("$myname: Table CITIES created successfully");
	}

	my $stmt2 = qq/CREATE TABLE IF NOT EXISTS DATA (CITY TEXT primary key, PVM INT, COUNTRY TEXT, CITYID int, SUNRISE int, SUNSET int, DESCRIPTION text, WINDSPEED text, WINDDIR text,
	TEMPMAX text, TEMP text, HUMIDITY text, PRESSURE text, TEMPMIN text, LAT text, LON text)/;
	my $rv2 = KaaosRadioClass::writeToOpenDB($dbh, $stmt2);
	if($rv2 < 0) {
   		Irssi::print ("$myname: DBI Error: $rv2");
		return -2;
	} else {
   		Irssi::print("$myname: Table DATA created successfully");
	}

	$dbh = KaaosRadioClass::closeDB($dbh);
	return 0;
}

# param: searchword, returns json answer or 0
sub findWeather {
	my ($searchword, @rest) = @_;
	#my $searchtime = time() - (2*60*60);
	dp("findWeather: $searchword") if $DEBUG;
	my $returnstring;

	my $data = KaaosRadioClass::fetchUrl($url.$searchword."&units=metric&appid=".$apikey, 0);
	da("DATA:",$data);
	if ($data < 0) {
		my ($lat, $lon, $name) = GETCITYCOORDS($searchword);
		$data = KaaosRadioClass::fetchUrl($url.$name."&units=metric&appid=".$apikey, 0);
		if ($data < 0) {
			dp('data = '.$data);
			return 0;
		}
	}
	
	my $json = decode_json($data);
	da('JSON:',$json);
	da('JSON-temp: '. $json->{main}->{temp});
	$dbh = KaaosRadioClass::connectSqlite($db);
	SAVECITY($json);
	SAVEDATA($json);
	$dbh = KaaosRadioClass::closeDB($dbh);
	return $json;
}

sub findWeatherForecast {
	my ($searchword, @rest) = @_;
	my $returnstring = 'klo ';

	my $data = KaaosRadioClass::fetchUrl($forecastUrl.$searchword.'&units=metric&appid='.$apikey, 0);
	
	#da("DATA: ",$data);
	if ($data < 0) {
		dp('data = '.$data);
		return 0;
	}
	my $dt = DateTime->new(
		year => 2018,
		month => 9,
		day => 1,
		hour => 12,
		minute => 0,
		second => 0,
		time_zone => 'Europe/London',
	);
	my $tz = $dt->time_zone();
	Irssi::print('timezone: '.$tz);
	Irssi::print('DT: ' .$dt);
	Irssi::print('YMD: '. $dt->ymd);
	my $json = decode_json($data);
	#da('JSON-list:',$json->{list});
	my $index = 0;

	foreach my $item (@{$json->{list}}) {
		if ($index > 8) {
			last;
		}
		Irssi::print('');
		Irssi::print('Timestamp: ' .$item->{dt});
		Irssi::print('Localtime: '.localtime($item->{dt}));
		Irssi::print('Temp: '.$item->{main}->{temp});
		my ($sec, $min, $hour, $mday) = localtime($item->{dt});
		$returnstring .= sprintf ('%.2d', $hour) .': '.$item->{main}->{temp} . '°C, ';
		#$returnstring .= $hour.': '.$item->{main}->{temp} . '°C, ';
		$index++;
	}
	
	dp("findWeatherForecast returnsring: $returnstring");
	return $returnstring;
}

sub FINDAREAWEATHER {
	my ($city, @rest) = @_;
	my ($lat, $lon, $name) = GETCITYCOORDS($city);
	return 'City not found.' unless ($lat && $lon);
	my $newSearchUrl = $areaUrl.$lat."&lon=$lon&units=metric&appid=".$apikey;
	my $data = KaaosRadioClass::fetchUrl($newSearchUrl, 0);
	da('URL', $newSearchUrl,'DATA',$data);
	if ($data < 0) {
		dp('data = '.$data);
		return 0;
	}
	my $json = decode_json($data);
	my $sayline;
	foreach my $city (@{$json->{list}}) {
		$sayline .= getSayLine2($city) . '. ';
	}
	da('JSON:',$json);
	da('SAYLINE', $sayline);
	return $sayline;
}

sub GETCITYCOORDS {
	my ($city, @rest) = @_;
	my $sql = "SELECT LAT,LON,NAME from CITIES where NAME Like '%".$city."%'";
	my @results = KaaosRadioClass::readLineFromDataBase($db,$sql);

	dp('GETCITYCOORDS SQL: '. $sql);
	dp('GETCITYCOORDS Result: ');
	da(@results);
	return $results[0], $results[1], $results[2];
}

# save new city to database
sub SAVECITY {
	my ($json, @rest) = @_;
	my $now = time;
	my $sql = "INSERT OR IGNORE INTO CITIES (ID, NAME, COUNTRY, PVM, LAT, LON) VALUES ($json->{id}, '$json->{name}', '$json->{sys}->{country}', $now, '$json->{coord}->{lat}', '$json->{coord}->{lon}')";
	dp('save City stmt: '.$sql);
	return KaaosRadioClass::writeToOpenDB($dbh, $sql);
}

sub SAVEDATA {
	my ($json, @rest) = @_;
	my $now = time;
	my $name = $json->{name};
	my $country = $json->{sys}->{country} || '';
	my $id = $json->{id} || -1;
	my $sunrise = $json->{sys}->{sunrise} || 0;
	my $sunset = $json->{sys}->{sunset} || 0;
	my $weatherdesc = $json->{weather}[0]->{description} || '';
	my $windspeed = $json->{wind}->{speed} || 0;
	my $winddir = $json->{wind}->{deg} || 0;
	my $tempmax = $json->{main}->{temp_max} || 0;
	my $humidity = $json->{main}->{humidity} || 0;
	my $pressure = $json->{main}->{pressure} || 0;
	my $tempmin = $json->{main}->{temp_min} || 0;
	my $temp = $json->{main}->{temp} || 0;
	my $lat = $json->{coord}->{lat} || 0;
	my $long = $json->{coord}->{lon} || 0;
									#1	#2		#2		#4		#5		#6		#7			#8			#9		#10			#11	#12			#13		#14		#15		#16	
	my $stmt = "INSERT INTO DATA (CITY, PVM, COUNTRY, CITYID, SUNRISE, SUNSET, DESCRIPTION, WINDSPEED, WINDDIR, TEMPMAX, TEMP, HUMIDITY, PRESSURE, TEMPMIN, LAT, LON)
	 VALUES ('$name', $now, '$country', $id, $sunrise, $sunset, '$weatherdesc', '$windspeed', '$winddir', '$tempmax', '$temp', '$humidity', '$pressure', '$tempmin', '$lat', '$long')";
	dp('save Data stmt: '.$stmt);
	return KaaosRadioClass::writeToOpenDB($dbh, $stmt);
}

# debug print
sub dp {
	my ($string, @rest) = @_;
	if ($DEBUG == 1) {
		print("\n$myname debug: ".$string);
	}
}

# debug print array
sub da {
	Irssi::print("$myname debugarray: ");
	Irssi::print(Dumper(@_)) if ($DEBUG == 1 || $DEBUG_decode == 1);
}

# format the message
sub getSayLine2 {
	my ($json, @rest) = @_;
	if ($json == 0) {
		dp('json = 0');
		return 0;
	}
	my $returnvalue = $json->{name}.': '.$json->{main}->{temp}.'°C, '.replace_with_emoji($json->{weather}[0]->{description});
	return $returnvalue;
}

# format the message
sub getSayLine {
	my ($json, @rest) = @_;
	if ($json == 0) {
		dp('json = 0');
		return 0;
	}
	my $tempmin = $json->{main}->{temp_min};
	my $tempmax = $json->{main}->{temp_max};
	my $temp;
	if ($tempmin != $tempmax) {
		$temp = "($tempmin..$tempmax) °C"
	} else {
		$temp = $json->{main}->{temp}.'°C';
	}
	my $apptemp = getApparentTemperature($json->{main}->{temp}, $json->{main}->{humidity}, $json->{wind}->{speed}, $json->{clouds}->{all}, $json->{coord}->{lat}, $json->{dt});
	dp($apptemp);
	my $sky = get_sun_moon($json->{sys}->{sunrise}, $json->{sys}->{sunset});
	my $sunrise = '🌄 '.localtime($json->{sys}->{sunrise})->strftime('%H:%M');
	my $sunset = '🌆 ' .localtime($json->{sys}->{sunset})->strftime('%H:%M');
	my $wind = '💨 '. $json->{wind}->{speed}. ' m/s';
	my $city = $json->{name};
	if ($city eq 'Kokkola') {
		$city = '🦄 Kokkola';
	}
	my $weatherdesc = '';
	my $index = 0;
	foreach my $item (@{$json->{weather}}) {
		if ($index > 1) {
			$weatherdesc .= ' ---, ';
		}
		$weatherdesc .= $item->{description};
		$index++;
	}
	dp('weatherdesc: '.$weatherdesc);
	
	my $returnvalue = $city.', '.$json->{sys}->{country}.': '.$temp.', '.replace_with_emoji($json->{weather}[0]->{description}).'. '.$sunrise.', '.$sunset.', '.$wind. ' --> '.$sky;
	#my $returnvalue = $city.', '.$json->{sys}->{country}.': '.$temp.', '.replace_with_emoji($weatherdesc).'. '.$sunrise.', '.$sunset.', '.$wind. ' --> '.$sky;
	return $returnvalue;
}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	return if ($nick eq $server->{nick});   # self-test
	
	# Check we have an enabled channel
	my $enabled_raw = Irssi::settings_get_str('openweathermap_enabled_channels');
	my @enabled = split(/ /, $enabled_raw);
	return unless grep(/$target/, @enabled);
	my $sayline = filter($msg);
	$server->command("msg -channel $target $sayline") if $sayline;
	return;
	
	
	if ($msg =~ /\!(sää |saa |s )(.*)$/i) {
		dp("Hopsan $1 $2");
		return if KaaosRadioClass::floodCheck() > 0;
		#my $searchWord = $1;
		my $city = $2;
		my $sayline = getSayLine(findWeather($city));
		dp("sig_msg_pub: found some results from '$city' on channel '$target'. '$sayline'") if $sayline;
		$server->command("msg -channel $target $sayline") if $sayline;
		return;
	} elsif ($msg =~ /\!(se )(.*)$/i) {
		dp("moksan $1");
		return if KaaosRadioClass::floodCheck() > 0;
		my $city = $2;
		my $sayline = findWeatherForecast($city);
		$server->command("msg -channel $target $sayline") if $sayline;
		return;
	} elsif ($msg =~ /\!(sa )(.*)$/i) {
		dp('area waeather');
		return if KaaosRadioClass::floodCheck() > 0;
		my $city = $2;
		my $sayline = FINDAREAWEATHER($city);
		$server->command("msg -channel $target $sayline") if $sayline;
		return;
	}
}

sub filter {
	my ($msg, @rest) = @_;
	my $returnstring = '';
	if ($msg =~ /\!(sää |saa |s )(.*)$/i) {
		return if KaaosRadioClass::floodCheck() > 0;
		my $city = $2;
		$returnstring = getSayLine(findWeather($city));
	} elsif ($msg =~ /\!(se )(.*)$/i) {
		return if KaaosRadioClass::floodCheck() > 0;
		my $city = $2;
		$returnstring = findWeatherForecast($city);
	} elsif ($msg =~ /\!(sa )(.*)$/i) {
		return if KaaosRadioClass::floodCheck() > 0;
		my $city = $2;
		$returnstring = FINDAREAWEATHER($city);
	}
	return $returnstring;
}

use constant SOLAR_CONSTANT => 1395; # solar constant (w/m2)
use constant TRANSMISSIONCOEFFICIENTCLEARDAY => 0.81;
use constant TRANSMISSIONCOEFFICIENTCLOUDY => 0.62;
# from your local weather android app
# params:
# $dryBulbTemperature = degrees in celsius ?
# $humidity = percent
# $windSpeed = m/s ?
# cloudiness = percent
# $latitude = degrees?
# $timestamp = unixtime ?
sub getApparentTemperature {
	my ($dryBulbTemperature, $humidity ,$windSpeed, $cloudiness, $latitude, $timestamp, @rest) = @_;
	da(@_);
	my $e = ($humidity / 100.0) * 6.105 * exp (17.27*$dryBulbTemperature / (237.7 + $dryBulbTemperature));
	my $cosOfZenithAngle = getCosOfZenithAngle(deg2rad($latitude), $timestamp);
	dp('cosOfZenithAngle: '.$cosOfZenithAngle);
	my $secOfZenithAngle = 1/ $cosOfZenithAngle;
	my $transmissionCoefficient = TRANSMISSIONCOEFFICIENTCLEARDAY - (TRANSMISSIONCOEFFICIENTCLEARDAY - TRANSMISSIONCOEFFICIENTCLOUDY) * ($cloudiness/100.0);
	my $calculatedIrradiation = 0;
	if ($cosOfZenithAngle > 0) {
            $calculatedIrradiation = (SOLAR_CONSTANT * $cosOfZenithAngle * $transmissionCoefficient ** $secOfZenithAngle)/10;
    }
	my $apparentTemperature = $dryBulbTemperature + (0.348 * $e) - (0.70 * $windSpeed) + ((0.70 * $calculatedIrradiation)/($windSpeed + 10)) - 4.25;
	return printf("%.1f", $apparentTemperature);
}

sub getCosOfZenithAngle {
	my ($latitude, $timestamp, @rest) = @_;
	# TODO: create perl time element
	my $declination = deg2rad(-23.44 * cos(deg2rad((360.0/365.0) * (9 + getDayOfYear($timestamp)))));
	my $hourAngle = ((12 * 60) - getMinuteOfDay($timestamp)) * 0.25;
	return sin $latitude * sin $declination + (cos $latitude * cos $declination * cos deg2rad($hourAngle));

}

# TODO: Timezone
sub getDayOfYear {
	my ($timestamp, $tz, @rest) = @_;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime $timestamp;
	return $yday +1;
}
sub getMinuteOfDay {
	my ($timestamp, $tz, @rest) = @_;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime $timestamp;
	return $hour*60 + $min;
}

sub sig_msg_priv {
	my ($server, $msg, $nick, $address) = @_;
	return if ($nick eq $server->{nick});		# self-test
	my $sayline = filter($msg);
	$server->command("msg $nick $sayline") if $sayline;
}

sub sig_msg_pub_own {
	my ($server, $msg, $target) = @_;
	dp('own public');
	sig_msg_pub($server, $msg, $server->{nick}, "", $target);
}

Irssi::settings_add_str('openweathermap', 'openweathermap_enabled_channels', '');

#Irssi::settings_add_str('openweathermap', 'openweathermap_shortmode_channels', '');

Irssi::signal_add('message public', 'sig_msg_pub');
Irssi::signal_add('message private', 'sig_msg_priv');
#Irssi::signal_add('message own_public', 'sig_msg_pub_own');
Irssi::print("$myname v. $VERSION loaded.");
Irssi::print("\nNew commands:");
Irssi::print('/set openweathermap_enabled_channels #1 #2');
#Irssi::print('/set openweathermap_shortmode_channels #1 #2');
