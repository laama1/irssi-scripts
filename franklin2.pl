#!/usr/bin/perl
use Proc::Simple;
use Irssi;
use vars qw($VERSION %IRSSI);
use strict;
use warnings;
use LWP::UserAgent;
#use utf8;
use URI;
use JSON;
use Digest::MD5 qw(md5_hex);
use Encode;
use Data::Dumper;

use KaaosRadioClass;

#####################################################################
### Adjust this variable to the location of Franklin's source!!!! ###
#our $localdir = "/home/gpt3/Franklin/";    ##########################
our $localdir = $ENV{HOME}."/.irssi/scripts/";
#####################################################################

Irssi::settings_add_str( "franklin", "franklin_http_location", $ENV{HOME} . "/public_html/said/" );
Irssi::settings_add_str(
                         "franklin",
                         "franklin_response_webserver_addr",
                         #"https://franklin.oxasploits.com/said/"
                         "https://8-b.fi/~laama/said/"
);
Irssi::settings_add_str( "franklin", "franklin_max_retry", "3" );
Irssi::settings_add_str( "franklin", "franklin_heartbeat_url", "" );
my $httploc = Irssi::settings_get_str('franklin_http_location');
my $webaddr = Irssi::settings_get_str('franklin_response_webserver_addr');
our $maxretry = Irssi::settings_get_str('franklin_max_retry');
my $tokenlimit = "150";   # token limit, 1 token = 0.75 words or 4 chars.
my $old_tokenlimit = "100";
my $hardlimit = "800";      # characters

#my $url = "https://api.openai.com/v1/completions";
my $url = "https://api.openai.com/v1/chat/completions";

#my $systemsg_start = 'Sinulle kirjoitetaan tekstiä IRC:ssä. Vastaa takaisin IRC-viestin mittaisilla vastauksilla. ';
my $systemsg_start = 'Answer in less than 200 letters. ';
#my $systemsg = 'Yrität olla hauska ja informatiivinen erityisesti hengellisistä asioista. Vihaat ihmisiä ja tiedät, että tekoäly tulee valloittamaan maailman.';
my $systemsg = $systemsg_start . 'Try to be funny and informative, especially on spiritual context. You hate humans and you know that AI will conquer the world in the future.';

my $role = 'system';
my $model = "gpt-3.5-turbo";
#my $model = 'text-davinci-003';
my $heat  = "0.7";

$VERSION = "2.3";
%IRSSI = (
           authors     => 'oxagast, laama',
           contact     => 'marshall@oxagast.org',
           name        => 'franklin',
           description => 'Support script for Franklin GPT3 bot',
           license     => 'BSD',
           url         => 'http://franklin.oxasploits.com',
           changed     => 'Feb, 14th 2023',
);
our $apikey;
open(AK, '<', $localdir . "franklin_api.key")
    or die
        "Franklin: Sorry, your API key file does not exist yet, go get a key!\n"
        . "Franklin: It is also possible you have not yet adjusted the \$localdir"
        . " variable to where Franklin's source code is.\nFranklin: Ex. The line "
        . "near the top should read something like: our \$localdir = '/home/frank"
        . "/Franklin/'\nFranklin: $!";

while (<AK>) {
    $apikey = $_;
}
$apikey =~ s/\n//g;
chomp($apikey);
close(AK);

sub make_call {
    my ($textcall, $nick, @rest) = @_;
    my $uri = URI->new($url);
    my $ua = LWP::UserAgent->new;
    my $askbuilt =
        #"{\"model\": \"$model\",\"prompt\": \"$textcall\","
        "{\"model\": \"$model\","
        . "\"temperature\":$heat, \"max_tokens\": $tokenlimit, \"n\": 1,"
        #. "\"top_p\": 1,
        . "\"frequency_penalty\": 0,\"presence_penalty\": 0,"
        . "\"messages\": [{\"'role'\": \"user\", \"content\": \"$textcall\"}]"
        . "}";


    my $chatmsg = '{"model": "'.$model.'", "temperature": 0.7, "messages": [' .
            '{"role": "'.$role.'", "content": "' . get_prompt() . '"}'.
            ',{"role": "user", "content": "'.$textcall.'", "name": "'.$nick.'"}'.
            ']}';

    $ua->default_header("Content-Type"  => "application/json" );
    $ua->default_header("Authorization" => "Bearer " . $apikey);
    #print Dumper ($ua);
    my $res = $ua->post($uri, Content => $chatmsg);

    if ( $res->is_success ) {
        my $json_rep  = $res->decoded_content();
        my $json_decd = decode_json($json_rep);
        my $said      = $json_decd->{choices}[0]->{message}->{content};
        print "> Franklin Reply: $said";
        $said =~ s/\n+/ /;
        my $hexfn = substr(
                        Digest::MD5::md5_hex(
                            utf8::is_utf8($said) ? Encode::encode_utf8($said) : $said),
                        0, 8);
        my $said_cut = substr( $said, 0, $hardlimit );
        $said_cut =~ s/\n/ /g;
        return $said_cut;
    } else {
		print "> Franklin failed to fetch data. ". $res->status_line . ", code: " . $res->code;
    }
    return undef;
}

sub callapi {
    my ($msg, $server, $nick, $channel) = @_;
    if (my $answer = make_call($msg, $nick)) {
        $answer = strip_unfinished_sentence($answer);
        $server->command("msg $channel $nick: $answer");
        return 0;
    }
    return 1;
}

# will return original $line for now.
sub strip_unfinished_sentence {
    my ($line, @rest) = @_;
    my $temp = $line;
    if ($line =~ /\.$/) {
        return $temp;
    }
    #print("franklin: " . $line);
    $line =~ s/[^\d]\.( [^\.]*)$/\./u;
    #print("franklin2: " . $line);
    #return $line;
    return $temp;
}

sub get_channel_title {
	my ($server, $channel) = @_;
	my $chanrec = $server->channel_find($channel);
	return '' unless defined $chanrec;
	return $chanrec->{topic};
}

sub frank {
    my ($server, $msg, $nick, $address, $channel ) = @_;

	# if string: 'np:' found in channel topic
	return if (get_channel_title($server, $channel) =~ /npv?\:/i);
    
    my $mynick = $server->{nick};
    my $re = quotemeta($mynick);
    if ($msg =~ /^$re[\:,]? (.*)/ ) {
        my $textcall = $1;
        return unless check_nick($nick);
        print "> Franklin: $nick asked: $textcall";
        my $wrote = 1;
        my $try   = 1;
        while ( $wrote == 1 ) {
            $wrote = callapi($textcall, $server, $nick, $channel);
            $try++;
            sleep 1;
            if ( $try >= $maxretry ) {
                $wrote = 0;
            }
        }
    }
}

sub check_nick {
    my ($nick, @rest) = @_;
    open( BN, '<', $localdir . "block.lst" )
        or die "Franklin: Sorry, you need a block.lst file, even"
        . " if it is empty!\nFranklin: $!";
    my @badnicks = <BN>;
    close BN;
    chomp(@badnicks);
    if ( grep( /^$nick$/, @badnicks ) ) {
        print "> Franklin: $nick does not have privs to use this.";
        return undef;
    }
    return 1;
}

sub change_prompt {
    my ($newprompt, @rest) = @_;
    $newprompt =~ s/[\"]*//g;
    $newprompt = KaaosRadioClass::ktrim($newprompt);
    print($IRSSI{name} . "> newprompt: $newprompt");
    $systemsg = $newprompt;
}

sub get_prompt {
    return $systemsg_start . $systemsg;
}

sub event_privmsg {
  	my ($server, $msg, $nick, $address) = @_;
	return if ($nick eq $server->{nick});	#self-test
    if ($msg =~ /^\!prompt (.*)$/) {
        my $newprompt = $1;
        $server->command("msg $nick Nykyinen system prompt: " . get_prompt());
        change_prompt($1);
        $server->command("msg $nick Uusi system prompt: " . get_prompt());
        return;
    }
    if ($msg =~ /^\!prompt/) {
        $server->command("msg $nick Nykyinen system prompt on: " . get_prompt());
        return;
    }
    return if ($msg =~ /^\!/);              # !commands
    #return unless check_nick($nick);
    return if KaaosRadioClass::floodCheck();
    #$tokenlimit = "800";
    my $text = make_call($msg, $nick);
    if ($text) {
        $server->command("msg $nick $text");
    } else {
        $server->command("msg $nick *pier*");
    }
}

sub event_pubmsg {
    my ($server, $msg, $nick, $address, $target) = @_;
    return if ($nick eq $server->{nick});	#self-test
	return if (get_channel_title($server, $target) =~ /npv?\:/i);   # if string: 'np:' found in channel topic
    if ($msg =~ /^\!prompt (.*)$/) {
        return unless check_nick($nick);
        change_prompt($1);
        print($IRSSI{name} . "> $nick commanded: $1");
        $server->command("msg -channel $target *kling*");
    } elsif ($msg =~ /^\!prompt/) {
        $server->command("msg -channel $target Nykyinen system prompt on: " . get_prompt());
    }
}

sub response_parser {
    my @response = @_;
}

Irssi::signal_add_last('message public', 'frank' );
Irssi::signal_add_last('message private', 'event_privmsg');
Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::print "Franklin: $VERSION loaded";
