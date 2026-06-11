use Irssi;
use vars qw($VERSION %IRSSI);
use strict;
use warnings;
use POSIX;
use LWP::UserAgent;
use Data::Dumper;
use JSON;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;		# LAama1 26.10.2016

$VERSION = '2026-02-21';
%IRSSI = (
        authors     => 'laama',
        contact     => "laama #irc-galleriaa",
        name        => "Imgur-API-script",
        description => "Fetch info from imgur api",
        license     => "Public Domain",
        url         => "http://8-b.fi",
        changed     => $VERSION
);

my $DEBUG = 1;
my $imgur_proxy_url = 'farside.link/rimgo';

my $baseurl = 'https://api.imgur.com/3/';
my $apiurl_image = $baseurl . "image/";
my $apiurl_gallery = $baseurl . "gallery/album/";
my $apiurl_album = $baseurl . "album/";
my $clientid_file = Irssi::get_irssi_dir() . '/scripts/irssi-scripts/imgur_client_id';

my $clientid = readLastLineFromFilename($clientid_file) || '';
my $h = HTTP::Headers->new;
$h->header('Accept-Encoding' => 'gzip,deflate,br', 'Authorization' => "Client-ID $clientid");

sub imgur_api  {
    my ($server, $target, $url, @rest) = @_;
    prind('Imgur url: ' . $url);
	return 0 unless $url =~ /imgur\.com/;

	if ($url =~ /\:\/\/imgur\.com\/gallery\/.*-([\d\w\W]{2,8})$/) {
		# example: https://imgur.com/gallery/two-people-that-always-comment-on-nonsense-getting-notified-you-submitted-shitpost-tMMxzLa
		my $gallery = $1;
		prind("Imgur gallery: $gallery");
		my $apiurl = $apiurl_gallery . $gallery;

		my $jsondata = getJSON($apiurl, $h);
		if ($jsondata eq '-1') {
			prindw("FAK gallery!");
			return 0;
		}
		my $id = $jsondata->{data}->{id} || '';
		my $title = $jsondata->{data}->{title} || '';
        $title .= ' ' if $title ne '';

		my $description = $jsondata->{data}->{description} || '';   # usually null here
		my $datetime = $jsondata->{data}->{datetime} || '';         # upload datetime in unix timestamp
		my $datetime_formatted = strftime('%Y-%m-%d %H:%M:%S', localtime($datetime)) if $datetime;
		my $account = $jsondata->{data}->{account_url} || '';       # account name
		my $images_count = $jsondata->{data}->{images_count} || '';
        my $views = $jsondata->{data}->{views} || '';
        my $upvotes = $jsondata->{data}->{ups} || '';

		$title = "\0033Imgur gallery:\003 ${title}[${images_count} images, by: ${account}";

        if ($upvotes) {
            $title .= ' 👍' . $upvotes;
        }
        $title .= ']';
		$url =~ s/https?:\/\/imgur\.com\//https:\/\/$imgur_proxy_url\//;
		$server->command("MSG $target $title -> $url");
		return 1;
 	} elsif ($url =~ /\:\/\/imgur\.com\/a\/([\d\w\W]{2,8})$/) {
		# example: https://imgur.com/a/2nqjLZt
		my $album = $1;
		prind("Imgur album: $album");
		my $apiurl = $apiurl_album . $album;

		my $jsondata = getJSON($apiurl, $h);
		if ($jsondata eq '-1') {
			prindw("FAKa!");
			return 0;
		}
		my $id = $jsondata->{data}->{id} || '';
		my $title = $jsondata->{data}->{title} || '';
		$title .= ' ' if $title ne '';
		my $description = $jsondata->{data}->{description} || '';
		my $datetime = $jsondata->{data}->{datetime} || '';
		my $datetime_formatted = strftime('%Y-%m-%d %H:%M:%S', localtime($datetime)) if $datetime;
		my $views = $jsondata->{data}->{views} || '';
		$title = "\0033Imgur album:\003 ${title}[";
		if ($datetime_formatted) {
			$title .= "uploaded: $datetime_formatted";
		}
		if ($views) {
			$title .= " views: $views";
		}
		$title .= ']';
		$url =~ s/https?:\/\/imgur\.com\//https:\/\/$imgur_proxy_url\//;
		$server->command("MSG $target $title -> $url");
		return 1;
	} elsif ($url =~ /\:\/\/imgur\.com\/([\d\w\W]{2,8})/ || $url =~ /\:\/\/i\.imgur\.com\/([\d\w\W]{2,8})\.(jpg|png|gif|jpeg|mp4)/) {
		# example https://i.imgur.com/VEPMTkD.jpg
		my $image = $1;
		prind("Imgur direct image: $image");
		my $apiurl = $apiurl_image . $image;

    	my $jsondata = getJSON($apiurl, $h);
		if ($jsondata eq '-1') {
			prindw("FAK!");
			return 0;
		}
		df(__LINE__ . ' urltitle imgurdata: ' . Dumper($jsondata)) if $DEBUG;
		my $id = $jsondata->{data}->{id} || '';
		my $title = $jsondata->{data}->{title} || $jsondata->{data}->{name};
		$title .= ' ' if $title ne '';
		my $width = $jsondata->{data}->{width} || '';
		my $height = $jsondata->{data}->{height} || '';
		my $size = $jsondata->{data}->{size} || $jsondata->{data}->{mp4_size};
		my $views = $jsondata->{data}->{views} || '';
		my $datetime = $jsondata->{data}->{datetime} || '';
		my $datetime_formatted = strftime('%Y-%m-%d %H:%M:%S', localtime($datetime)) if $datetime;
		my $tags = $jsondata->{data}->{tags} || [];
		# fixme
			$tags = join(', ', @$tags);
			$tags = "Tags: ${tags}" if $tags ne '';
			$tags = '' if $tags eq '';

		$title = "\0033Imgur image:\003 ${title}[${width}x${height}, " . sprintf("%.2f", $size / 1024) . "KiB";
		if ($views) {
			$title .= ", views: $views";
		}
		if ($datetime_formatted) {
			$title .= ", uploaded: $datetime_formatted";
		}
		if ($tags) {
			$title .= ", Tags: $tags";
		}
		$title .= ']';

		$url =~ s/https?:\/\/imgur\.com\//https:\/\/$imgur_proxy_url\//;
		$url =~ s/https?:\/\/i\.imgur\.com\//https:\/\/$imgur_proxy_url\//;
		$server->command("MSG $target $title -> $url");
		return 1;
	}

}

sub dp {
	return unless $DEBUG;
	my $sayline = shift;
	print($IRSSI{name}. " debug: $sayline");
}
sub prind {
	my ($text, @test) = @_;
	print("\0033" . $IRSSI{name} . ">\003 ". $text);
}

sub prindw {
	my ($text, @test) = @_;
	print("\0034" . $IRSSI{name} . ">\003 ". $text);
}

Irssi::signal_add('sig_imgur_api', 'imgur_api');
prind("loaded! Version: $VERSION");
