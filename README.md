# irssi-scripts

-Old and new scripts, mostly WIP (work in progress)

## These scripts require extra perl modules:
### addquote.pl:
- Encode

### dronebl_check.pl
- Net::DNS

### fetch_areena.pl
- JSON

### franklin3.pl
- LWP::Simple

### openweathermap.pl:
- Number::Format
- Encode

### korvamato.pl:
- Encode

### hamqsl:
- Encode

### fingrid.pl:
- Encode
- DateTime::Format::ISO8601

### hamqsl.pl:
- XML::LibXML

### horos2.pl:
- Encode

### lastspoke.pl
- JSON::PP
- Encode

### msg_telegram.pl
- URI::Encode

### poker.pl
- Run the test from this directory using: `prove -v t/poker.t` (does not work yet)

### sahkohinnat.pl
- Requires DBI, DBD::SQLite, DateTime, DateTime::Format::ISO8601, JSON, and LWP.
- Creates `scripts/sahkohinnat.sqlite` under the Irssi configuration directory.
  Each successful fetch saves the API's 15-minute prices in the `prices` table;
  repeated intervals are updated rather than duplicated. `start_utc` and `end_utc`
  are Unix timestamps in UTC, and `price` is the API price in cents/kWh, including VAT.
  Stored prices are historical records and are not used as an offline cache.
- Run the storage test using `prove -v t/sahkohinnat.t`.

### urltitle3.pl:
- Encode
- HTTP::CookieJar::LWP

### megahal2.pl (Perl Module: https://metacpan.org/pod/AI::MegaHAL, Sourcecode for the app and python + tcl interface, https://sourceforge.net/projects/megahal/)
- AI::MegaHAL

### fmi_weather.pl
- Number::Format
- pip install fmi-weather fmi-weather-client
