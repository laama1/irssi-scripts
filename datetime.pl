use POSIX qw(locale_h);
use POSIX qw(strftime);
use DateTime;
use locale;

my $dt = DateTime->now;
my $dura_begin = DateTime::Duration->new(minutes => -3);
my $start_time = ($dt + $dura_begin)->iso8601 . 'Z';
$temp = "https://data.fingrid.fi/api/data?datasets=177,181,188,191,192,193?startTime=$start_time";
print $temp;
print "\n";
exit;


my $timeint = time;

#$ENV{'LANG'}='fi_FI.utf-8';
#$ENV{'LC_CTYPE'}='fi_FI.utf-8';
#my $oldlocal = setlocale(LC_ALL, 'fi_FI.utf-8');
my $oldlocal = setlocale(LANG);
print('old local: '. $oldlocal. "\n");
#my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
print "Localtime: " .localtime($timeint) . "\n";
#print ("yday1: " .($yday+1) . "\n");
#my ($sec2,$min2,$hour2,$mday2,$mon2,$year2,$wday2,$yday2,$isdst2) = gmtime(time);
#print ("yday2: " .($yday2+1) . "\n");
#my $number = 0.01234325;
#my $number2 = 3;
#printf '%1.2d', $number;
#print "\n";
#my $newnumber = sprintf '%.2d', $number2;
#print $newnumber . " JEE\n";
#print $newnumber;
#print "\n";
# restore the old locale
#setlocale(LC_CTYPE, $oldlocal);

my $now_string = strftime "%A %B %e %H:%M:%S %Y", localtime($timeint);
print "strftime localtime: " . $now_string . "\n";
# or for GMT formatted appropriately for your locale:
my $now_string2 = strftime "%a %b %e %H:%M:%S %Y", gmtime;
print "strftime gmtime: ". $now_string2 . "\n";