use POSIX qw(locale_h);
use POSIX qw(strftime);
use DateTime;
use locale;

my $timeint = time;

#$ENV{'LANG'}='fi_FI.utf-8';
#$ENV{'LC_CTYPE'}='fi_FI.utf-8';
my $oldlocal = setlocale(LC_CTYPE, 'fi_FI.utf-8');
my $oldlocal2 = setlocale(LC_ALL);
print('old local: '. $oldlocal. "\n");
#my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
print "Localtime: " .localtime($timeint) . "\n";
#print ("yday1: " .($yday+1) . "\n");
#my ($sec2,$min2,$hour2,$mday2,$mon2,$year2,$wday2,$yday2,$isdst2) = gmtime(time);
#print ("yday2: " .($yday2+1) . "\n");
my $number = 0.01234325;
my $number2 = 3;
printf '%1.2d', $number;
print "\n";
my $newnumber = sprintf '%.2d', $number2;
print $newnumber . " JEE\n";
#print $newnumber;
#print "\n";
# restore the old locale
#setlocale(LC_CTYPE, $oldlocal);

my $now_string = strftime "%A %B %e %H:%M:%S %Y", localtime($timeint);
print $now_string . "\n";
# or for GMT formatted appropriately for your locale:
my $now_string2 = strftime "%a %b %e %H:%M:%S %Y", gmtime;
print $now_string2 . "\n";