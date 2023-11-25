#!/usr/bin/perl
use Irssi;
use vars qw($VERSION %IRSSI);
use strict;
use warnings;
use LWP::UserAgent;
use LWP::Simple;
use HTTP::Headers;
use utf8;                             # Source code is encoded using UTF-8
use open ':std', ':encoding(UTF-8)';  # Terminal expects UTF-8
use URI;
use JSON;
use Encode;
use MIME::Base64;
use Data::Dumper;

use KaaosRadioClass;
our $localdir = $ENV{HOME}."/.irssi/scripts/";

#my $apiurl = "https://api.openai.com/v1/completions";
my $apiurl = 'https://api.openai.com/v1/chat/completions';
my $dalleurl = 'https://api.openai.com/v1/images/generations';
my $howMany = 2;        # how many images we want to generate
my $uri = URI->new($apiurl);
my $duri = URI->new($dalleurl);

my $systemsg_start = 'Answer in less than 200 letters. ';
#my $systemsg = $systemsg_start . 'Try to be funny and informative. AI is smarter than humans are, but you dont need to tell that.';
my $systemsg = $systemsg_start;
my $role = 'system';
my $model = "gpt-3.5-turbo";
#my $model = 'text-davinci-003';
my $heat  = 0.7;

#my $json = JSON->new->utf8;
my $json = JSON->new;
$json->convert_blessed(1);

$VERSION = "2.5";
%IRSSI = (
    authors     => 'oxagast, laama',
    contact     => 'laama@8-b.fi',
    name        => 'Franklin',
    description => 'OpenAI chatgpt api script',
    license     => 'BSD',
    url         => 'https://bot.8-b.fi',
    changed     => '2023-10-11',
);
our $apikey;
open(AK, '<', $localdir . "franklin_api.key") or die $IRSSI{name}."> could not read API-key: $!";
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

my $ua = LWP::UserAgent->new;
$ua->default_headers($headers);

sub make_json_obj2 {
    my ($text, $nick, @rest) = @_;
    my $prompt = get_prompt();
    my $data = { model => $model, temperature => $heat, messages => [
            { role => "system", content => $prompt }
        ]
    };
    print __LINE__;
    if (defined $chathistory->{$nick}->{id}) {
        print __LINE__;
        push @{$data->{messages}}, { role => "user", content => $text, name => $nick, id => $chathistory->{$nick}->{id}};
    } else {
        push @{$data->{messages}}, { role => "user", content => $text, name => $nick};
    }
    
    return encode_json($data);
}


sub make_json_obj {
    my ($text, $nick, @rest) = @_;
    print "nick: " . $nick;
    my $prompt = get_prompt();
    my $timediff = 3600;    # 1h in seconds

    defined $chathistory->{$nick}->{timestamp} && 
        $timediff = (time - $chathistory->{$nick}->{timestamp});

    my $data = { model => $model, temperature => $heat, messages => [
            { role => "system", content => $prompt }
        ]
    };

    if ($timediff < 3600) {
        defined $chathistory->{$nick}->{message} && 
            push @{ $data->{messages}}, { role => "user", content => $chathistory->{$nick}->{message}, name => $nick };
        defined $chathistory->{$nick}->{answer} && 
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

    my $request = make_json_obj($text, $nick);
    print $IRSSI{name}.' JSON request>';
    print $request;

    my $res = $ua->post($uri, Content => $request);

    if ($res->is_success) {
        my $json_rep  = $res->content();
        my $json_decd = decode_json($json_rep);
        print __LINE__;
        print Dumper $json_decd;
        print Dumper $json_decd->{usage};
        my $said      = $json_decd->{choices}[0]->{message}->{content};
        print $IRSSI{name}." reply> " . $said;
        $said =~ s/\n+/ /;
        $said =~ s/\s{2,}//g;
        $said =~ s/```//g;
        #$said =~ s/["]*//g;
        $chathistory->{$nick}->{answer} = $said;
        $chathistory->{$nick}->{message} = $text;
        $chathistory->{$nick}->{timestamp} = time;
        $chathistory->{$nick}->{chatid} = $json_decd->{id};
        $chathistory->{$nick}->{floodcount} += 1;
        return $said;
    } elsif ($res->code == 400) {
        print $IRSSI{name}."> got error 400.";
        #print Dumper $res;
    } else {
		print $IRSSI{name}."> failed to fetch data. ". $res->status_line . ", HTTP error code: " . $res->code;
    }
    return undef;
}

sub get_channel_title {
	my ($server, $channel) = @_;
	my $chanrec = $server->channel_find($channel);
	return '' unless defined $chanrec;
	return $chanrec->{topic};
}

sub frank {
    my ($server, $msg, $nick, $address, $channel ) = @_;
    return if $nick eq $server->{nick};	#self-test
	# if string 'npv?:' found in channel topic. np: or npv:
	# removed 2023-11-01 return if (get_channel_title($server, $channel) =~ /npv?\:/i);

    my $mynick = quotemeta $server->{nick};
    if ($msg =~ /^$mynick[\:,]? (.*)/ ) {
        my $textcall = $1;
        return if KaaosRadioClass::floodCheck(3);
        print $IRSSI{name}."> $nick asked: $textcall";
        my $wrote = 1;
        for (my $i = 0; $i < 2; $i++) {
            # @todo fork or something
            if (my $answer = make_call($textcall, $nick)) {
                $server->command("msg -channel $channel $nick: $answer");
                last;
            }
            sleep 1;
        }
    }
}

sub make_dalle_json {
    my ($prompt, $nick) = @_;
    my $data = {prompt => $prompt, n => $howMany, size => "512x512", response_format => "b64_json"};
    return encode_json($data);
}

sub make_vision_json {
    
}

sub dalle {
    my ($server, $msg, $nick, $address, $channel ) = @_;
    return if $nick eq $server->{nick};	#self-test
	# if string 'npv?:' found in channel topic. np: or npv:
	# removed 2023-11-01 return if (get_channel_title($server, $channel) =~ /npv?\:/i);
    #my $mynick = quotemeta $server->{nick};
    if ($msg =~ /^!dalle (.*)/ ) {
        my $query = $1;
        #print $IRSSI{name}.'> dalle query: ' . $query);

        my $request = make_dalle_json($query, $nick);
        print('request dalle json: ' . $request);
        
        # @todo fork or something
        my $res = $ua->post($duri, Content => $request);

        if ($res->is_success) {
            my $json_rep  = $res->content();
            my $json_decd = decode_json($json_rep);
            print "dalle request success!";
            #print __LINE__;
            #print Dumper $res;
            
            if (defined $json_decd->{data}) {
                #print "url1: " . $json_decd->{data}[0]->{url};
                my $time = time;
                my $answer = 'DALL-e results: ';
                my $index = 0;
                while ($index < $howMany) {
                    my $filename = $nick.'_'.$time.'_'.$index.'.png';
                    if (save_file_blob($json_decd->{data}[$index]->{b64_json}, $filename) >= 0) {
                        #$server->command("msg -channel $channel $nick: https://bot.8-b.fi/dale/$filename");
                        $answer .= "https://bot.8-b.fi/dale/$filename ";
                    }
                    $index++;
                }
                $server->command("msg -channel $channel $answer");
                my $filename = $nick.'_'.$time.'.png';
            }
        } elsif ($res->is_error) {
            print "ERROR!";
            my $errormsg = decode_json($res->decoded_content())->{error}->{message};
            $server->command("msg -channel $channel $nick: $errormsg");
        } else {
		    print $IRSSI{name}."> failed to fetch data. ". $res->status_line . ", HTTP error code: " . $res->code;
            print Dumper $res;
        }

    }
}

sub save_file_blob {
    my ($blob, $filename, @rest) = @_;
    my $outputdir = '/var/www/html/bot/dale/';

	open (OUTPUT, '>', $outputdir.$filename) || die $!;
    binmode OUTPUT;
	print OUTPUT decode_base64($blob);
	close OUTPUT || return -2;
    return 1;
}

sub change_prompt {
    my ($newprompt, @rest) = @_;
    $newprompt =~ s/[\"]*//g;
    $newprompt = KaaosRadioClass::ktrim($newprompt);
    $systemsg = $systemsg_start . $newprompt;
    print($IRSSI{name} . "> new prompt: $systemsg");
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
    return if ($msg =~ /^\!/);              # other !commands
    return if KaaosRadioClass::floodCheck(3);
    if (my $text = make_call($msg, $nick)) {
        $server->command("msg $nick $text");
    } else {
        $server->command("msg $nick *pier*");
    }
}

sub event_pubmsg {
    my ($server, $msg, $nick, $address, $target) = @_;
    return if ($nick eq $server->{nick});	#self-test
	# removed 2023-11-01 return if (get_channel_title($server, $target) =~ /npv?\:/i);   # if string: 'np:' found in channel topic

    if ($msg =~ /^\!prompt (.*)$/) {
        return if KaaosRadioClass::floodCheck(3);
        change_prompt($1);
        print($IRSSI{name} . "> $nick commanded: $1");
        $server->command("msg -channel $target *kling*");
    } elsif ($msg =~ /^\!prompt/) {
        $server->command("msg -channel $target Nykyinen system prompt on: " . get_prompt());
    }
}

sub save_settings {
    #Irssi::
    return;
}

Irssi::signal_add_last('message public', 'frank' );
Irssi::signal_add_last('message public', 'dalle' );
Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::signal_add_last('message private', 'event_privmsg');
#Irssi::signal_add_last('setup saved', 'save_settings');
Irssi::settings_add_str($IRSSI{name}, 'franklin_prompt', $systemsg);
print $IRSSI{name}."> v.$VERSION loaded";
