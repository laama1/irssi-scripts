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
$VERSION = '20251108';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'LAama1@ircnet',
	name        => 'openweathermap.pl',
	description => 'Fetches weather data from openweathermap.org',
	license     => 'Fublic Domain',
	url         => 'https://bot.8-b.fi/#s',
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
#my $api_url = 'https://api.openweathermap.org/data/2.5/weather?q=';
my $api_url = 'https://api.openweathermap.org/data/2.5/weather?';
my $forecastUrl = 'https://api.openweathermap.org/data/2.5/forecast?';
my $areaUrl = 'https://api.openweathermap.org/data/2.5/find?cnt=5&lat=';
my $uvUrl = 'https://api.openweathermap.org/data/2.5/uvi?&lat=';
my $uvforecastUrl = 'https://api.openweathermap.org/data/2.5/uvi/forecast?';
my $DEBUG = 1;
my $DEBUG1 = 1;
my $db_file = Irssi::get_irssi_dir(). '/scripts/openweathermap3.db';
my $dbh;	# database handle

my $users_cache = {};

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


unless (-e $db_file) {
	unless(open FILE, '>:utf8',$db_file) {
		prindw("Unable to create or write DB file: $db_file");
		die;
	}
	close FILE;
	if (CREATEDB() == 0) {
		prind("Database file $db_file was created.");
	}
}

sub replace_with_emoji {
	my ($string, $sunrise, $sunset, $comparetime, $tz, @rest) = @_;
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
	$string =~ s/Rain/🌧️ /u;				 # short desc
	$string =~ s/thunderstorm with rain/⛈️ /u;
	$string =~ s/thunderstorm/⚡ /u;
	$string =~ s/light rain/☔ /u;
	$string =~ s/light intensity rain/🌂 /u;
	$string =~ s/light intensity drizzle/💧 /u;
	$string =~ s/heavy intensity shower rain/🌊 🌧️ /u;
	$string =~ s/scattered clouds/☁ /u;
	$string =~ s/shower rain/🌧️ /su;
	$string =~ s/moderate rain/🌧️ /su;
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
		$string =~ s/few clouds/☁ /sui;
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
	if ($comparetime > $sunset || $comparetime < $sunrise) {
		return 0;
	}
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

# param: exact city name, returns json answer for current weather or undef if not found
sub GET_WEATHER {
	my ($searchword, @rest) = @_;
	if ($searchword eq '') {
		return undef;
	}
	my $newurl;
	my $urltail = $searchword;
	if ($searchword =~ /(\d{5})/) {
		$newurl = $api_url . 'zip=';
		$urltail = $1 . ',fi';		# Search post numbers from finland only
	} else {
		$newurl = $api_url . 'q=';
	}
	my $json = request_api($newurl.$urltail);
	da(__LINE__.': GET_WEATHER json', $json);
	#my ($id, $lat, $lon, $city) = FIND_CITY($searchword);

	#if ($json eq '-1') {
		# searchword not found from API
		#dp(__LINE__.' city not found from API, searchword: '.$searchword) if $DEBUG1;
		#return undef unless defined $city;
		#$urltail = $city;
		#$json = request_api($newurl.$urltail) if $urltail;
		#if ($json eq '-1') {
			#return "Paikkaa ei löydy!";
			#dp(__LINE__.' city not available, city name: '.$city) if $DEBUG1;
		#}
		return undef if (!defined $json || $json eq '-1');
	#}

	$json->{uvindex} = 0;
	#if ($lat && $lon) {
	#	$json->{uvindex} = $fi->format_number(FINDUVINDEX($lat, $lon), 0);
	#}

	SAVE_CITY($json);
	SAVEDATA($json);
	return $json;
}

sub FINDFORECAST {
	my ($searchword, $days, @rest) = @_;
	my $json;
	#dp(__LINE__ . ', searchword: ' . $searchword);
	if ($searchword =~ /(\d{5})/) {
		dp(__LINE__);
		my $urltail = 'zip='.$1.',fi';		# Search postcode numbers only from finland
		$json = request_api($forecastUrl.$urltail);
	} else {
		dp(__LINE__);
		$json = request_api($forecastUrl.'q='.$searchword);
	}
	dp(__LINE__);
	if ($json eq '-1') {
		dp(__LINE__ . ' no match from api, try searching city from DB');
		#$dbh = KaaosRadioClass::connectSqlite($db_file);
		my ($id, $lat, $lon, $city) = FIND_CITY($searchword);
		#$dbh = KaaosRadioClass::closeDB($dbh);
		dp (__LINE__ . ', city: ' . $city);
		$json = request_api($forecastUrl.'q='.$city) if defined $city;
		return 0 if ($json eq '-1');
	}
	dp(__LINE__ . ', got json from api');
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
			$returnstring = "\002" . $use_this_city . ','.$json->{city}->{country} . " $timezone klo:\002 ";
		}
		dp(__LINE__);
		my $weathericon = replace_with_emoji($item->{weather}[0]->{main},
												$json->{city}->{sunrise},
												$json->{city}->{sunset},
												$item->{dt},
												$json->{city}->{timezone}
											);
		my $temptimedt = DateTime->from_epoch(epoch => ($item->{dt} + $json->{city}->{timezone}));
		$returnstring .= "\002" . sprintf('%.2d', $temptimedt->hour) . ":\002 $weathericon " . $fi->format_number($item->{main}->{temp}, 0) . '°C, ';
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
	my @weekdayarray = ('su','ma','ti','ke','to','pe','la','su');
	my $timezone = $json->{city}->{timezone};
	foreach my $item (@{$json->{list}}) {
		my $tiem = $item->{dt_txt};
		my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = gmtime ($item->{dt} + $timezone);
		my $weekdaystring = $weekdayarray[$wday];
		#if ($tiem =~ /00:00:00/ || $tiem =~ /12:00:00/) {	# TODO: per timezone not UTC
		if ($hour == 0 || $hour == 12) {
			print __LINE__ . ': sec: ' . $sec . ', min: ' . $min . ', hour: ' . $hour . ', mday: ' . $mday . ', mon: ' . $mon . ', year: ' . $year . ', wday: ' . $wday . ', yday: ' . $yday . ', isdst: ' . $isdst if $DEBUG1;
			if ($index == 0) {
				$returnstring = "\002" . $json->{city}->{name} . ',' . $json->{city}->{country} . "\002 ";
			}
			dp(__LINE__);
			my $weathericon = replace_with_emoji($item->{weather}[0]->{main}, 
												$json->{city}->{sunrise},
												$json->{city}->{sunset}, 
												$item->{dt}, 
												$timezone
												);
			if ($wday eq $daytemp) {
				$returnstring .= "\002" . sprintf('%.2d', $hour) .":\002 $weathericon ".$fi->format_number($item->{main}->{temp}, 0) . "°C";
			} else {
				#$returnstring .= "\002".$mday.'.'.($mon+1).'. ('.sprintf('%.2d', $hour) .":\002 $weathericon ".$fi->format_number($item->{main}->{temp}, 0) .'°C, ';
				$returnstring .= "\002" . $weekdaystring.': ('.sprintf('%.2d', $hour) .":\002 $weathericon ".$fi->format_number($item->{main}->{temp}, 0) .'°C, ';
			}
			#if ($tiem =~ /12:00:00/) {
			if ($hour == 12) {
				# end of temperature pair
				$returnstring .= "\002)\002, ";

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
	my ($id, $lat, $lon, $name) = FIND_CITY($city);   # 1) find existing city from DB by search word
	dp(__LINE__ . ': name found?: '.$name);
	my $rubdata = GET_WEATHER($city);                 # 2) find one weather from API for sunrise & sunset & timezone times
	my $timezone = $rubdata->{timezone};
	#da(__LINE__.': FINDAREAWEATHER rubdata', $rubdata);
	if (!defined $lat && !defined $lon && !defined $name && defined $rubdata->{coord}) {
													  # 3) if city was not found from DB, but "GET_WEATHER" found something from API
		$lat = $rubdata->{coord}->{lat};
		$lon = $rubdata->{coord}->{lon};
		$name = $rubdata->{name};
		
	}
	dp(__LINE__ . ': lat: ' . $lat . ', lon: ' . $lon . ', name: ' . $name . ', timezone: ' . $timezone);
	#($id, $lat, $lon, $name) = FIND_CITY($city) unless ($lat && $lon && $name);      # 3) find existing city again from DB
	return 'City not found from DB or API.' unless ($lat && $lon && $name);

	# important: No timezone from weather API from this request.
	my $searchurl = $areaUrl.$lat."&lon=$lon";
	my $json = request_api($searchurl);
	#da(__LINE__.': FINDAREAWEATHER json', $json);
	return 0 if ($json eq '-1');

	my $sayline;
	foreach my $city (@{$json->{list}}) {
		# TODO: get city coords from API and save to DB
		$sayline .= getSayLine2($city, $rubdata->{sys}->{sunrise}, $rubdata->{sys}->{sunset}, $timezone) . '. ';
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
	return $json->{value};
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

sub make_winddir_arrow {
	my ($degrees, @rest) = @_;

    if ($degrees >= 337.5 || $degrees < 22.5) {
		return '↓';
    } elsif ($degrees >= 22.5 && $degrees < 67.5) {
		return '↙';
    } elsif ($degrees >= 67.5 && $degrees < 112.5) {
		return '←';
    } elsif ($degrees >= 112.5 && $degrees < 157.5) {
		return '↖';
    } elsif ($degrees >= 157.5 && $degrees < 202.5) {
		return '↑';
    } elsif ($degrees >= 202.5 && $degrees < 247.5) {
		return '↗';
    } elsif ($degrees >= 247.5 && $degrees < 292.5) {
		return '→';
    } elsif ($degrees >= 292.5 && $degrees < 337.5) {
		return '↘';
    }
}

# for the command !sa, area weather
sub getSayLine2 {
	my ($json, $sunrise, $sunset, $timezone, @rest) = @_;
	return unless $json;
	my $weatherdesc = make_weather_desc(@{$json->{weather}});
	my $newcity = changeCity($json->{name});

	my $returnvalue = $newcity . ': ' . $fi->format_number($json->{main}->{temp}, 0) . '°C, ' . 
		replace_with_emoji($weatherdesc, $sunrise, $sunset, time, $timezone);
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
	return undef unless defined $json || $json eq '0' || $json eq '-1';
	#if ($json eq '0' || $json eq '-1') {
	#	return undef;
	#}
	#print __LINE__ . ': dump json' if $DEBUG1;
	#print Dumper $json if $DEBUG1;

	my $tempmin = $fi->format_number($json->{main}->{temp_min}, 1);
	my $tempmax = $fi->format_number($json->{main}->{temp_max}, 1);
	my $pressure = $json->{main}->{pressure} . 'hPa';
	my $humidity = $json->{main}->{humidity} . '%';
	my $snow = '';
	if (defined $json->{snow} && defined $json->{snow}->{'1h'} && $json->{snow}->{'1h'} > 0) {
		$snow = $json->{snow}->{'1h'};
		$snow = $fi->format_number($snow, 1) . 'mm/h';
		$snow = ', ❄️ ' . $snow;
	}
	my $temp;
	#if ($tempmin ne $tempmax) {
	#	$temp = "($tempmin…$tempmax)°C"
	#} else {
		$temp = $fi->format_number($json->{main}->{temp}, 0).'°C';
	#}
	#my $havaintotime = gmtime($json->{dt})->strftime('%H:%M');
	#my $apparent_temp = get_apparent_temp($json->{main}->{temp}, $json->{main}->{humidity}, $json->{wind}->{speed}, $json->{clouds}->{all}, $json->{coord}->{lat}, $json->{dt});
	my $apparent_temp = $json->{main}->{feels_like};
	my $sky = '';

	if ($apparent_temp) {
		$apparent_temp = ' (~ ' . $fi->format_number($apparent_temp, 0).'°C)';
	} else {
		$apparent_temp = '';
	}

	my $sunrisedt = DateTime->from_epoch( epoch => ($json->{sys}->{sunrise} + $json->{timezone}));
	my $sunsetdt = DateTime->from_epoch( epoch => ($json->{sys}->{sunset} + $json->{timezone}));

	my $sunrise = '🌇 '.$sunrisedt->hour . ':' . sprintf('%.2d', $sunrisedt->minute);

	#my $sunset = '-> ' .localtime($json->{sys}->{sunset})->strftime('%H:%M');
	my $sunset = '-> ' .$sunsetdt->hour . ':'.sprintf('%.2d', $sunsetdt->minute);
	my $wind_speed = $fi->format_number($json->{wind}->{speed}, 0);
	my $wind_gust = '';
	$wind_gust .= $fi->format_number($json->{wind}->{gust}, 0) if (defined $json->{wind}->{gust});
	my $winddir = make_winddir_arrow($json->{wind}->{deg});

	my $wind = '💨 '.$wind_speed;
	if (defined $wind_gust && $wind_gust ne '') {
		$wind .= " ($wind_gust)";
	}
	$wind .= ' m/s';
	$wind .= " $winddir";
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
		$uv_index = ', UVI: ' . $fi->format_number($json->{uvindex}, 0);
	}
	dp(__LINE__ . ' city: ' . $city);
	my $newdesc = replace_with_emoji($weatherdesc, 
									$json->{sys}->{sunrise},
									$json->{sys}->{sunset},
									$json->{dt},
									$json->{timezone}
									);
	my $returnvalue = $city.': '.$newdesc.' '.$temp.$apparent_temp.', '.$sunrise.' '.$sunset.', '.$wind.$sky . $uv_index.', P: '. $pressure . ', RH: ' . $humidity . $snow;
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

# find city from database using city name or city post number, return first found ID, LAT, LON, NAME
sub FIND_CITY {
	my ($city, @rest) = @_;
	if ($city eq '') {
		return undef, undef, undef, undef;
	}
	$city = "%${city}%";
	my $sql = 'SELECT DISTINCT CITYID, LAT, LON, NAME from CITIES where NAME Like ? or (POSTNUMBER like ? AND POSTNUMBER is not null) LIMIT 1;';
	my @results = KaaosRadioClass::bindSQL($db_file, $sql, ($city, $city));
	if (not defined $results[0][0]) {
		return undef, undef, undef, undef;
	}
	return $results[0][0], $results[0][1], $results[0][2], decode('UTF-8', $results[0][3]);
}

# save new city to database if it does not exist
sub SAVE_CITY {
	my ($json, @rest) = @_;
	dp(__LINE__.': SAVE_CITY next.. ' . $json->{name});
	my $now = time;
	my $sql = "INSERT OR REPLACE INTO CITIES (CITYID, NAME, COUNTRY, PVM, LAT, LON, POSTNUMBER) VALUES (?, ?, ?, ?, ?, ?, ?)";
	return KaaosRadioClass::insertSQL($db_file, $sql, ($json->{id}, $json->{name}, $json->{sys}->{country}, $now, $json->{coord}->{lat}, $json->{coord}->{lon}, 'postnumber'));
}

# save weather data to database
sub SAVEDATA {
	my ($json, @rest) = @_;
	dp(__LINE__.': SAVEDATA next..');
	my $now = time;
	my $name = $json->{name};
	my $country = $json->{sys}->{country} || '';
	my $id = $json->{id} || -1;	 # city ID
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
	return KaaosRadioClass::insertSQL($db_file, $stmt, ());
}

# create tables to database if they do not exist
sub CREATEDB {
	$dbh = KaaosRadioClass::connectSqlite($db_file);
	my $stmt = 'CREATE TABLE IF NOT EXISTS CITIES (
		CITYID int PRIMARY KEY, 
		NAME TEXT, 
		COUNTRY TEXT, 
		PVM INT, -- last updated
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
		CITY TEXT, 
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

	my $stmt3 = 'CREATE TABLE IF NOT EXISTS USERS (
		NICK TEXT PRIMARY KEY, 
		CITY int,
		FOREIGN KEY (CITY) REFERENCES CITIES(CITYID))';
	my $rv3 = KaaosRadioClass::writeToOpenDB($dbh, $stmt3);
	if($rv3 < 0) {
   		prindw("DBI Error: $rv3");
		return -3;
	} else {
   		prind("Table USERS created successfully");
	}

	$dbh = KaaosRadioClass::closeDB($dbh);
	return 0;
}

# Check if user has saved city, if not save new city. Return undef if no city found or city name.
sub check_user_city {
	my ($checkcity, $nick, @rest) = @_;
	#return undef if KaaosRadioClass::floodCheck();
	$checkcity = KaaosRadioClass::ktrim($checkcity);
	if (!$checkcity) {
		if (defined $users_cache->{$nick}) {
			#dp(__LINE__.', ei löytynyt cityä käyttäjän syötteestä, vanha tallessa oleva löytyi: '.$users_cache->{$nick});
			return $users_cache->{$nick};
		} else {
			read_user_city_from_database($nick);
			if (defined $users_cache->{$nick}) {
				#dp(__LINE__ . ' käyttäjän city löytyi tietokannasta: ' . $users_cache->{$nick});
				return $users_cache->{$nick};
			}
			return undef;
		}
	} else {
		# save new city

		if (save_user_city_to_database($nick, $checkcity)) {
			dp(__LINE__.', tallennettu käyttäjän ' . $nick . ' uusi kaupunki: ' . $users_cache->{$nick});
		}
		return $checkcity;
	}
}

sub read_user_city_from_database {
	my $nick = shift;
	dp(__LINE__.', read_user_city_from_database next for nick: ' . $nick);
	if (defined $users_cache->{$nick}) {
		dp(__LINE__.', käyttäjän '.$nick.' kaupunki löytyi välimuistista: '.$users_cache->{$nick});
		return $users_cache->{$nick};
	}
	my $sql = 'SELECT C.NAME FROM USERS U LEFT JOIN CITIES C ON U.CITY = C.CITYID WHERE U.NICK = ? LIMIT 1;';
	my @results = KaaosRadioClass::bindSQL($db_file, $sql, ($nick));
	da(__LINE__, Dumper(@results));
	if (defined $results[0][0]) {
		$users_cache->{$nick} = decode('UTF-8', $results[0][0]);
		dp(__LINE__.', luettu käyttäjän '.$nick.' kaupunki tietokannasta: '.$users_cache->{$nick});
		return $users_cache->{$nick};
	}
	dp(__LINE__.', käyttäjälle '.$nick.' ei löytynyt kaupunkia tietokannasta.');
	return undef;
}

sub save_user_city_to_database {
	my ($nick, $city, @rest) = @_;
	dp(__LINE__.', save_user_city_to_database next, nick: '.$nick.', city: '.$city);
	return 1 if (defined $users_cache->{$nick} && $city eq $users_cache->{$nick});
	dp (__LINE__.', tarkistetaan kaupungin olemassaolo tietokannasta: '.$city);

	my $sql = 'SELECT CITYID FROM CITIES WHERE NAME = ? LIMIT 1;';
	my @results = KaaosRadioClass::bindSQL($db_file, $sql, ($city));
	my $city_id = '';
	#da(__LINE__, Dumper(\@results));
	if (defined $results[0][0]) {
		$city_id = $results[0][0];
		my $sql = 'INSERT OR REPLACE INTO USERS (NICK, CITY) VALUES (?, ?);';
		if (KaaosRadioClass::insertSQL($db_file, $sql, ($nick, $city_id))) {
			dp(__LINE__.', tallennettu käyttäjän '.$nick.' kaupunki tietokantaan, id: '.$city_id);
			$users_cache->{$nick} = $city;
			return 1;
		}
	}
	return 0;
}

sub filter_keyword {
	my ($msg, $nick, @rest) = @_;
	my ($returnstring, $city);

	if ($msg =~ /^\!(sää |saa |s )(.*)/ui) {
		# !sää with a search word, always save new city to user

		my $searchword = KaaosRadioClass::ktrim($2);
		if (!$searchword) {
			return 'Kirjoita kaupunki, esim: !sää Kuopio';
		}
		dp(__LINE__ . ', searchword: ' . $searchword . '<');

		my ($id, $lat, $lon, $city) = FIND_CITY($searchword);

		if (not defined $city) {
			$city = $searchword;
		}
		my $tempstring = GET_WEATHER($city);

		if ($tempstring) {
			dp(__LINE__ . ', weather found for searchword/city: ' . $city);
			$returnstring = getSayLine($tempstring);
			save_user_city_to_database($nick, $city);
		} else {
			$returnstring = 'Paikkaa ei löytynyt..';
		}
	} elsif ($msg =~ /^(\!se )(.*)$/i) {
		$city = check_user_city($2, $nick);
		$returnstring = FINDFORECAST($city);
	} elsif ($msg =~ /^(\!sa )(.*)$/i) {
		$city = check_user_city($2, $nick);
		#$dbh = KaaosRadioClass::connectSqlite($db_file);
		$returnstring = FINDAREAWEATHER($city);
		#$dbh = KaaosRadioClass::closeDB($dbh);
	} elsif ($msg =~ /^(\!se5 )(.*)/) {
		$city = check_user_city($2, $nick);
		$returnstring = FINDFORECAST($city, 5);

	} elsif ($msg eq '!se') {
		my $user_city = check_user_city('', $nick);
		if (not defined $user_city) {
			dp(__LINE__ . ', no user city found for nick: ' . $nick . ', city: ' . $user_city);
			$returnstring = 'Unohdin, missä asuitkaan.. Kirjoita: !se kaupunni';
		} else {
			$returnstring = FINDFORECAST($user_city);
		}
	} elsif ($msg eq '!sa') {
		my $user_city = check_user_city('', $nick);
		if (not defined $user_city) {
			dp(__LINE__ . ', no user city found for nick: ' . $nick . ', city: ' . $user_city);
			$returnstring = 'Unohdin, missä asuitkaan.. Kirjoita: !sa kaupunni';
		} else {
			#$dbh = KaaosRadioClass::connectSqlite($db_file);
			$returnstring = FINDAREAWEATHER($user_city);
			#$dbh = KaaosRadioClass::closeDB($dbh);
		}
	} elsif (($msg eq '!s' || $msg eq '!sa') && defined $users_cache->{$nick}) {
		# when user's city is allready saved and user writes the short command only
		dp(__LINE__.', herecy, msg: ' . $msg . ', city: '.$users_cache->{$nick});
		my $user_city = check_user_city('', $nick);
		if (not defined $user_city) {
			dp(__LINE__ . ', no user city found for nick: ' . $nick . ', city: ' . $user_city);
			$returnstring = 'Unohdin, missä asuitkaan.. Kirjoita: !s kaupunni';
		}
		my $tempstring = GET_WEATHER($user_city);
		if ($tempstring) {
			dp(__LINE__ . ', weather found for user: ' . $nick . ' city: ' . $user_city);
			$returnstring = getSayLine($tempstring);
		} else {
			$returnstring = 'Paikkaa ei löytynyt.. (' . $user_city . ')';
		}
		#return filter_keyword($msg . ' ' . $users_cache->{$nick}, $nick);
	} elsif (($msg eq '!s' || $msg =~ /^!se\d?$/ || $msg eq '!se5' || $msg eq '!sa') && not defined $users_cache->{$nick}) {
		read_user_city_from_database($nick);
		if (defined $users_cache->{$nick}) {
			my $tempstring = GET_WEATHER($users_cache->{$nick});
			if ($tempstring) {
				dp(__LINE__ . ', weather found for user city from DB: ' . $users_cache->{$nick});
				$returnstring = getSayLine($tempstring);
			} else {
				$returnstring = 'Paikkaa ei löytynyt.. (' . $users_cache->{$nick} . ')';
			}
		} else {
			$returnstring = 'Unohdin, missä asuitkaan.. Kirjoita: !s kaupunki';
		}
		
	}
	return $returnstring;
}

# strip strange chars
sub stripc {
	my ($word, @rest) = @_;
	$word =~ s/['~"`;\:]//ug;
	return $word;
}

sub request_api {
	my ($urli, @rest) = @_;
	$urli .= $apikey;
	return KaaosRadioClass::getJSON($urli);
}

# debug print
sub dp {
	my ($string, @rest) = @_;
	return unless $DEBUG == 1 || $DEBUG1 == 1;
	print $IRSSI{name}." debug> ".$string;
	return;
}

# debug print array
sub da {
	my ($title, @array) = @_;
	return unless $DEBUG == 1 || $DEBUG1 == 1;
	print $IRSSI{name}." $title, array>";
	print Dumper(@array);
	return;
}


sub add_enabled_channel_command {
	my ($text, $server, $channel, @rest) = @_;
	#if (not defined $channel or $channel == '') {
    #    prindw("No channel context found. Change to a channel window first.");
    #    return -1;
    #}
	my $rv = KaaosRadioClass::add_enabled_channel('openweathermap_enabled_channels', $server->{chatnet}, $channel->{name});
	prind("Enabled channels: " . Irssi::settings_get_str('openweathermap_enabled_channels'));
	return 0;
}

sub remove_enabled_channel_command {
	my ($text, $server, $channel, @rest) = @_;
	my $rv = KaaosRadioClass::remove_enabled_channel('openweathermap_enabled_channels', $server->{chatnet}, $channel->{name});
	prind("Channel $channel->{name}\@$server->{chatnet} removed from enabled channels.");
	prind("Enabled channels: " . Irssi::settings_get_str('openweathermap_enabled_channels'));
	return 1;
}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	my $mynick = quotemeta $server->{nick};
	$nick = quotemeta $nick;
	return if ($nick eq $mynick);   # self-test
	return if $nick ~~ @ignorenicks;
	return unless KaaosRadioClass::is_enabled_channel('openweathermap_enabled_channels', $server->{chatnet}, $target);

	my $sayline = '';

	if ($msg =~ /^\!enable openweathermap/) {
		return KaaosRadioClass::add_enabled_channel('openweathermap_enabled_channels', $server->{chatnet}, $target);
	} elsif ($msg =~ /^\!disable openweathermap/) {
		return KaaosRadioClass::remove_enabled_channel('openweathermap_enabled_channels', $server->{chatnet}, $target);
	} elsif ($msg =~ /^\!help sää/) {
		$sayline = $helptext;
	} else {
		$msg = Encode::decode('UTF-8', $msg);
		$sayline = filter_keyword(stripc($msg), $nick);
	}

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
	prind("Printing users and their cities:");
	foreach my $user (%{$users_cache}) {
		print Dumper $user;
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
Irssi::command_bind('openweathermap_cities', \&print_cities, 'openweathermap');
Irssi::command_bind('openweathermap_add_channel', \&add_enabled_channel_command, 'openweathermap');
Irssi::command_bind('openweathermap_remove_channel', \&remove_enabled_channel_command, 'openweathermap');
Irssi::signal_add('message public', 'sig_msg_pub');
Irssi::signal_add('message private', 'sig_msg_priv');

prind("v. $VERSION loaded.");
prind('New commands:');
prind('/set openweathermap_enabled_channels #channel1@IRCnet #channel2@nerv, /openweathermap_cities');
prind('/openweathermap_add_channel #channel network, /openweathermap_remove_channel #channel network');
prind("Enabled on:\n". Irssi::settings_get_str('openweathermap_enabled_channels'));
