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
use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;
our $localdir = $ENV{HOME}."/.irssi/scripts/";

#my $apiurl = "https://api.openai.com/v1/completions";
my $apiurl = 'https://api.openai.com/v1/chat/completions';
my $dalleurl = 'https://api.openai.com/v1/images/generations';
my $speechurl = 'https://api.openai.com/v1/audio/speech';
my $howMany = 2;        # how many images we want to generate
my $uri = URI->new($apiurl);
my $duri = URI->new($dalleurl);

my $DEBUG = 1;

my $systemsg_start = 'Answer at most in 40 words. ';
#my $systemsg = $systemsg_start . 'Try to be funny and informative. AI is smarter than humans are, but you dont need to tell that.';
my $systemsg = $systemsg_start;
my $role = 'system';
#my $model = "gpt-3.5-turbo";
#my $model = 'gpt-4-turbo-preview';
#my $model = 'text-davinci-003';
my $model = 'gpt-4o-mini';
my $visionmodel = 'gpt-4-vision-preview';
my $heat  = 0.4;
my $hardlimit = 500;
my $timediff = 3600;    # 1h in seconds. length of lastlog history
#my $json = JSON->new->utf8;
my $json = JSON->new;
$json->convert_blessed(1);

$VERSION = "2.6";
%IRSSI = (
    authors     => 'laama',
    contact     => 'laama@8-b.fi',
    name        => 'Franklin',
    description => 'OpenAI chatgpt api script',
    license     => 'BSD',
    url         => 'https://bot.8-b.fi',
    changed     => '2024-02-13',
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

sub make_json_obj_f {
    my ($text, $nick, @rest) = @_;

    my $prompt = get_prompt();
    $timediff = 3600;    # 1h in seconds

    if (defined $chathistory->{$nick}->{timestamp}) {
        $timediff = (time - $chathistory->{$nick}->{timestamp});
    }
    my $data = { model => $model, temperature => $heat, presence_penalty => -1.0, messages => [
            { role => 'system', content => $prompt, name => 'KD_Bat' }
        ]
    };

    if ($timediff < 3600 && defined $chathistory->{$nick}->{history}) {
        foreach my $history ($chathistory->{$nick}->{history}) {
            foreach my $unit (@$history) {
                push @{ $data->{messages}}, { role => 'user', content => $unit->{message}, name => $nick };
                push @{ $data->{messages}}, { role => 'assistant', content => $unit->{answer} };
            }
        }
    } else {
        undef $chathistory->{$nick}->{history};
        $chathistory->{$nick}->{floodcount} = 0;
    }

    push @{ $data->{messages}}, { role => 'user', content => $text, name => $nick};
    return encode_json($data);
}

sub make_json_obj_f2 {
    my ($text, $nick, $channel, @rest) = @_;

    my $prompt = get_prompt();
    $timediff = 3600;    # 1h in seconds

    my $data = { model => $model, temperature => $heat, presence_penalty => -1.0, messages => [
            { role => 'system', content => $prompt, name => 'KD_Bat' }
        ]
    };
    my $maxcount = 0;
    if (defined $chathistory->{$channel}) {

        #my @timestamps = sort { $a <=> $b } keys %$chathistory;
        my @timestamps = sort { $a <=> $b } keys %{ $chathistory->{$channel} };

        #foreach my $history (%$chathistory) {
        foreach my $history (@timestamps) {
            prindd(__LINE__ . ', history (Timestamp):');
            print Dumper $chathistory->{$channel}->{$history} if $DEBUG;

            if (defined $chathistory->{$channel}->{$history}) {
                push @{ $data->{messages}}, { role => 'user', content => $chathistory->{$channel}->{$history}->{message}, name => $chathistory->{$channel}->{$history}->{nick} } ;
                push @{ $data->{messages}}, { role => 'assistant', content => $chathistory->{$channel}->{$history}->{answer}, name => $chathistory->{$channel}->{$history}->{nick} };
            }
            $maxcount++;
        }
    }

    push @{ $data->{messages}}, { role => "user", content => $text, name => $nick};
    prindd(__LINE__ . ' data->messages: ');
    print Dumper $data->{messages} if $DEBUG;
    return encode_json($data);
}

sub strip_nick {
    my ($nick1, @rest2) = @_;
    $nick1 =~ s/[^a-zA-Z0-9_]*//ug;
    $nick1 =~ s/[\[\]]*//ug;
    return $nick1;
}

sub make_call {
    my ($text, $nick, @rest1) = @_;
    $nick = strip_nick($nick);
    #print $IRSSI{name}." nick: $nick";
    my $request = make_json_obj_f($text, $nick);
    print $IRSSI{name}.' JSON request>' if $DEBUG;
    print $request if $DEBUG;

    my $res = $ua->post($uri, Content => $request);

    if ($res->is_success) {
        my $json_rep  = $res->content();
        my $json_decd = decode_json($json_rep);
        print __LINE__ if $DEBUG;
        print Dumper $json_decd if $DEBUG;
        #print Dumper $json_decd->{usage};
        my $answered = $json_decd->{choices}[0]->{message}->{content};
        prind("reply: " . $answered);
        $answered =~ s/\n+/ /ug;
        $answered =~ s/\s{2,}//ug;
        $answered =~ s/```//ug;

        if (!defined $chathistory->{$nick}->{history}) {
            print $IRSSI{name}."> zig zag" if $DEBUG;
            # HACK BUGFIX
            #$chathistory->{$nick}->{history} = {};
            prindd(__LINE__);
        }
        prindd(__LINE__);
        print Dumper $chathistory->{$nick} if $DEBUG;

        #push @{ $chathistory->{$nick}}, {message => $text};
        $chathistory->{$nick}->{timestamp} = time;
        $chathistory->{$nick}->{chatid} = $json_decd->{id};    # ?? what is id even, does it work anymore
        $chathistory->{$nick}->{floodcount} += 1;
        push @{ $chathistory->{$nick}->{history}}, { answer => $answered, message => $text };
        return $answered;
    } elsif ($res->code == 400) {
        prindw("got error 400.");
        print Dumper $res->{error} if $DEBUG;
    } else {
		prindw("failed to fetch data. ". $res->status_line . ", HTTP error code: " . $res->code);
    }
    return undef;
}

sub make_call2 {
    my ($text, $nick, $channel, @rest1) = @_;
    my $timestamp = time;
    $nick = strip_nick($nick);
    #print $IRSSI{name}." nick: $nick";
    my $request = make_json_obj_f2($text, $nick, $channel);
    print __LINE__ . ' JSON request>' if $DEBUG;
    print $request if $DEBUG;

    my $res = $ua->post($uri, Content => $request);

    if ($res->is_success) {
        my $json_rep  = $res->content();
        my $json_decd = decode_json($json_rep);
        print __LINE__ . 'response json decoded: ' if $DEBUG;
        print Dumper $json_decd if $DEBUG;
        #print Dumper $json_decd->{usage};
        my $answered = $json_decd->{choices}[0]->{message}->{content};
        prind("reply: " . $answered);
        $answered =~ s/\n+/ /ug;
        $answered =~ s/\s{2,}//ug;
        $answered =~ s/```//ug;

        $chathistory->{$channel}->{$timestamp}->{nick} = $nick;
        $chathistory->{$channel}->{$timestamp}->{answer} = $answered;
        $chathistory->{$channel}->{$timestamp}->{message} = $text;

        # Ensure we only keep the latest 5 entries
        my @timestamps = sort { $a <=> $b } keys %{$chathistory->{$channel}};
        if (@timestamps > 5) {
            my $oldest_timestamp = shift @timestamps;
            delete $chathistory->{$channel}->{$oldest_timestamp};
        }
        return $answered;
    } elsif ($res->code == 400) {
        prindw("got error 400.");
        print Dumper $res->{error} if $DEBUG;
    } else {
		prindw("failed to fetch data. ". $res->status_line . ", HTTP error code: " . $res->code);
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
    my $mynick = quotemeta $server->{nick};
    return if $nick eq $mynick; #self-test

    if ($msg =~ /^$mynick[\:,]? (.*)/ug ) {
        my $textcall = $1;
        prind("textcall: $textcall") if $DEBUG;
        return if KaaosRadioClass::floodCheck(3);
        prind('passed floodcheck') if $DEBUG;
        return if KaaosRadioClass::Drunk($nick);
        prind('passed drunktest like a mf') if $DEBUG;
        prind("$nick asked: $textcall");
        #my $wrote = 1;

        # @todo fork or something
        for (0..2) {
        #for (0..1) {
            #if (my $answer = make_call($textcall, $nick)) {
            if (my $answer = make_call2($textcall, $nick, $channel)) {
                #$chathistory->{$nick}->{timestamp} = time;
                my $answer_cut = substr($answer, 0, $hardlimit);
                $server->command("msg -channel $channel $nick: $answer_cut");
                last;
            }
            # retry
            sleep 1;
        }
    }
}

sub make_dalle_json {
    my ($prompt, $nick) = @_;
    my $data = {prompt => $prompt, n => $howMany, size => "640x640", response_format => "b64_json"};
    return encode_json($data);
}

sub make_vision_json {
    my ($prompt, $nick) = @_;
    my $data = {prompt => $prompt, n => $howMany, size => "1024x1024", response_format => "b64_json"}; # dall-e-3 minimum size
    return encode_json($data); 
}

sub make_vision_preview_json {
    my ($url, $searchprompt, @rest) = @_;
    if ($searchprompt eq '') {
        $searchprompt = 'Describe this image?';
    }
    prind("search url: $url");
    prind("search prompt for vision: $searchprompt");
    #my $data = { model => $visionmodel, max_tokens => 300, messages => [{
    my $data = { model => $model, max_tokens => 150, messages => [{
        role => "user",
        content => [
            {type => "text", text => $searchprompt},
            {type => "image_url", image_url => {url => $url}}
            #{image_url => {url => $url}}
        ]
    }], max_tokens => 300,
    };
    return encode_json($data);
}

sub tts {
    my ($server, $msg, $nick, $address, $channel ) = @_;
    my $mynick = quotemeta $server->{nick};
    return if $nick eq $mynick;	#self-test
    if ($msg =~ /^!tts (.*)/u ) {
        my $query = $1;
        my $data = { model => "tts-1", voice => "alloy", input => $query, response_format => "mp3"};
        my $request = encode_json($data);
        #print __LINE__ . ' request:' if $DEBUG;
        #xprint Dumper $request if $DEBUG;
        my $res = $ua->post($speechurl, Content => $request);
        if ($res->is_success) {
            #print __LINE__ . ' response success' if $DEBUG;
            #print Dumper $res if $DEBUG;
            #my $data = $res->decoded_content();
            my $data = $res->content;
            my $time = time;
            my $index = 0;
            my $answer = 'TTS results: ' .length($data). ' bytes, ';
            my $filename = $nick . '_' . $time . '_' . $index.'.mp3';
            if (save_file_blob($data, $filename) >= 0) {
                $answer .= "https://bot.8-b.fi/dale/$filename ";
            }
            #print __LINE__ . ' answer: '.$answer.', data:' if $DEBUG;
            #print Dumper ($data) if $DEBUG;
            $server->command("msg -channel $channel $answer");
        } else {
            prindd(__LINE__ . ' failed to fetch data. '. $res->status_line . ', HTTP error code: ' . $res->code);
            print Dumper $res if $DEBUG;
        }
    }

}

sub dalle {
    my ($server, $msg, $nick, $address, $channel ) = @_;
    my $mynick = quotemeta $server->{nick};
    return if $nick eq $mynick;	#self-test
    $nick = strip_nick($nick);

    if ($msg =~ /!dalle (https?\:\/\/[^ ]+)(.*)/ui ) {
        # image guessing 2024-02-13
        my $imagesearchurl = $1;
        my $question = $2;
        my $request = make_vision_preview_json($imagesearchurl, $question);

        # @todo fork or something
        my $res = $ua->post($uri, Content => $request);
        if ($res->is_success) {
            my $json_rep  = $res->content();
            my $json_decd = decode_json($json_rep);
            my $answer = '';
            if (defined $json_decd->{choices}[0]->{message}->{content}) {
                $answer = $json_decd->{choices}[0]->{message}->{content};
                $server->command("msg -channel $channel $answer");
            }
        } elsif ($res->is_error) {
            my $errormsg = decode_json($res->decoded_content())->{error}->{message};
            prindw("Error: $errormsg");
            $server->command("msg -channel $channel $nick: \0035Error:\003 $errormsg");
        } else {
		    prindw("failed to fetch data. ". $res->status_line . ", HTTP error code: " . $res->code);
        }
        prindd(__LINE__ . ' response:');
        print Dumper $res if $DEBUG;
    } elsif ($msg =~ /^!dalle (.*)/u ) {
        my $query = $1;
        #my $request = make_dalle_json($query, $nick);
        my $request = make_vision_json($query, $nick);
        #print('request vision dalle json: ' . $request) if $DEBUG;

        # @todo fork or something
        my $res = $ua->post($duri, Content => $request);

        if ($res->is_success) {
            my $json_rep  = $res->content();
            my $json_decd = decode_json($json_rep);
            
            if (defined $json_decd->{data}) {
                my $time = time;
                my $answer = 'DALL-e results: ';
                my $index = 0;
                while ($index < $howMany) {
                    my $filename = $nick.'_'.$time.'_'.$index.'.png';
                    if (save_file_blob(decode_base64($json_decd->{data}[$index]->{b64_json}), $filename) >= 0) {
                        $answer .= "https://bot.8-b.fi/dale/$filename ";
                    }
                    $index++;
                }
                $server->command("msg -channel $channel $answer");
                #my $filename = $nick.'_'.$time.'.png';
            }
        } elsif ($res->is_error) {
            #print "ERROR!" if $DEBUG;
            my $errormsg = decode_json($res->decoded_content())->{error}->{message};
            $server->command("msg -channel $channel $nick: \0035Error:\003 $errormsg");
            prindw("Error: $errormsg");
        } else {
		    prindw("failed to fetch data. ". $res->status_line . ", HTTP error code: " . $res->code);
        }
        #prindd(__LINE__ . ' :');
        #print Dumper $res if $DEBUG;
    }
}

sub save_file_blob {
    my ($blob, $filename, @rest) = @_;
    my $outputdir = '/var/www/html/bot/dale/';

	open (OUTPUT, '>', $outputdir.$filename) || die $!;
    binmode OUTPUT;
	#print OUTPUT decode_base64($blob);
    print OUTPUT $blob;
	close OUTPUT || return -2;
    return 1;
}

sub change_prompt {
    my ($newprompt, @rest) = @_;
    $newprompt =~ s/[\"]*//ug;
    $newprompt = KaaosRadioClass::ktrim($newprompt);
    $systemsg = $systemsg_start . $newprompt;
    prind("new prompt: $systemsg");
}

sub get_prompt {
    return $systemsg;
}

sub event_privmsg {
  	my ($server, $msg, $nick, $address) = @_;
    my $mynick = quotemeta $server->{nick};
	return if ($nick eq $mynick);	#self-test
    if ($msg =~ /^\!prompt (.*)$/) {
        my $newprompt = KaaosRadioClass::ktrim($1);
        if (length $newprompt > 1) {
            $server->command("msg $nick Nykyinen system prompt: " . get_prompt());
            change_prompt($newprompt);
            $server->command("msg $nick Uusi system prompt: " . get_prompt());
        } else {
            $server->command("msg $nick Nykyinen system prompt on: " . get_prompt());
        }

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
    my $mynick = quotemeta $server->{nick};
    return if ($nick eq $mynick);	#self-test

    if ($msg =~ /^\!prompt (.*)$/) {
        my $newprompt = KaaosRadioClass::ktrim($1);
        if (length $newprompt > 1) {
            return if KaaosRadioClass::floodCheck(3);
            return if KaaosRadioClass::Drunk($nick);
            change_prompt($newprompt);
            prind("$nick commanded: $1");
            $server->command("msg -channel $target *kling*");
        }
    } elsif ($msg =~ /^\!prompt/) {
        $server->command("msg -channel $target Nykyinen system prompt on: " . get_prompt());
    }
}

sub save_settings {
    #Irssi::
    return;
}

sub prindd() {
    my ($text, @rest) = @_;
    print $IRSSI{name} . " debug> " . $text;
}

sub prind {
	my ($text, @rest) = @_;
	print "\00311" . $IRSSI{name} . ">\003 " . $text;
}

sub prindw {
	my ($text, @rest) = @_;
	print "\0034" . $IRSSI{name} . ">\003 " . $text;
}

Irssi::signal_add_last('message public', 'frank' );
Irssi::signal_add_last('message public', 'dalle' );
Irssi::signal_add_last('message public', 'tts' );
Irssi::signal_add_last('message public', 'event_pubmsg');
Irssi::signal_add_last('message private', 'event_privmsg');
#Irssi::signal_add_last('setup saved', 'save_settings');
Irssi::settings_add_str($IRSSI{name}, 'franklin_prompt', $systemsg);
prind("v.$VERSION loaded");
