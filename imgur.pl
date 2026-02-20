use Irssi;
use strict;
use warnings;
use LWP::UserAgent;
use Data::Dumper;
use JSON;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;		# LAama1 26.10.2016

$VERSION = '2026-02-18';
%IRSSI = (
        authors     => 'laama',
        contact     => "laama #irc-galleriaa",
        name        => "Imgur-API-script",
        description => "Fetch info from omdbapi or theimdbapi.org",
        license     => "Public Domain",
        url         => "http://8-b.fi",
        changed     => $VERSION
);

my $apiurl_image = "https://api.imgur.com/3/image/";
my $apiurl_gallery = "https://api.imgur.com/3/gallery/album/";

my $clientid = KaaosRadioClass::readLastLineFromFilename('imgur_client_id') || '';
my $h = HTTP::Headers->new;
$h->header('Accept-Encoding' => 'gzip,deflate,br', 'Authorization' => "Client-ID $clientid");

sub imgur_api  {
    my ($server, $target, $param, @rest) = @_;
	if ($param =~ /\:\/\/imgur\.com\/gallery\/.*-([\d\w\W]{2,8})$/) {
		# example: https://imgur.com/gallery/two-people-that-always-comment-on-nonsense-getting-notified-you-submitted-shitpost-tMMxzLa
		my $gallery = $1;
		prind("imgur-klick! gallery: $gallery");
		$apiurl_gallery .= $gallery;

		my $jsondata = KaaosRadioClass::getJSON($apiurl_gallery, $h);
		if ($jsondata eq '-1') {
			print "FAK gallery!";
			return 0;
		}
		my $gallery_id = $jsondata->{data}->{id} || '';
		my $title = $jsondata->{data}->{title} || '';
        $title .= ' ' if $title ne '';

		my $description = $jsondata->{data}->{description} || '';   # usually null
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

		$newUrlData->{title} = $title;
		$newUrlData->{desc} = '';
		return 1;
 	} elsif ($param =~ /\:\/\/imgur\.com\/a\/([\d\w\W]{2,8})$/) {
		# example: https://imgur.com/a/2nqjLZt
		my $album = $1;
		prind("imgur album klick! album: $album");
		my $apiurl = "https://api.imgur.com/3/album/" . $album;

		my $jsondata = KaaosRadioClass::getJSON($apiurl, $h);
		if ($jsondata eq '-1') {
			print "FAKa!";
			return 0;
		}
		my $id = $jsondata->{data}->{id} || '';
		my $title = $jsondata->{data}->{title} || '';
		$title .= ' ' if $title ne '';
		my $description = $jsondata->{data}->{description} || '';
		my $datetime = $jsondata->{data}->{datetime} || '';
		my $datetime_formatted = strftime('%Y-%m-%d %H:%M:%S', localtime($datetime)) if $datetime;
		my $views = $jsondata->{data}->{views} || '';
		$title = "Imgur album: ${title}[";
		if ($datetime_formatted) {
			$title .= "uploaded: $datetime_formatted";
		}
		if ($views) {
			$title .= " views: $views";
		}
		$title .= ']';
		$newUrlData->{title} = $title;
		$newUrlData->{desc} = '';
		return 1;
	} elsif ($param =~ /\:\/\/imgur\.com\/([\d\w\W]{2,8})/ || $param =~ /\:\/\/i\.imgur\.com\/([\d\w\W]{2,8})\.(jpg|png|gif|jpeg)/) {
		my $image = $1;
		prind("imgur direct image klick! img: $image");
		my $apiurl = "https://api.imgur.com/3/image/" . $image;

    	my $jsondata = KaaosRadioClass::getJSON($apiurl, $h);
		if ($jsondata eq '-1') {
			print "FAK!";
			return 0;
		}
		KaaosRadioClass::df(__LINE__ . ' urltitle imgurdata: ' . Dumper($jsondata));
		my $id = $jsondata->{data}->{id} || '';
		my $title = $jsondata->{data}->{title} || '';
		$title .= ' ' if $title ne '';
		my $width = $jsondata->{data}->{width} || '';
		my $height = $jsondata->{data}->{height} || '';
		my $size = $jsondata->{data}->{size} || '';
		my $views = $jsondata->{data}->{views} || '';
		my $datetime = $jsondata->{data}->{datetime} || '';
		my $datetime_formatted = strftime('%Y-%m-%d %H:%M:%S', localtime($datetime)) if $datetime;
		my $tags = $jsondata->{data}->{tags} || [];
			$tags = join(', ', @$tags);
			$tags = "Tags: ${tags}" if $tags ne '';
			$tags = '' if $tags eq '';

		$title .= "Imgur image: ${title}[${width}x${height}, " . sprintf("%.2f", $size / 1024) . "KiB";
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

		$newUrlData->{title} = $title;
		$newUrlData->{desc} = '';
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
prind($IRSSI{name} . " script loaded! Version: $VERSION");
Irssi::signal_add('imgur_api', 'sig_imgur_api');