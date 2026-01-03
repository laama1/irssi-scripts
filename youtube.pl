use Irssi;
use strict;
use warnings;
use utf8;
use Data::Dumper;
use JSON;
use POSIX;
use Time::Piece;
use vars qw($VERSION %IRSSI);
use Data::Dumper;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;


$VERSION = '2025-11-22';
%IRSSI = (
        authors     => 'laama',
        contact     => "laama #kaaosradio",
        name        => "youtube.pl",
        description => "Fetch info from youtube api",
        license     => "Fublic Domain",
        url         => "https://kaaos.radio",
        changed     => $VERSION
);

my $DEBUG = 1;

my $localdir = Irssi::get_irssi_dir() . '/scripts/';
my $apikeyfile = $localdir . 'youtube_apikey';
my $apikey = KaaosRadioClass::readLastLineFromFilename($apikeyfile);

my $apiurl = "https://www.googleapis.com/youtube/v3/videos?part=snippet%2CcontentDetails%2Cstatistics&key=" . $apikey;

#my $invidiousUrl = 'https://invidious.private.coffee';
my $invidiousUrl = 'https://farside.link/invidious';
#my $invidiousUrl ='https://invidious.protokolla.fi';


sub sig_youtube {
    my ($server, $target, $videoid) = @_;
    return unless KaaosRadioClass::is_enabled_channel('urltitle_enabled_channels', $server->{chatnet}, $target);

    prind("got signal: Target: $target, chatnet: $server->{chatnet}, videoid: $videoid");
    my $newUrlData = {};
    my $url = $apiurl . "&id=" . $videoid;
    my $jsondata = KaaosRadioClass::getJSON($url);
    #print Dumper $jsondata if ($DEBUG);

    if ($jsondata eq '-1' || $jsondata eq '-2') {
        prind('youtube api failed!');
        return 0;
    }

    my $len = scalar $jsondata->{items};
    if (not defined $jsondata->{items}[0]) {
        prind('video not found from API...');
        $newUrlData->{title} = "Video not found from API...";
        return 1;
    }

    my $searchresult = $jsondata->{items}[0];
    #print Dumper $searchresult if ($DEBUG);

    my $likes = '👍'.$searchresult->{statistics}->{likeCount};
    my $commentcount = $searchresult->{statistics}->{commentCount};
    my $title = $searchresult->{snippet}->{title};
    my $description = $searchresult->{snippet}->{description};
    my $chantitle = $searchresult->{snippet}->{channelTitle};
    my $published = $searchresult->{snippet}->{publishedAt};
    my $duration = $searchresult->{contentDetails}->{duration};
    $duration = format_duration($duration);
    $published = format_time($published);
    $newUrlData->{title} = "\0030,5 ▶ \003 " . $title . ' ['.$duration.'] [' . $chantitle . ', ' . $published . ', ' . $likes . ']';
    $newUrlData->{desc} = $description;

    my $invidious_url = $invidiousUrl . '/watch?v=' . $videoid;
    $newUrlData->{extra} = " -- proxy: $invidious_url";
    $server->command("msg $target " . $newUrlData->{title} . $newUrlData->{extra});
}

# format youtube timestamp
sub format_time {
	my ($value, @rest) = @_;
    #print Dumper $value if $DEBUG;
	my $time_object = Time::Piece->strptime($value, "%Y-%m-%dT%H:%M:%SZ");	# ISO8601
	my $local_time = localtime;

	my $diff = ($local_time - $time_object);

	prind(__LINE__ . ': diff in seconds: ' . $diff . ', years: ' . floor($diff / 29030400) . 'y, months: ' . floor($diff / 2419200) . 'mon, weeks: ' . floor($diff / 604800) . 'wk, days: ' . floor($diff / 86400) . 'days, hours: ' . floor($diff / 3600) . 'h, minutes: ' . floor($diff / 60) . 'min') if $DEBUG;	# debug
	my $result = '';
	if ($diff >= 29030400) {
    	$result = sprintf("%.1f", ($diff / 29030400)) . 'y';
	} elsif ($diff >= 2419200) {
		$result = sprintf("%.1f", ($diff / 2419200)) . 'mon';
	} elsif ($diff >= 604800) {
		$result = sprintf("%.1f", ($diff / 604800)) . 'wk';
	} elsif ($diff > 86400) {
		$result = sprintf("%.1f", ($diff / 86400)) . 'days';
	} elsif ($diff > 3600) {
		$result = sprintf("%.1f", ($diff / 3600)) . 'h';
	} elsif($diff > 60) {
		$result = sprintf("%.f", $diff / 60) . 'mins';
	} else {
		$result .= 's';
	}
	$result .= ' ago';
	return $result;
}

sub format_duration {
    my ($value, @rest) = @_;
    # 'duration' => 'PT42M45S',
    $value =~ /PT((\d+)H)?((\d+)M)?((\d+)S)?/;
    my $hours = defined $2 ? $2 : 0;
    my $minutes = defined $4 ? $4 : 0;
    my $seconds = defined $6 ? $6 : 0;
    my $result = '';
    if ($hours > 0) {
        $result .= $hours . ':';
    }
    $result .= sprintf("%02d:%02d", $minutes, $seconds);
    return $result;
}

sub prind {
	my ($text, @test) = @_;
	print("\0038" . $IRSSI{name} . ">\003 ". $text);
}

prind($IRSSI{name}." v. $VERSION loaded.");
Irssi::signal_add('youtube_search_id', 'sig_youtube');