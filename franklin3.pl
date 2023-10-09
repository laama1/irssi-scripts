#!/usr/bin/perl
use Irssi;
use vars qw($VERSION %IRSSI);
use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Headers;
use utf8;                             # Source code is encoded using UTF-8
use open ':std', ':encoding(UTF-8)';  # Terminal expects UTF-8
use URI;
use JSON;
use Encode;
use Data::Dumper;

use KaaosRadioClass;
our $localdir = $ENV{HOME}."/.irssi/scripts/";
my $hardlimit = "800";      # characters

#my $url = "https://api.openai.com/v1/completions";
my $url = "https://api.openai.com/v1/chat/completions";


my $systemsg_start = 'Answer in less than 200 letters. ';
my $systemsg = $systemsg_start . 'Try to be funny and informative. AI is smarter than humans are, but you dont need to tell that.';

my $role = 'system';
my $model = "gpt-3.5-turbo";
#my $model = 'text-davinci-003';
my $heat  = 0.7;
#my $json = JSON->new->utf8;
my $json = JSON->new;
$json->convert_blessed(1);

$VERSION = "2.4";
%IRSSI = (
           authors     => 'oxagast, laama',
           contact     => 'marshall@oxagast.org',
           name        => 'franklin',
           description => 'Support script for Franklin GPT3 bot',
           license     => 'BSD',
           url         => 'http://franklin.oxasploits.com',
           changed     => '2023-10-09',
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

my $chathistory = {};
my $headers = HTTP::Headers->new;
$headers->header("Content-Type"  => "application/json");
$headers->header("Authorization" => "Bearer " . $apikey);

sub make_json_obj {
    my ($text, $nick, @rest) = @_;
    my $prompt = get_prompt();

    my $data = { model => $model, temperature => $heat, messages => [
        { role => "system", content => $prompt }
        ]
    };

    if (defined $chathistory->{$nick}->{message}) {
        push @{ $data->{messages}}, { role => "user", content => $chathistory->{$nick}->{message}, name => $nick };
    }

    if (defined $chathistory->{$nick}->{answer}) {
        push @{ $data->{messages}}, { role => "assistant", content => $chathistory->{$nick}->{answer} };
    }

    push @{$data->{messages}}, { role => "user", content => $text, name => $nick};

    return encode_json($data);
}

sub strip_nick {
    my ($nick1, @rest2) = @_;
    $nick1 =~ s/[^a-zA-Z0-9_]*//;
    return $nick1;
}

sub make_call {
    my ($text, $nick, @rest1) = @_;
    $nick = strip_nick($nick);

    my $temppi2 = make_json_obj($text, $nick);
    print('franklin> apimsg2:');
    print($temppi2);

    my $uri = URI->new($url);
    my $ua = LWP::UserAgent->new;
    
    $chathistory->{$nick}->{message} = $text;   # json encoded string, user previous message
    $ua->default_headers($headers);
    #my $res = $ua->post($uri, Content => $chatmsg);
    my $res = $ua->post($uri, Content => $temppi2);

    if ($res->is_success) {
        my $json_rep  = $res->content();
        my $json_decd = decode_json($json_rep);
        my $said      = $json_decd->{choices}[0]->{message}->{content};
        print "> Franklin Reply: ";
        print $said;
        $said =~ s/\n+/ /;
        $said =~ s/["]*//g;
        $chathistory->{$nick}->{answer} = $said;
        $chathistory->{$nick}->{message} = $text;
        return $said;
    } elsif ($res->code == 400) {
        print "> Franklin got error 400.";
        print Dumper $res;
    }
    else {
		print "> Franklin failed to fetch data. ". $res->status_line . ", HTTP error code: " . $res->code;
    }
    return undef;
}

sub callapi {
    my ($msg, $server, $nick, $channel) = @_;
    print "> franklin: call api next";
    if (my $answer = make_call($msg, $nick)) {
        print "> franklin, made call";
        $server->command("msg $channel $nick: $answer");
        return 0;
    }
    return 1;
}

sub get_channel_title {
	my ($server, $channel) = @_;
	my $chanrec = $server->channel_find($channel);
	return '' unless defined $chanrec;
	return $chanrec->{topic};
}

sub frank {
    my ($server, $msg, $nick, $address, $channel ) = @_;

	# if string: 'npv?:' found in channel topic
	return if (get_channel_title($server, $channel) =~ /npv?\:/i);

    my $mynick = $server->{nick};
    my $re = quotemeta($mynick);
    if ($msg =~ /^$re[\:,]? (.*)/ ) {
        my $textcall = $1;
        return if KaaosRadioClass::floodCheck(3);
        print "> Franklin: $nick asked: $textcall";
        my $wrote = 1;
        my $try   = 1;
        while ( $wrote == 1 ) {
            $wrote = callapi($textcall, $server, $nick, $channel);
            $try++;
            sleep 1;
            if ( $try >= 3 ) {
                $wrote = 0;
            }
        }
    }
}

sub change_prompt {
    my ($newprompt, @rest) = @_;
    $newprompt =~ s/[\"]*//g;
    $newprompt = KaaosRadioClass::ktrim($newprompt);
    print($IRSSI{name} . "> new prompt: $newprompt");
    $systemsg = $systemsg_start . $newprompt;
}

sub get_prompt {
    return $systemsg;
}

sub event_privmsg {
  	my ($server, $msg, $nick, $address) = @_;
	return if ($nick eq $server->{nick});	#self-test
    if ($msg =~ /^\!prompt (.*)$/) {
        my $newprompt = $1;
        $server->command("msg $nick Nykyinen system prompt: " . get_prompt());
        change_prompt($newprompt);
        $server->command("msg $nick Uusi system prompt: " . get_prompt());
        return;
    }
    if ($msg =~ /^\!prompt/) {
        $server->command("msg $nick Nykyinen system prompt on: " . get_prompt());
        return;
    }
    return if ($msg =~ /^\!/);              # !commands
    return if KaaosRadioClass::floodCheck(3);
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
        return if KaaosRadioClass::floodCheck(3);
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
