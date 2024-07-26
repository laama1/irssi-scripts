use warnings;
use strict;
use Irssi;
use utf8;							# allow utf8 in regex
use Encode;
use JSON;
use DateTime;
use POSIX;
#use Time::Piece;
use feature 'unicode_strings';

use Number::Format qw(:subs :vars);
my $fi = new Number::Format(-decimal_point => ',');

use Math::Trig;						# for apparent temp
use Data::Dumper;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;				# LAama1 13.11.2016

use vars qw($VERSION %IRSSI);
$VERSION = '20240216';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'LAama1@ircnet',
	name        => 'openweathermap',
	description => 'Fetches weather data from openweathermap.org',
	license     => 'Fublic Domain',
	url         => 'https://kaaosradio.fi',
	changed     => $VERSION,
);

my @ignorenicks = (
	'kaaosradio',
	'ryokas',
	'KD_Butt',
	'KD_Bat',
	'micdrop'
);

my $apikeyfile = Irssi::get_irssi_dir(). '/scripts/openweathermap_apikey';
my $apikey = '&units=metric&appid=';
$apikey .= KaaosRadioClass::readLastLineFromFilename($apikeyfile);
#my $url = 'https://api.openweathermap.org/data/2.5/weather?q=';
my $url = 'https://api.openweathermap.org/data/2.5/weather?';
my $forecastUrl = 'https://api.openweathermap.org/data/2.5/forecast?';
my $areaUrl = 'https://api.openweathermap.org/data/2.5/find?cnt=5&lat=';
my $uvUrl = 'https://api.openweathermap.org/data/2.5/uvi?&lat=';
my $uvforecastUrl = 'https://api.openweathermap.org/data/2.5/uvi/forecast?';
my $DEBUG = 0;
my $DEBUG1 = 0;
my $db = Irssi::get_irssi_dir(). '/scripts/openweathermap.db';
my $dbh;	# database handle

my $users = {};

my $helptext = 'Openweathermap sääskripti. Ohje: https://bot.8-b.fi/#s';

=pod
some weather related UTF8 emojis:
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
😎 Smiling face with sunglasses
🌆 cityscape at dusk
🌉 bridge at night
🌃 night with stars

🌊 water wave
🌀 cyclone
🌬️ Wind Face
💨 dashing away
🍂 fallen leaf
🌋 volcano
🌏 earth globe asia australia
🌟 glowing star
🌠 shooting star
🎆 fireworks
💧 droplet

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
🎠 carousel horse
https://emojipedia.org/moon-viewing-ceremony/
🌶  Hot Pepper
=cut


unless (-e $db) {
	unless(open FILE, '>:utf8',$db) {
		prindw("Unable to create or write DB file: $db");
		die;
	}
	close FILE;
	if (CREATEDB() == 0) {
		prind("Database file created.");
	}
}

sub replace_with_emoji {
	my ($string, $sunrise, $sunset, $comparetime, $tz, @rest) = @_;
	#dp(__LINE__.": string: $string, sunrise: $sunrise, sunset: $sunset, comparetime: $comparetime, timezone: $tz");
	$sunrise += $tz;
	$sunset += $tz;
	$comparetime += $tz;
	my $sunmoon = get_sun_moon($sunrise, $sunset, $comparetime);
	$string =~ s/fog|mist/🌫️ /ui;
	$string =~ s/wind/💨 /ui;
	$string =~ s/light snow/❄️ /ui;
	$string =~ s/snow/🌨️ /ui;
	$string =~ s/clear sky/$sunmoon /u;
	$string =~ s/Sky is Clear/$sunmoon /u;
	$string =~ s/Clear/$sunmoon /u;			# short desc
	$string =~ s/Clouds/☁️ /u;				# short desc
	$string =~ s/Rain/🌧️ /u;				# short desc
	$string =~ s/thunderstorm with rain/⛈️ /u;
	$string =~ s/thunderstorm/⚡ /u;
	$string =~ s/light rain/☔ /u;
	$string =~ s/light intensity rain/🌂 /u;
	$string =~ s/heavy intensity shower rain/🌊 🌧️ /u;
	$string =~ s/scattered clouds/☁ /u;
	$string =~ s/shower rain/🌧️ /su;
	my $sunup = is_sun_up($sunrise, $sunset, $comparetime);
	if ($sunup == 1) {
		$string =~ s/overcast clouds/🌥️ /sui;
		$string =~ s/broken clouds/⛅ /sui;
		$string =~ s/few clouds/🌤️ /sui;
		$string =~ s/light intensity shower rain/🌦️ /su;
		#$string =~ s/shower rain/🌧️ /su;
	} elsif ($sunup == 0) {
		#$string =~ s/shower rain/🌧️ /su;
		$string =~ s/broken clouds/☁ /su;
		$string =~ s/overcast clouds/☁ /sui;
	}
	return $string;
}

# params: sunrise, sunset, time to compare. all are unixtime
sub is_sun_up {
	my ($sunrise, $sunset, $comparetime, @rest) = @_;
	# Necessary, when sunset is today, and we dont know about the real sunset for given day. 
	# Becaues the API does not return sunset for forecast measurements.
	$sunrise = $sunrise % 86400;
	$sunset = $sunset % 86400;
	$comparetime = $comparetime % 86400;
	print ("Sunrise: " . DateTime->from_epoch(epoch => $sunrise)->hms(':') . ', Compare to: ' . DateTime->from_epoch(epoch => $comparetime)->hms(':') . ', sunset: ' . DateTime->from_epoch(epoch => $sunset)->hms(':')) if $DEBUG1;
	if ($comparetime > $sunset || $comparetime < $sunrise) {
		print ("Sun is down :(") if $DEBUG1;
		return 0;
	}
	print("Sun is up :)") if $DEBUG1;
	return 1;
}

sub get_sun_moon {
	my ($sunrise, $sunset, $comparetime, @rest) = @_;
	if (is_sun_up($sunrise, $sunset, $comparetime) == 1) {
		return '🌞';
	}
	return omaconway();
}

sub omaconway {
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
	$r -= 8.3;              # year > 2000, if $r < 8.3, -> new moon

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

# param: searchword, returns json answer for current weather or undef if not found
sub FINDWEATHER {
	my ($searchword, @rest) = @_;
	my $newurl;
	my $urltail = $searchword;
	if ($searchword =~ /(\d{5})/) {
		$newurl = $url.'zip=';
		$urltail = $1.',fi';		# Search post numbers from finland only
	} else {
		$newurl = $url.'q=';
	}
	my $json = request_api($newurl.$urltail);
	da(__LINE__.' json', $json);
	my ($lat, $lon, $name) = GETCITYCOORDS($searchword);

	if ($json eq '-1') {
		# searchword not found from API
		dp(__LINE__.' city not found from API, searchword: '.$searchword) if $DEBUG1;
		#return undef unless defined $name;
		$urltail = $name;
		$json = request_api($newurl.$urltail) if $urltail;
		if ($json eq '-1') {
			#return "Paikkaa ei löydy!";
			dp(__LINE__.' city not available, name: '.$name) if $DEBUG1;
		}
		return undef if (!defined $json || $json eq '-1');
	}

	$json->{uvindex} = 0;
	if ($lat && $lon) {
		$json->{uvindex} = FINDUVINDEX($lat, $lon);
	}

	SAVECITY($json);
	SAVEDATA($json);
	return $json;
}

sub FINDFORECAST {
	my ($searchword, $days, @rest) = @_;
	my $json;
	
	if ($searchword =~ /(\d{5})/) {
		my $urltail = 'zip='.$1.',fi';		# Search postcode numbers only from finland
		$json = request_api($forecastUrl.$urltail);
	} else {
		$json = request_api($forecastUrl.'q='.$searchword);
	}
	if ($json eq '-1') {
		$dbh = KaaosRadioClass::connectSqlite($db);
		my ($lat, $lon, $name) = GETCITYCOORDS($searchword);
		$dbh = KaaosRadioClass::closeDB($dbh);
		$json = request_api($forecastUrl.'q='.$name) if defined $name;
		return 0 if ($json eq '-1');
	}
	
	if (defined $days && $days == 5) {
		return forecastloop5($json);
	} else {
		return forecastloop1($json);
	}
}

# print temperature for every 3 hours for the first 24h
sub forecastloop1 {
	my ($json, @rest) = @_;
	my $index = 0;
	my $returnstring = '';
	foreach my $item (@{$json->{list}}) {
		if ($index >= 7) {
			# max 8 items: 8x 3h = 24h
			last;
		}
		if ($index == 0) {
			my $use_this_city = $json->{city}->{name};
			my $timezone = ($json->{city}->{timezone} / 3600);
			if ($timezone > 0) {$timezone = '+'.$timezone};
			$timezone = '(UTC' . $timezone . ')';
			#print ("Timezone: " . $timezone) if $DEBUG;
			$returnstring = $use_this_city . ','.$json->{city}->{country} . " $timezone \002klo:\002 " . $returnstring;
		}
		#print __LINE__ if $DEBUG1;
		my $weathericon = replace_with_emoji($item->{weather}[0]->{main},
												$json->{city}->{sunrise},
												$json->{city}->{sunset},
												$item->{dt},
												$json->{city}->{timezone}
											);
		my $temptimedt = DateTime->from_epoch(epoch => ($item->{dt} + $json->{city}->{timezone}));
		$returnstring .= "\002".sprintf('%.2d', $temptimedt->hour) .":\002 $weathericon ".$fi->format_number($item->{main}->{temp}, 0) .'°C, ';
		$index++;
	}
	return $returnstring;
}

# print temperature for every 12 h in the next 5d
sub forecastloop5 {
	my ($json, @rest) = @_;
	my $index = 0;
	my $returnstring = '';
	my $daytemp = '';
	my @weekdayarray = ('su','ma', 'ti','ke','to','pe','la','su');
	foreach my $item (@{$json->{list}}) {
		my $tiem = $item->{dt_txt};
		#my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime $item->{dt};
		my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = gmtime ($item->{dt} + $item->{timezone});
		my $weekdaystring = $weekdayarray[$wday];
		if ($tiem =~ /00:00:00/ || $tiem =~ /12:00:00/) {	# TODO: per timezone not UTC
			if ($index == 0) {
				$returnstring = $json->{city}->{name} . ','.$json->{city}->{country} . ' ';
			}
			print __LINE__ if $DEBUG;
			my $weathericon = replace_with_emoji($item->{weather}[0]->{main}, $json->{city}->{sunrise},	$json->{city}->{sunset}, $item->{dt}, $json->{timezone});
			if ($wday eq $daytemp) {
				$returnstring .= "\002".sprintf('%.2d', $hour) .":\002 $weathericon ".$fi->format_number($item->{main}->{temp}, 0) . "°C";
			} else {
				#$returnstring .= "\002".$mday.'.'.($mon+1).'. ('.sprintf('%.2d', $hour) .":\002 $weathericon ".$fi->format_number($item->{main}->{temp}, 0) .'°C, ';
				$returnstring .= "\002".$weekdaystring.': ('.sprintf('%.2d', $hour) .":\002 $weathericon ".$fi->format_number($item->{main}->{temp}, 0) .'°C, ';
			}
			if ($tiem =~ /12:00:00/) {
				# end of temperature pair
				#print("Time: " . $tiem);
				$returnstring .= "\002)\002, ";
				#print("returnstring: " . $returnstring);
			}
			$daytemp = $wday;
			$index++;
		}
	}

	$returnstring .= "\002)\002";
	return $returnstring;
}

sub FINDAREAWEATHER {
	my ($city, @rest) = @_;
	my ($lat, $lon, $name) = GETCITYCOORDS($city);   # 1) find existing city from DB by search word
	dp('name found?: '.$name);
	my $rubdata = FINDWEATHER($city);                # 2) find one weather from API for sunrise & sunset times
	if (!defined $lat && !defined $lon && !defined $name && defined $rubdata->{coord}) {
													# 3) if city was not found from DB
		$lat = $rubdata->{coord}->{lat};
		$lon = $rubdata->{coord}->{lon};
		$name = $rubdata->{name};
	}
	#($lat, $lon, $name) = GETCITYCOORDS($city) unless ($lat && $lon && $name);      # 3) find existing city again from DB
	return 'City not found from DB or API.' unless ($lat && $lon && $name);

	my $searchurl = $areaUrl.$lat."&lon=$lon";
	my $json = request_api($searchurl);

	return 0 if ($json eq '-1');

	my $sayline;
	foreach my $city (@{$json->{list}}) {
		# TODO: get city coords from API and save to DB
		$sayline .= getSayLine2($city, $rubdata->{sys}->{sunrise}, $rubdata->{sys}->{sunset}) . '. ';
	}
	return $sayline;
}

sub FINDUVINDEX {
	#return ''; # poissa käytöstä toistaiseksi koska tällä ei ole juuri merkitystä. ei perustu paikallisiin havaintoihin.
	my ($lat, $lon, @rest) = @_;

	my $searchurl = $uvUrl.$lat."&lon=$lon";
	my $json = request_api($searchurl);

	if ($json eq '-1') {
		return '';
	}
	return $json->{value}
}

sub make_weather_desc {
	my (@weather)  = @_;
	my $weatherdesc = '';
	my $index = 1;
	foreach my $item (@weather) {
		if ($index > 1) {
			$weatherdesc .= ', ';
		}
		$weatherdesc .= $item->{description};
		$index++;
	}
	return $weatherdesc;
}

# for the command !sa, area weather
sub getSayLine2 {
	my ($json, $sunrise, $sunset, @rest) = @_;
	return unless $json;
	my $weatherdesc = make_weather_desc(@{$json->{weather}});
	#my $index = 1;
	#foreach my $item (@{$json->{weather}}) {
	#	if ($index > 1) {
	#		$weatherdesc .= ', ';
	#	}
	#	$weatherdesc .= $item->{description};
	#	$index++;
	#}
	my $newcity = changeCity($json->{name});
	print __LINE__ . 'weatherdesc: ' . $weatherdesc if $DEBUG;
	my $returnvalue = $newcity.': '.$fi->format_number($json->{main}->{temp}, 1).'°C, '.replace_with_emoji($weatherdesc, $sunrise, $sunset, time, $json->{timezone});
	return $returnvalue;
}

# change city name to funy one
sub changeCity {
	my ($city, @rest) = @_;
	if ($city eq 'Kokkola') {
		$city = '🦄 Kokkola';
	} elsif ($city eq 'Ylöjärvi' || $city eq 'Ylojarvi') {
		$city = '🌶  Ylöjärvi';
	} elsif ($city eq 'Jyvaskyla' || $city eq 'Jyväskylä') {
		#$city = '🚲 Jyväskylä';
		$city = '🚴 Jyväskylä';
	} elsif ($city eq 'Turku') {
		$city = '⛵ Turku';
	} elsif ($city eq 'Hatanpää' || $city eq 'Hatanpaa') {
		#$city = '🍻 Hatanpää';
		$city = '🍺 Hatanpää';
	} elsif ($city eq 'Fathiye' || $city eq 'Fathie') {
		$city = 'Fathiye';
	}
	return $city;
}

# format the message
sub getSayLine {
	my ($json, @rest) = @_;
	return undef unless defined $json;
	if ($json eq '0' || $json eq '-1') {
		return undef;
	}
	my $tempmin = $fi->format_number($json->{main}->{temp_min}, 1);
	my $tempmax = $fi->format_number($json->{main}->{temp_max}, 1);
	my $pressure = $json->{main}->{pressure} . 'hPa';
	my $humidity = $json->{main}->{humidity} . '%';
	my $temp;
	if ($tempmin ne $tempmax) {
		$temp = "($tempmin…$tempmax)°C"
	} else {
		$temp = $fi->format_number($json->{main}->{temp}, 1).'°C';
	}
	#my $havaintotime = gmtime($json->{dt})->strftime('%H:%M');
	my $apparent_temp = get_apparent_temp($json->{main}->{temp}, $json->{main}->{humidity}, $json->{wind}->{speed}, $json->{clouds}->{all}, $json->{coord}->{lat}, $json->{dt});
	my $sky = '';

	if ($apparent_temp) {
		$apparent_temp = ' (~ '.$fi->format_number($apparent_temp, 1).'°C)';
	} else {
		$apparent_temp = '';
	}

	my $sunrisedt = DateTime->from_epoch( epoch => ($json->{sys}->{sunrise} + $json->{timezone}));
	my $sunsetdt = DateTime->from_epoch( epoch => ($json->{sys}->{sunset} + $json->{timezone}));

	my $sunrise = '🌇 '.$sunrisedt->hour .':'.sprintf('%.2d', $sunrisedt->minute);

	#my $sunset = '-> ' .localtime($json->{sys}->{sunset})->strftime('%H:%M');
	my $sunset = '-> ' .$sunsetdt->hour . ':'.sprintf('%.2d', $sunsetdt->minute);
	my $wind_speed = $fi->format_number($json->{wind}->{speed}, 1);
	my $wind_gust = '';
	$wind_gust .= $fi->format_number($json->{wind}->{gust}, 1) if (defined $json->{wind}->{gust});

	my $wind = '💨 '.$wind_speed;
	if (defined $wind_gust && $wind_gust ne '') {
		$wind .= " ($wind_gust)";
	}
	$wind .= ' m/s';
	my $city = changeCity($json->{name});
	my $timezone = ($json->{timezone} / 3600);
	if ($timezone > 0) {
		$timezone = '+'.$timezone; 
	}
	$city .= ','.$json->{sys}->{country};
	$city .= " (UTC$timezone)";

	my $weatherdesc = make_weather_desc(@{$json->{weather}});;
	
	my $uv_index = '';
	if (defined $json->{uvindex} && $json->{uvindex} && $json->{uvindex} > 1) {
		$uv_index = ', UVI: '.$json->{uvindex};
	}
	print __LINE__ . ' city: ' . $city if $DEBUG1;
	my $newdesc = replace_with_emoji($weatherdesc, $json->{sys}->{sunrise}, $json->{sys}->{sunset}, $json->{dt}, $json->{timezone});
	my $returnvalue = $city.': '.$newdesc.' '.$temp.$apparent_temp.', '.$sunrise.' '.$sunset.', '.$wind.$sky.$uv_index.', '. $pressure . ', ' . $humidity;
	return $returnvalue;
}

use constant SOLAR_CONSTANT => 1395; # solar constant (w/m2)
use constant TRANSMISSIONCOEFFICIENTCLEARDAY => 0.81;
use constant TRANSMISSIONCOEFFICIENTCLOUDY => 0.62;
# copied from android app: your local weather
# TODO: mention license GPL?
# params:
# $dryBulbTemperature = degrees in celsius ?
# $humidity = percent
# $windSpeed = m/s
# $cloudiness = percent
# $latitude = degrees?
# $timestamp = unixtime
sub get_apparent_temp {
	my ($dryBulbTemperature, $humidity, $windSpeed, $cloudiness, $latitude, $timestamp, @rest) = @_;

	my $e = ($humidity / 100.0) * 6.105 * exp (17.27*$dryBulbTemperature / (237.7 + $dryBulbTemperature));
	my $cosOfZenithAngle = get_cos_of_zenith_angle(deg2rad($latitude), $timestamp);
	my $secOfZenithAngle = (1/$cosOfZenithAngle);
	my $transmissionCoefficient = TRANSMISSIONCOEFFICIENTCLEARDAY - (TRANSMISSIONCOEFFICIENTCLEARDAY - TRANSMISSIONCOEFFICIENTCLOUDY) * ($cloudiness/100.0);
	my $calculatedIrradiation = 0;
	if ($cosOfZenithAngle > 0) {
		$calculatedIrradiation = (SOLAR_CONSTANT * $cosOfZenithAngle * $transmissionCoefficient ** $secOfZenithAngle)/10;
    }
	my $apparentTemperature = $dryBulbTemperature + (0.348 * $e) - (0.70 * $windSpeed) + ((0.70 * $calculatedIrradiation)/($windSpeed + 10)) - 4.25;
	#dp(__LINE__.': apparent temp: '.$apparentTemperature) if $DEBUG1;
	return sprintf "%.1f", $apparentTemperature;
}
sub get_cos_of_zenith_angle {
	my ($latitude, $timestamp, @rest) = @_;
	my $declination = deg2rad(-23.44 * cos(deg2rad((360.0/365.0) * (9 + get_day_of_year($timestamp)))));
	my $hour_angle = ((12 * 60) - get_minute_of_day($timestamp)) * 0.25;
	return sin $latitude * sin $declination + (cos $latitude * cos $declination * cos deg2rad($hour_angle));
}
sub get_day_of_year {
	my ($timestamp, $tz, @rest) = @_;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime $timestamp;
	return $yday +1;
}
sub get_minute_of_day {
	my ($timestamp, $tz, @rest) = @_;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime $timestamp;
	return $hour*60 + $min;
}

sub GETCITYCOORDS {
	my ($city, @rest) = @_;
	dp(__LINE__.' search city from DB: '.$city) if $DEBUG1;
	$city = "%${city}%";
	my $sql = 'SELECT DISTINCT LAT,LON,NAME from CITIES where NAME Like ? or (POSTNUMBER like ? AND POSTNUMBER is not null) LIMIT 1;';
	my @results = KaaosRadioClass::bindSQL($db, $sql, ($city, $city));
	da(__LINE__.' GETCITYCOORDS results', @results) if $DEBUG1;
	return $results[0], $results[1], decode('UTF-8', $results[2]);
}

# save new city to database if it does not exist
sub SAVECITY {
	my ($json, @rest) = @_;
	my $now = time;
	# primary key is POSTNUMBER
	my $sql = "INSERT OR IGNORE INTO CITIES (ID, NAME, COUNTRY, PVM, LAT, LON, POSTNUMBER) VALUES (?, ?, ?, ?, ?, ?, ?)";
	#my $sql = "INSERT OR UPDATE INTO CITIES (ID, NAME, COUNTRY, PVM, LAT, LON, POSTNUMBER) VALUES (?, ?, ?, ?, ?, ?, ?)";
	#my $sql = "INSERT INTO CITIES (ID, NAME, COUNTRY, PVM, LAT, LON, POSTNUMBER) VALUES (?, ?, ?, ?, ?, ?, ?)
	#	ON CONFLICT (ID)
	#	DO UPDATE set";
	return KaaosRadioClass::bindSQL($db, $sql, ($json->{id}, $json->{name}, $json->{sys}->{country}, $now, $json->{coord}->{lat}, $json->{coord}->{lon}, 'postnumber'));
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
									#1	#2	 #2			#4		#5		#6		#7			#8			#9		#10		#11		#12		#13			#14		#15	#16	
	my $stmt = "INSERT INTO DATA (CITY, PVM, COUNTRY, CITYID, SUNRISE, SUNSET, DESCRIPTION, WINDSPEED, WINDDIR, TEMPMAX, TEMP, HUMIDITY, PRESSURE, TEMPMIN, LAT, LON)
	 VALUES ('$name', $now, '$country', $id, $sunrise, $sunset, '$weatherdesc', '$windspeed', '$winddir', '$tempmax', '$temp', '$humidity', '$pressure', '$tempmin', '$lat', '$long')";
	#my $stmt = "INSERT INTO DATA (CITY, PVM, COUNTRY, CITYID, SUNRISE, SUNSET, DESCRIPTION, WINDSPEED, WINDDIR, TEMPMAX, TEMP, HUMIDITY, PRESSURE, TEMPMIN, LAT, LON)
	# VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
	#my @params = ($name, $now, $country, $id, $sunrise, $sunset, $weatherdesc, $windspeed, $winddir, $tempmax, $temp, $humidity, $pressure, $tempmin, $lat, $long);
	#dp(__LINE__.':SAVEDATA name: '.$name);
	return KaaosRadioClass::writeToOpenDB($dbh, $stmt);
}

sub CREATEDB {
	$dbh = KaaosRadioClass::connectSqlite($db);
	my $stmt = 'CREATE TABLE IF NOT EXISTS CITIES (
		ID int PRIMARY KEY, 
		NAME TEXT, 
		COUNTRY text, 
		PVM INT, 
		LAT TEXT, 
		LON TEXT, 
		POSTNUMBER TEXT)';

	my $rv = KaaosRadioClass::writeToOpenDB($dbh, $stmt);
	if($rv != 0) {
   		prindw("DBI Error $rv");
		return -1;
	} else {
   		prind("Table CITIES created succesfully");
	}

	my $stmt2 = 'CREATE TABLE IF NOT EXISTS DATA (
		CITY TEXT primary key, 
		PVM INT, 
		COUNTRY TEXT, 
		CITYID int, 
		SUNRISE int, 
		SUNSET int, 
		DESCRIPTION text, 
		WINDSPEED text, 
		WINDDIR text,
		TEMPMAX text, 
		TEMP text, 
		HUMIDITY text, 
		PRESSURE text, 
		TEMPMIN text, 
		LAT text, 
		LON text)';
	my $rv2 = KaaosRadioClass::writeToOpenDB($dbh, $stmt2);
	if($rv2 < 0) {
   		prindw("DBI Error: $rv2");
		return -2;
	} else {
   		prind("Table DATA created successfully");
	}

	$dbh = KaaosRadioClass::closeDB($dbh);
	return 0;
}

sub check_user_city {
	my ($checkcity, $nick, @rest) = @_;
	return undef if KaaosRadioClass::floodCheck();
	$checkcity = KaaosRadioClass::ktrim($checkcity);
	if (!$checkcity) {
		if (defined $users->{$nick}) {
			dp(__LINE__.', ei löytynyt cityä syötteestä, vanha tallessa oleva: '.$users->{$nick});
			return $users->{$nick};
		} else {
			return undef;
		}
	} else {
		$users->{$nick} = $checkcity;
		return $checkcity;
	}
}

sub filter_keyword {
	my ($msg, $nick, @rest) = @_;

	my ($returnstring, $city);
	if ($msg =~ /\!(sää |saa |s )(.*)/ui) {
		dp(__LINE__.', normaali säätilan haku: '.$nick.', city: '.$2) if $DEBUG1;
		$city = check_user_city($2, $nick);
		$dbh = KaaosRadioClass::connectSqlite($db);
		my $tempstring = FINDWEATHER($city);
		if ($tempstring) {
			dp(__LINE__);
			$returnstring = getSayLine($tempstring);
		} else {
			$returnstring = 'Paikkaa ei löytynyt..';
		}

		$dbh = KaaosRadioClass::closeDB($dbh);
	} elsif ($msg =~ /\!(se )(.*)$/i) {
		$city = check_user_city($2, $nick);
		return FINDFORECAST($city);
	} elsif ($msg =~ /\!(sa )(.*)$/i) {
		$city = check_user_city($2, $nick);
		$dbh = KaaosRadioClass::connectSqlite($db);
		$returnstring = FINDAREAWEATHER($city);
		$dbh = KaaosRadioClass::closeDB($dbh);
	} elsif ($msg =~ /(\!se5 )(.*)/) {
		$city = check_user_city($2, $nick);
		return FINDFORECAST($city, 5);
	} elsif ($msg =~ /!help sää/) {
		return $helptext;
	} elsif (($msg eq '!s' || $msg eq '!se' || $msg eq '!sa') && $users->{$nick}) {
		# when user's city is allready saved and user writes the short command only
		dp(__LINE__.', herecy: '.$users->{$nick});
		return filter_keyword($msg . ' ' . $users->{$nick}, $nick);
	} elsif (($msg eq '!s' || $msg eq '!se' || $msg eq '!se5' || $msg eq '!sa') && !$users->{$nick}) {
		return 'Unohdin, missä asuitkaan..';
	}
	return $returnstring;
}

sub stripc {
	my ($word, @rest) = @_;
	$word =~ s/['~"`;\:]//ug;
	return $word;
}

sub request_api {
	my ($url, @rest) = @_;
	$url .= $apikey;
	#dp(__LINE__ . ' url: ' . $url);
	return KaaosRadioClass::getJSON($url);
}

# debug print
sub dp {
	my ($string, @rest) = @_;
	return unless $DEBUG == 1;
	print $IRSSI{name}." debug> ".$string;
	return;
}

# debug print array
sub da {
	my ($title, @array) = @_;
	return unless $DEBUG == 1;
	print $IRSSI{name}." $title, array>";
	print Dumper(@array);
	return;
}

# Check we have an enabled channel@network
sub is_enabled_channel {
	my ($channel, $network, @rest) = @_;
	my $enabled_raw = Irssi::settings_get_str('openweathermap_enabled_channels');
	my @enabled = split / /, $enabled_raw;
	foreach my $item (@enabled) {
		if (grep /$channel/i, $item) {
        	if (grep /$network/i, $item) {
				return 1;
			}
    	}
	}
	return 0;
}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	my $mynick = quotemeta $server->{nick};
	return if ($nick eq $mynick);   # self-test
	return if $nick ~~ @ignorenicks;
	return unless is_enabled_channel($target, $server->{chatnet});

	$msg = Encode::decode('UTF-8', $msg);
	my $sayline = filter_keyword(stripc($msg), $nick);
	$server->command("msg -channel $target $sayline") if $sayline;
}

sub sig_msg_priv {
	my ($server, $msg, $nick, $address) = @_;
	return if ($nick eq $server->{nick});		# self-test
	$msg = Encode::decode('UTF-8', $msg);
	my $sayline = filter_keyword(stripc($msg), $nick);
	$server->command("msg $nick $sayline") if $sayline;
	return;
}

# print nicks and cities that we remember
sub print_cities {
	foreach ( $users ) {
		print Dumper @_;
	}
}

sub prind {
	my ($text, @rest) = @_;
	print "\0035" . $IRSSI{name} . ">\003 " . $text;
}

sub prindw {
	my ($text, @rest) = @_;
	print "\0034" . $IRSSI{name} . ">\003 " . $text;
}

Irssi::settings_add_str('openweathermap', 'openweathermap_enabled_channels', '');
Irssi::command_bind('openweathermap_cities', \&print_cities);
Irssi::signal_add('message public', 'sig_msg_pub');
Irssi::signal_add('message private', 'sig_msg_priv');

prind("v. $VERSION loaded.");
prind('New commands:');
prind('/set openweathermap_enabled_channels #channel1@IRCnet #channel2@nerv, /openweathermap_cities');
prind("Enabled on:\n". Irssi::settings_get_str('openweathermap_enabled_channels'));
