use Irssi;
use strict;
use warnings;
use utf8;

use HTTP::Headers;
use Data::Dumper;

use vars qw($VERSION %IRSSI);

use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;


$VERSION = '2025-11-23';
%IRSSI = (
        authors     => 'LAama1',
        contact     => "LAama1 #kaaosradio",
        name        => "twitter.pl",
        description => "Fetch info from twitter api",
        license     => "Fublic Domain",
        url         => "https://kaaos.radio",
        changed     => $VERSION
);

# nitter instances: https://github.com/zedeus/nitter/wiki/Instances
# nitter.42l.fr nitter.pussthecat.org nitter.eu nitter.net nitter.dark.fail nitter.cattube.org nitter.actionsack.com
# nitter.mailstation.de nitter.namazso.eu nitter.himiko.cloud nitter.domain.glass nitter.unixfox.eu

my $localdir = Irssi::get_irssi_dir() . '/scripts/irssi-scripts/';
my $bearer_token = KaaosRadioClass::readLastLineFromFilename($localdir . 'twitter_bearer_token.key');

my $url = 'https://api.twitter.com/2/tweets/';
my $headers = HTTP::Headers->new;
$headers->header('Authorization' => 'Bearer ' . $bearer_token);

sub sig_twitter {
    my ($server, $target, $id) = @_;
    prind("got signal: Target: $target, tweet-id: $id");
    return unless KaaosRadioClass::is_enabled_channel('urltitle_enabled_channels', $server->{chatnet}, $target);

    my $twitter_url = $url . $id;
    my $jsondata = KaaosRadioClass::getJSON($twitter_url, $headers);
    if ($jsondata eq '-1') {
        #$server->command("MSG $target 🐦 error..");
    } else {
        print Dumper($jsondata);
        $server->command("MSG $target 🐦 " . $jsondata->{data}->{text});
    }
}

sub prind {
	my ($text, @test) = @_;
	print("\0038" . $IRSSI{name} . ">\003 ". $text);
}

prind("v. $VERSION loaded.");
Irssi::signal_add('twitter_search_id', 'sig_twitter');