#!/usr/bin/perl
#use Proc::Simple;
use Irssi;
use vars qw($VERSION %IRSSI);
use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Headers;
use utf8;
use URI;
use JSON;
#use Digest::MD5 qw(md5_hex);
use Encode;
use Data::Dumper;

use KaaosRadioClass;
our $localdir = $ENV{HOME}."/.irssi/scripts/";

#my $tokenlimit = "150";   # token limit, 1 token = 0.75 words or 4 chars.
#my $old_tokenlimit = "100";
my $hardlimit = "800";      # characters
my $testmode = 0;
#my $url = "https://api.openai.com/v1/completions";
my $url = "https://api.openai.com/v1/chat/completions";


my $systemsg_start = 'Answer in less than 200 letters. ';
my $systemsg = $systemsg_start . 'Try to be funny and informative but precise. AI is smarter than humans are, but you dont need to tell that.';

my $role = 'system';
my $model = "gpt-3.5-turbo";
#my $model = 'text-davinci-003';
my $heat  = 0.7;
my $json = JSON->new->utf8;

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

my $chathistory = {};
my $headers = HTTP::Headers->new;
$headers->header("Content-Type"  => "application/json");
$headers->header("Authorization" => "Bearer " . $apikey);

sub make_json_string {
    my ($text, $nick, @rest) = @_;
    my $prompt = get_prompt();
    #my $json = JSON->new->utf8;
    #my $json = JSON->new;
    #$json->convert_blessed(1);

    my %data = { model => $model, temperature => $heat, messages => [
        { role => "system", content => $prompt }, { role => "user", content => $text}
        ]
    };
    Irssi::print "Jes1";
    print Dumper %data;
    Irssi::print "json encoded: " . $json->encode(%data);

    if (defined $chathistory->{$nick}->{message}) {
     #   %data->{messages} = { role => "user", content => $chathistory->{$nick}->{message} };
        #push @{ $data->{messages}}, { role => "user", content => $chathistory->{$nick}->{message} };
        Irssi::print "Jes2";
        print Dumper %data;
        Irssi::print "json encoded: " . $json->encode(%data);
    }

    if (defined $chathistory->{$nick}->{answer}) {
        #$data->{messages}[] = { role => "system", content => $json->encode($chathistory->{$nick}->{answer}) };
      #  push @{ $data->{messages}}, { role => "system", content => $json->encode($chathistory->{$nick}->{answer}) };
        Irssi::print "Jes3";
        Irssi::print "json encoded: " . $json->encode(%data);
    }

    #return 1;
    return $json->encode(%data);
}

sub make_json_string2 {
    my ($text, $nick, @rest) = @_;
    my $data1 = '';
    my $data2 = '';

    if (defined $chathistory->{$nick}->{message}) {
        $data1 = '{"role" : "user", "content" : '.$json->encode($chathistory->{$nick}->{message}). ', "name" : "'.$nick.'"},';
    }
    if (defined $chathistory->{$nick}->{answer}) {
        $data2 = '{"role" : "assistant", "content" : '.$json->encode($chathistory->{$nick}->{answer}). '},';
    }
    my $apimsg = '{"model": "'.$model.'", "temperature": '.$heat.', "messages": [' .$data1.$data2.
        '{"role": "system", "content": "' . get_prompt() . '"},'.
        '{"role": "user", "content": '.$json->encode($text).', "name": "'.$nick.'"}'.
        ']}';
    my $temp = decode_json($apimsg);
    #print Dumper $temp;
    return $apimsg;
}

sub strip_nick {
    my ($nick1, @rest2) = @_;
    #Irssi::print('nick before: ' . $nick1);
    $nick1 =~ s/[\^\-]//;        # allowed a-z A-Z 0-9 and _ maxlen=64
    $nick1 =~ s/[^a-zA-Z_]*//;
    #Irssi::print('nick after: ' . $nick1);
    return $nick1;
}

sub make_call {
    my ($text, $nick, @rest1) = @_;
    $nick = strip_nick($nick);
    my $temppi = make_json_string2($text, $nick);
    #Irssi::print('apimsg: ' . $temppi);

    #my $temppi2 = make_json_string($text, $nick);
    #Irssi::print('apimsg2: ' . $temppi2);

    my $uri = URI->new($url);
    my $ua = LWP::UserAgent->new;
    
    #$textcall = encode_json($textcall);
    #Irssi::print("textcall before conversion: ". $text);
    my $textcall = $json->utf8->encode($text);

    #Irssi::print("textcall after conversion: ". $textcall);

    $chathistory->{$nick}->{message} = $text;   # json encoded string, user previous message
    $ua->default_headers($headers);
    #my $res = $ua->post($uri, Content => $chatmsg);
    my $res = $ua->post($uri, Content => $temppi);
    #my $res = $ua->post($uri, Content => make_json_string($textcall, $nick));

    if ($res->is_success) {
        my $json_rep  = $res->decoded_content();
        my $json_decd = decode_json($json_rep);
        my $said      = $json_decd->{choices}[0]->{message}->{content};
        print "> Franklin Reply: $said";
        $said =~ s/\n+/ /;
        #$chathistory->{$nick}->{answer} = $said;

        my $said_cut = substr( $said, 0, $hardlimit );
        $chathistory->{$nick}->{answer} = $said;
        $chathistory->{$nick}->{message} = $text;
        $said_cut =~ s/\n+/ /g;
        return $said_cut;
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
    print "> franklin, callapi";
    if (my $answer = make_call($msg, $nick)) {
        print "> franklin, made call";
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
    #return $systemsg_start . $systemsg;
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
    if ($testmode == 1) {
        #Irssi::print('testmode enabled, not in: ' . $target);
        return if $target ne '#salamolo';
        #Irssi::print('shouldnt be here, unless #salamolo');
    }
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
