use Irssi;
use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use Data::Dumper;
use JSON;
use JSON::WebToken; 
use vars qw($VERSION %IRSSI);
use Data::Dumper;
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;


$VERSION = '2024-11-08';
%IRSSI = (
        authors     => 'LAama1',
        contact     => "LAama1 #kaaosleffat",
        name        => "Twitter-skripti",
        description => "Fetch info from twitter api",
        license     => "Fublic Domain",
        url         => "https://kaaos.radio",
        changed     => $VERSION
);

my $DEBUG = 0;

my $localdir = Irssi::get_irssi_dir() . '/scripts/irssi-scripts/';
my $bearer_token = KaaosRadioClass::readLastLineFromFilename($localdir . 'twitter_bearer_token.key');

my $url = 'https://api.twitter.com/2/tweets/';
my $ua = LWP::UserAgent->new;
my $headers = HTTP::Headers->new;
$headers->header('Authorization' => 'Bearer ' . $bearer_token);

sub sig_twitter {
    my ($server, $target, $id) = @_;
    prind("got signal: Target: $target, tweet-id: $id");
    my $twitter_url = $url . $id;
    my $jsondata = KaaosRadioClass::getJSON($twitter_url, $headers);
    if ($jsondata eq '-1') {
        $server->command("MSG $target 🐦 error..");
    } else {
        print Dumper($jsondata);
        $server->command("MSG $target 🐦 " . $jsondata->{data}->{text});
    }
}

sub prind {
	my ($text, @test) = @_;
	print("\0038" . $IRSSI{name} . ">\003 ". $text);
}

Irssi::signal_add('twitter_search_id', 'sig_twitter');