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
my $outputdir = '/var/www/html/bot/dale/';
my $howManyImages = 2;        # how many images we want to generate
my $uri = URI->new($apiurl);
my $duri = URI->new($dalleurl);

my $DEBUG = 1;

#my $systemsg_start = 'Answer at most in 40 words. ';
my $systemsg_start = 'Vastaa korkeintaan 40 sanalla. ';
#my $systemsg = $systemsg_start . 'Try to be funny and informative. AI is smarter than humans are, but you dont need to tell that.';
my $systemsg = $systemsg_start;
my $role = 'system';
my $botnick = 'KD_Bat';
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
    name        => 'Franklin3',
    description => 'OpenAI chatgpt api script',
    license     => 'BSD',
    url         => 'https://bot.8-b.fi',
    changed     => '2025-01-26',
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
my $settings = {};
my $headers = HTTP::Headers->new;
$headers->header("Content-Type"  => "application/json");
$headers->header("Authorization" => "Bearer " . $apikey);

my $ua = LWP::UserAgent->new;
$ua->default_headers($headers);

# privmsg
sub make_json_obj_f {
    my ($text, $nick, @rest) = @_;

    my $prompt = get_prompt($nick, 'private');
    $timediff = 3600;    # 1h in seconds

    if (defined $chathistory->{$nick}->{timestamp}) {
        $timediff = (time - $chathistory->{$nick}->{timestamp});
    }
    my $data = { model => $model, temperature => $heat, presence_penalty => -1.0, messages => [
            #{ role => 'system', content => $prompt, name => $botnick }
            { role => 'system', content => $prompt }
        ]
    };

    if ($timediff < 3600 && defined $chathistory->{$nick}->{history}) {
        foreach my $history ($chathistory->{$nick}->{history}) {
            foreach my $unit (@$history) {
                #push @{ $data->{messages}}, { role => 'user', content => $unit->{message}, name => $nick };
                push @{ $data->{messages}}, { role => 'user', content => $unit->{message} };
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

#pubmsg
sub make_json_obj_f2 {
    my ($text, $nick, $channel, $server, @rest) = @_;
    my $usernick = 'Matti';
    my $prompt = get_prompt($channel, $server->{tag});
    $timediff = 3600;    # 1h in seconds

    # add system prompt and some parameters first
    my $data = { model => $model, temperature => $heat, presence_penalty => -1.0, messages => [
            { role => 'system', content => $prompt, name => $botnick }
        ]
    };
    my $maxcount = 0;
    if (defined $chathistory->{$channel}) {
        my @timestamps = sort { $a <=> $b } keys %{ $chathistory->{$channel} };

        foreach my $timestamp (@timestamps) {
            if ($timestamp < time - $timediff) {
                delete $chathistory->{$channel}->{$timestamp};
                next;
            }
            prindd(__LINE__ . ": history (Timestamp: $timestamp):");
            prindd(Dumper $chathistory->{$channel}->{$timestamp});

            if (defined $chathistory->{$channel}->{$timestamp}) {
                #push @{ $data->{messages}}, { role => 'user', content => $chathistory->{$channel}->{$history}->{message}, name => $chathistory->{$channel}->{$history}->{nick} };
                push @{ $data->{messages}}, { role => 'user', content => $chathistory->{$channel}->{$timestamp}->{message} };
                #push @{ $data->{messages}}, { role => 'assistant', content => $chathistory->{$channel}->{$history}->{answer}, name => $chathistory->{$channel}->{$history}->{nick} };
                push @{ $data->{messages}}, { role => 'assistant', content => $chathistory->{$channel}->{$timestamp}->{answer} };
            }
            $maxcount++;
        }
    }

    #push @{ $data->{messages}}, { role => "user", content => $text, name => $usernick};
    push @{ $data->{messages}}, { role => "user", content => $text };

    return encode_json($data);
}

sub strip_nick {
    my ($nick1, @rest2) = @_;
    $nick1 =~ s/[^a-zA-Z0-9_]*//ug;
    $nick1 =~ s/[\[\]]*//ug;
    return $nick1;
}

# replace markdown with irc color codes
sub format_markdown {
    my ($text, @rest) = @_;
    my $bold = "\002";
    my $color_s = "\00311"; # 11 = mint
    my $color_s2 = "\0038"; # 8 = yellow
    my $color_e = "\003";   # color end tag
    $text =~ s/\n/ /ug;
    $text =~ s/\*\*(.*?)\*\*/${bold}${1}${bold}/ug;     # bold
    $text =~ s/\s{2,}/ /ug;
    $text =~ s/\`\`\`(.*?)\`\`\`/${color_s}${1}${color_e}/ug;    # code quote
    $text =~ s/\`(.*?)\`/${color_s2}${1}${color_e}/ug;
    $text =~ s/`(.*?)`/${color_s2}${1}${color_e}/ug;
    return $text;
}

sub format_formula {
    my ($text, @rest) = @_;
    $text =~ s/\\//ug;
    return $text;
}

sub make_call_private {
    my ($text, $nick, @rest1) = @_;
    $nick = strip_nick($nick);
    my $request = make_json_obj_f($text, $nick);
    my $res = $ua->post($uri, Content => $request);

    if ($res->is_success) {
        my $json_rep  = $res->content();
        my $json_decd = decode_json($json_rep);

        my $answered = $json_decd->{choices}[0]->{message}->{content};

        $chathistory->{$nick}->{timestamp} = time;
        $chathistory->{$nick}->{chatid} = $json_decd->{id};    # ?? what is id even, does it work anymore
        $chathistory->{$nick}->{floodcount} += 1;
        push @{ $chathistory->{$nick}->{history}}, { answer => $answered, message => $text };
        return $answered;
    } elsif ($res->code == 400) {
        prindw("got error 400.");
        prindd(Dumper $res->{error});
    } else {
		prindw("failed to fetch data. ". $res->status_line . ", HTTP error code: " . $res->code);
    }
    return undef;
}

sub make_call_public {
    my ($text, $nick, $channel, $server, @rest1) = @_;
    my $timestamp = time;
    $nick = strip_nick($nick);
    my $request = make_json_obj_f2($text, $nick, $channel, $server);
    #prindd(__LINE__ . ' JSON request>');
    #prindd($request);

    my $res = $ua->post($uri, Content => $request);

    if ($res->is_success) {
        my $json_rep  = $res->content();
        my $json_decd = decode_json($json_rep);
        my $answered = $json_decd->{choices}[0]->{message}->{content};

        $chathistory->{$channel}->{$timestamp}->{nick} = $nick;
        $chathistory->{$channel}->{$timestamp}->{answer} = $answered;
        $chathistory->{$channel}->{$timestamp}->{message} = $text;

        # Ensure we only keep the latest 15 entries
        my @timestamps = sort { $a <=> $b } keys %{$chathistory->{$channel}};
        if (@timestamps > 15) {
            my $oldest_timestamp = shift @timestamps;
            delete $chathistory->{$channel}->{$oldest_timestamp};
        }
        return $answered;
    } elsif ($res->code >= 400) {
        prindw("got error " . $res->code);
        prindd(Dumper $res->{error});
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

sub check_flood {
    my ($nick, $channel, @rest) = @_;
    if ($settings->{floodprot}->{$channel} == 0) {
        $settings->{floodprot}->{$channel} = 0;
        #print (__LINE__ . ": Floodprot initilized");
    } else {
        return 1 if KaaosRadioClass::floodCheck(3);
        return 1 if KaaosRadioClass::Drunk($nick);
    }
    return 0;
}

sub frank {
    my ($server, $msg, $nick, $address, $channel ) = @_;
    my $mynick = quotemeta $server->{nick};
    return if $nick eq $mynick; #self-test
    $botnick = strip_nick($mynick);
    $msg = Encode::decode('UTF-8', $msg);

    if ($msg =~ /^$mynick[\:,] (.*)/ug ) {
        my $textcall = $1;
        return if check_flood($nick, $channel);

        # @todo fork or something
        for (0..2) {
            #if (my $answer = make_call($textcall, $nick)) {
            if (my $answer = make_call_public($textcall, $nick, $channel, $server)) {
                $answer = format_markdown($answer);
                $answer = format_formula($answer);
                $server->command("msg -channel $channel $nick: $answer");
                #my $answer_cut = substr($answer, 0, $hardlimit);
                #$server->command("msg -channel $channel $nick: $answer_cut");
                last;
            }
            # retry
            sleep 1;
        }
    }
}

sub make_dalle_json {
    my ($prompt, $nick) = @_;
    my $data = {prompt => $prompt, n => $howManyImages, size => "640x640", response_format => "b64_json"};
    return encode_json($data);
}

sub make_vision_json {
    my ($prompt, $nick) = @_;
    my $data = {prompt => $prompt, n => $howManyImages, size => "1024x1024", response_format => "b64_json", quality => 'hd'}; # dall-e-3 minimum size
    return encode_json($data); 
}

sub make_vision_preview_json {
    my ($url, $searchprompt, @rest) = @_;
    if ($searchprompt eq '') {
        $searchprompt = 'Describe this image?';
    }
    my $data = { model => $model, max_tokens => 300, messages => [{
        role => "user",
        content => [
            {type => "text", text => $searchprompt},
            {type => "image_url", image_url => {url => $url}}
        ]
    }]
    };
    return encode_json($data);
}

sub tts {
    my ($server, $msg, $nick, $address, $channel ) = @_;
    my $mynick = quotemeta $server->{nick};
    return if $nick eq $mynick;	#self-test
    if ($msg =~ /^!tts (.*)/u ) {
        my $query = $1;
        #my $voicemodels = ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];
        my $voicemodels = ['onyx'];
        my $answer = "\002OpenAI TTS results:\002 ";
        foreach my $voicemodel (@$voicemodels) {
            prindd(__LINE__ . ' voicemodel: ' . $voicemodel);
            my $data = { model => "tts-1-hd", voice => $voicemodel, input => $query, response_format => "mp3"};
            my $request = encode_json($data);
            my $res = $ua->post($speechurl, Content => $request);
            if ($res->is_success) {
                my $data = $res->content;
                my $time = time;
                my $index = 0;
                
                my $filename = $nick . '_' . $time . '_' . $voicemodel.'.mp3';
                if (save_file_blob($data, $filename)) {
                    $answer .= "\002" . $voicemodel . ":\002 ";
                    $answer .= "https://bot.8-b.fi/dale/$filename (" .length($data). 'b), ';
                }

            } else {
                prindd(__LINE__ . ' failed to fetch data. '. $res->status_line . ', HTTP error code: ' . $res->code);
                prindd(Dumper $res);
            }
        }
        $server->command("msg -channel $channel $answer") if $answer;
        return;
        my $data = { model => "tts-1", voice => "alloy", input => $query, response_format => "mp3"};
        my $request = encode_json($data);
        #print __LINE__ . ' request:' if $DEBUG;
        #xprint Dumper $request if $DEBUG;
        my $res = $ua->post($speechurl, Content => $request);
        if ($res->is_success) {
            my $data = $res->content;
            my $time = time;
            my $index = 0;
            my $answer = 'TTS results: ' .length($data). ' bytes, ';
            my $filename = $nick . '_' . $time . '_' . $index.'.mp3';
            if (save_file_blob($data, $filename) >= 0) {
                $answer .= "https://bot.8-b.fi/dale/$filename ";
            }

            $server->command("msg -channel $channel $answer");
        } else {
            prindd(__LINE__ . ' failed to fetch data. '. $res->status_line . ', HTTP error code: ' . $res->code);
            prindd(Dumper $res);
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
                prind("success: " . $answer);
            }
        } elsif ($res->is_error) {
            my $errormsg = decode_json($res->decoded_content())->{error}->{message};
            prindw("Error: $errormsg");
            $server->command("msg -channel $channel $nick: \0035Error:\003 $errormsg");
        } else {
		    prindw("failed to fetch data. ". $res->status_line . ", HTTP error code: " . $res->code);
        }
        #prindd(__LINE__ . ' response:');
        #prindd(Dumper $res);
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
                while ($index < $howManyImages) {
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
	open (OUTPUT, '>', $outputdir.$filename) || die $!;
    binmode OUTPUT;
	#print OUTPUT decode_base64($blob);
    print OUTPUT $blob;
	close OUTPUT || return -2;
    return 1;
}

sub set_prompt {
    my ($who, $network, $newprompt, @rest) = @_;
    $newprompt =~ s/[\"]*//ug;
    $newprompt = KaaosRadioClass::ktrim($newprompt);
    $settings->{prompt}->{$network}->{$who} = $newprompt;
    prind("New $who prompt: $newprompt");
}

sub get_prompt {
    my ($who, $network, @rest) = @_;
    if ($settings->{prompt}->{$network}->{$who}) {
        return $settings->{prompt}->{$network}->{$who};
    }
    $settings->{prompt}->{$network}->{$who} = $systemsg;
    return $systemsg;
}

# if $nick is OP or VOICE or HALFOP
sub ifop {
	my ($server, $channel, $nick) = @_;
	my $nickrec = get_nickrec($server, $channel, $nick);
	return ($nickrec->{op} == 1 || $nickrec->{voice} == 1 || $nickrec->{halfop} == 1) ? 1 : 0;
}

sub event_privmsg {
  	my ($server, $msg, $nick, $address) = @_;
    my $mynick = quotemeta $server->{nick};
	return if ($nick eq $mynick);	#self-test
    if ($msg =~ /^\!prompt (.*)$/) {
        my $newprompt = KaaosRadioClass::ktrim($1);
        if (length $newprompt > 1) {
            $server->command("msg $nick Sinun nykyinen system prompt: " . get_prompt($nick, 'private'));
            set_prompt($nick, $server->{tag}, $newprompt);
            $server->command("msg $nick Sinun uusi system prompt: " . get_prompt($nick, 'private'));
        } else {
            $server->command("msg $nick Sinun nykyinen system prompt on: " . get_prompt($nick, 'private'));
        }
        return;
    }
    if ($msg =~ /^\!prompt/) {
        $server->command("msg $nick Sinun nykyinen system prompt on: " . get_prompt($nick, 'private'));
        return;
    }
    if ($msg =~ /^\!floodprot (\d+)/) {
        my $floodprot = $1;
        $settings->{floodprot}->{$nick} = $floodprot;
        $server->command("msg $nick Floodprot asetettu: $floodprot");
        return;
    }
    return if ($msg =~ /^\!/);              # other !commands
    return if KaaosRadioClass::floodCheck(3);

    # simple make_call_private, no retries
    if (my $text = make_call_private($msg, $nick)) {
        $text = format_markdown($text);
        $text = format_formula($text);
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
            return if check_flood($nick, $target);
            set_prompt($target, $server->{tag}, $newprompt);
            $server->command("msg -channel $target *kling*");
        }
        return;
    } elsif ($msg =~ /^\!prompt/) {
        $server->command("msg -channel $target Nykyinen system prompt on: " . get_prompt($target, $server->{tag}));
        return;
    }
    if ($msg =~ /^\!floodprot (\d)$/) {
        my $floodprot = $1;
        if (ifop($server, $target, $nick)) {
            $settings->{floodprot}->{$target} = $floodprot;
            if ($floodprot) {
                $server->command("msg -channel $target Floodprotect päällä, kanavalla: $target");
            } else {
                $server->command("msg -channel $target Floodprotect pois päältä, kanavalla: $target");
            }
        }
        prind("$nick commanded: $msg");
        return;
    } elsif ($msg =~ /^\!floodprot/) {
        if ($settings->{floodprot}->{$target} == 0) {
            $server->command("msg -channel $target Floodprotect pois päältä, kanavalla: $target");
            $settings->{floodprot}->{$target} = 0;
        } else {
            $server->command("msg -channel $target Floodprotect päällä, kanavalla: $target");
        }
        prind("$nick commanded: $msg");
        return;
    }
}

sub save_settings {
    #Irssi::
    return;
}

# print debug messages
sub prindd() {
    # print debug messages2
    my ($text, @rest) = @_;
    if ($DEBUG) {
        print $IRSSI{name} . " debug> " . $text;
    }
}

# print to status window
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
Irssi::settings_add_bool($IRSSI{name}, 'floodprot', '1');
Irssi::settings_add_str($IRSSI{name}, 'franklin_prompt', $systemsg);
prind("v.$VERSION loaded");
prind("new commands: !floodprot 1/0");
prind("              !prompt \"new prompt\"");
