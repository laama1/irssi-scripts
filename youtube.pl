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

my $DEBUG = 0;

my $localdir = Irssi::get_irssi_dir() . '/scripts/';
my $apikeyfile = $localdir . 'youtube_apikey';
my $apikey = KaaosRadioClass::readLastLineFromFilename($apikeyfile);

my $apiurl = "https://www.googleapis.com/youtube/v3/videos?part=snippet%2CcontentDetails%2Cstatistics&key=" . $apikey;
my $apiurl_playlist_items = "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet%2CcontentDetails&key=" . $apikey;
my $apiurl_playlist = "https://www.googleapis.com/youtube/v3/playlists?part=snippet%2CcontentDetails%2Cstatus&key=" . $apikey;

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

    if ($jsondata eq '-1' || $jsondata eq '-2') {
        prindw('youtube api failed!');
        return 0;
    }

    my $len = scalar $jsondata->{items};
    if (not defined $jsondata->{items}[0]) {
        prindw('video not found from API...');
        $newUrlData->{title} = "Video not found from API...";
        return 1;
    }

    my $searchresult = $jsondata->{items}[0];

    my $likes = '👍'.$searchresult->{statistics}->{likeCount};
    my $commentcount = $searchresult->{statistics}->{commentCount};
    my $title = $searchresult->{snippet}->{title};
    my $description = $searchresult->{snippet}->{description};
    my $chantitle = $searchresult->{snippet}->{channelTitle};
    my $published = $searchresult->{snippet}->{publishedAt};
    my $duration = $searchresult->{contentDetails}->{duration};
    $duration = format_duration($duration);
    $published = format_time_ago($published);
    #$published = format_time($published);
    $newUrlData->{title} = "\0030,5 ▶ \003 " . $title . ' ['.$duration.'] [' . $chantitle . ', ' . $published . ', ' . $likes . ']';
    $newUrlData->{desc} = $description;

    my $invidious_url = $invidiousUrl . '/watch?v=' . $videoid;
    $newUrlData->{extra} = " -- proxy: $invidious_url";
    $server->command("msg $target " . $newUrlData->{title} . $newUrlData->{extra});
}

sub sig_youtube_playlist {
    my ($server, $target, $playlist_id) = @_;
    return unless KaaosRadioClass::is_enabled_channel('urltitle_enabled_channels', $server->{chatnet}, $target);
    prind("got signal: Target: $target, chatnet: $server->{chatnet}, playlist: $playlist_id");
    my $url = $apiurl_playlist . "&id=" . $playlist_id;
    my $jsondata = KaaosRadioClass::getJSON($url);

    if ($jsondata eq '-1' || $jsondata eq '-2') {
        prindw('youtube api failed!');
        return 0;
    }

    if (not defined $jsondata->{items}[0]) {
        prindw('playlist not found from API...');
        return 1;
    }
    print Dumper($jsondata);
    my $itemcount = $jsondata->{items}[0]->{contentDetails}->{itemCount};
    my $title = $jsondata->{items}[0]->{snippet}->{title};
    my $chantitle = $jsondata->{items}[0]->{snippet}->{channelTitle};
    my $published = $jsondata->{items}[0]->{snippet}->{publishedAt};
    $published = format_time_ago($published);
    my $newUrlData = {};
    $newUrlData->{title} = "\0030,5 ▶ \003 " . $title . ' [' . $chantitle . ', ' . $published . ', ' . $itemcount . ' videos]';
    my $invidious_url = $invidiousUrl . '/playlist?list=' . $playlist_id;
    $newUrlData->{extra} = " -- proxy: $invidious_url";
    $server->command("msg $target " . $newUrlData->{title} . $newUrlData->{extra});
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

sub prindw {
    my ($text, @test) = @_;
    print("\0034" . $IRSSI{name} . ">\003 ". $text);
}

prind($IRSSI{name}." v. $VERSION loaded.");
Irssi::signal_add('sig_youtube_search_id', 'sig_youtube');
Irssi::signal_add('sig_youtube_playlist_id', 'sig_youtube_playlist');