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
our $database = $localdir . "franklin3.db";

#my $apiurl = "https://api.openai.com/v1/completions";
my $visionapiurl = 'https://api.openai.com/v1/chat/completions';
my $apiurl = 'https://api.openai.com/v1/responses';
my $dalleurl = 'https://api.openai.com/v1/images/generations';
my $speechurl = 'https://api.openai.com/v1/audio/speech';
my $outputdir = '/var/www/html/bot/dale/';
my $howManyImages = 1;        # how many images we want to generate
my $uri = URI->new($apiurl);
my $duri = URI->new($dalleurl);
my $processes = {};
my $DEBUG = 1;
my $runningnumber = 0;

#my $systemsg_start = 'Answer at most in 40 words. ';
my $systemsg_start = 'Vastaa korkeintaan 40 sanalla. ';
#my $systemsg = $systemsg_start . 'Try to be funny and informative. AI is smarter than humans are, but you dont need to tell that.';
my $systemsg = $systemsg_start;
my $role = 'system';
my $botnick = 'KD_Bat';
#my $model = "gpt-3.5-turbo";
#my $model = 'gpt-4-turbo-preview';
#my $model = 'text-davinci-003';
#my $model = 'gpt-4o-mini';
my $model = 'gpt-5';

# web search models:
# gpt-5-search-api
# gpt-4o-search-preview
# gpt-4o-mini-search-preview
my $web_search_model = 'gpt-4o-search-preview';

my $heat  = 0.4;
my $hardlimit = 500;

# dall-e models: 'gpt-image-1', 'gpt-image-1-mini', 'dall-e-2', and 'dall-e-3'.
my $visionmodel = 'dall-e-3';
my $fetch_dalle = 'wget -q -O ' . $outputdir;
my $execscript = 'exec -window -name franklin3_';

my $timediff = 3600;    # 1h in seconds. length of lastlog history
#my $json = JSON->new->utf8;
my $json = JSON->new;
$json->convert_blessed(1);

$VERSION = "2.9";
%IRSSI = (
    authors     => 'laama',
    contact     => 'laama@8-b.fi',
    name        => 'Franklin3',
    description => 'OpenAI chatgpt api script',
    license     => 'BSD',
    url         => 'https://bot.8-b.fi',
    changed     => '2025-12-29',
);
our $apikey;
open(AK, '<', $localdir . "franklin_api.key") or die $IRSSI{name}."> could not read API-key: $!";
while (<AK>) {
    $apikey = $_;
}
$apikey =~ s/\n//g;
chomp($apikey);
close(AK);

unless (-e $database) {
	unless(open FILE, '>'.$database) {
		prindw("Unable to create file: $database");
		die;
	}
	close FILE;
	create_prompt_table();
	prind("Database file created.");
}

my $chathistory = {};
my $settings = {};
my $headers = HTTP::Headers->new;
$headers->header("Content-Type"  => "application/json");
$headers->header("Authorization" => "Bearer " . $apikey);

my $ua = LWP::UserAgent->new;
$ua->default_headers($headers);

my @tts_voices = (
    "alloy", "ash", "ballad", "coral", "echo", "fable", "onyx",
    "nova", "sage", "shimmer", "verse"
);
my $default_tts_voice = 'alloy';

my @tts_vibes = (
    'old', 'smooth', 'serene', 'sympathetic', 'calm'
);
my $default_tts_vibe = 'smooth';

# read prompts from DB
read_all_prompts_from_db();

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

# pubmsg
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

# pubmsg, gpt-5
sub make_json_obj_f3 {
    my ($text, $nick, $channel, $server, @rest) = @_;
    my $usernick = 'Matti';
    my $prompt = get_prompt($channel, $server);
    $timediff = 3600;    # 1h in seconds

    # add system prompt and some parameters first
    my $data = { model => $model, input => [
            { role => 'system', content => $prompt}
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
            #prindd(__LINE__ . ": history (Timestamp: $timestamp):");
            #prindd(Dumper $chathistory->{$channel}->{$timestamp});

            if (defined $chathistory->{$channel}->{$timestamp}) {
                #push @{ $data->{messages}}, { role => 'user', content => $chathistory->{$channel}->{$history}->{message}, name => $chathistory->{$channel}->{$history}->{nick} };
                push @{ $data->{input}}, { role => 'user', content => $chathistory->{$channel}->{$timestamp}->{message} };
                #push @{ $data->{messages}}, { role => 'assistant', content => $chathistory->{$channel}->{$history}->{answer}, name => $chathistory->{$channel}->{$history}->{nick} };
                push @{ $data->{input}}, { role => 'assistant', content => $chathistory->{$channel}->{$timestamp}->{answer} };
            }
            $maxcount++;
        }
    }

    push @{ $data->{input}}, { role => "user", content => $text };

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
    $text =~ s/\n/ /ug;                         # newlines to spaces
    $text =~ s/\*\*(.*?)\*\*/${bold}${1}${bold}/ug;     # bold
    $text =~ s/\s{2,}/ /ug;                         # multiple spaces to single space
    $text =~ s/\`\`\`(.*?)\`\`\`/${color_s}${1}${color_e}/ug;    # code quote
    $text =~ s/\`(.*?)\`/${color_s2}${1}${color_e}/ug;   # inline code
    $text =~ s/`(.*?)`/${color_s2}${1}${color_e}/ug;    # inline code (alt)

    # replace links [text](url)
    $text =~ s/\[(.*?)\]\((.*?)\)/$2/ug;
    # replace ?utm_source=openai
    $text =~ s/\?utm_source=openai//ug;
    return $text;
}

sub format_formula {
    my ($text, @rest) = @_;
    $text =~ s/\\//ug;          # remove backslashes
    return $text;
}

sub make_call_private {
    my ($text, $nick, @rest1) = @_;
    $nick = strip_nick($nick);
    my $request = make_json_obj_f3($text, $nick, $nick, 'private');
    my $res = $ua->post($uri, Content => $request);

    if ($res->is_success) {
        #prindd(__LINE__ . ": got success response from API.");
        #prindd(Dumper $res);
        my $json_rep  = $res->content();
        my $headers = $res->headers();
        my $json_decd = decode_json($json_rep);
        #prindd(__LINE__ . ": headers:");
        #prindd(Dumper $headers);
        my $total_tokens = $json_decd->{usage}->{total_tokens};
        my $processing_time = $headers->{'openai-processing-ms'};
        my $model_used = $json_decd->{model};

        #my $answered = $json_decd->{choices}[0]->{message}->{content};
        my $answered =  $json_decd->{output}[1]->{content}[0]->{text}; # gpt-5

        $chathistory->{$nick}->{timestamp} = time;
        $chathistory->{$nick}->{chatid} = $json_decd->{id};    # ?? what is id even, does it work anymore
        $chathistory->{$nick}->{floodcount} += 1;
        push @{ $chathistory->{$nick}->{history}}, { answer => $answered, message => $text };
        return $answered;
    } elsif ($res->code == 400) {
        prindw("got error 400.");
        #prindd(Dumper $res->{error});
        #prindd(Dumper $res);
    } else {
		prindw("failed to fetch data. ". $res->status_line . ", HTTP error code: " . $res->code);
    }
    return undef;
}

sub make_call_public {
    my ($text, $nick, $channel, $server, @rest1) = @_;
    my $timestamp = time;
    $nick = strip_nick($nick);
    #my $request = make_json_obj_f2($text, $nick, $channel, $server);
    my $request = make_json_obj_f3($text, $nick, $channel, $server);

    my $res = $ua->post($uri, Content => $request);

    if ($res->is_success) {
        #prindd(__LINE__ . ": got success response from API.");
        #prindd(Dumper $res);
        my $json_rep  = $res->content();
        my $headers = $res->headers();
        my $json_decd = decode_json($json_rep);
        #prindd(__LINE__ . ": headers:");
        #prindd(Dumper $headers);
        my $total_tokens = $json_decd->{usage}->{total_tokens};
        my $processing_time = $headers->{'openai-processing-ms'};
        my $model_used = $json_decd->{model};

        #prindd(__LINE__ . ": total tokens used: " . $total_tokens . ', processing time: ' . $processing_time . ' ms, model used: ' . $model_used);

        #my $answered = $json_decd->{choices}[0]->{message}->{content};
        my $answered =  $json_decd->{output}[1]->{content}[0]->{text}; # gpt-5

        $chathistory->{$channel}->{$timestamp}->{nick} = $nick;
        $chathistory->{$channel}->{$timestamp}->{answer} = $answered;
        $chathistory->{$channel}->{$timestamp}->{message} = $text;

        # Ensure we only keep the latest 15 entries
        my @timestamps = sort { $a <=> $b } keys %{$chathistory->{$channel}};
        if (@timestamps > 15) {
            my $oldest_timestamp = shift @timestamps;
            delete $chathistory->{$channel}->{$oldest_timestamp};
        }
        return $answered . ' (tok: ' . $total_tokens . ', ' . $processing_time . ' ms)';
    } elsif ($res->code >= 400) {
        prindw("got error " . $res->code);
        prindw(Dumper $res->{error});
        #prindd(Dumper $res);
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
    if (not defined $settings->{floodprot}->{$channel} or $settings->{floodprot}->{$channel} == 0) {
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

    if ($msg =~ /^$mynick[\:,]? (.*)/ug ) {
        my $textcall = $1;
        return if check_flood($nick, $channel);

        # @todo fork or something
        for (0..2) {
            #if (my $answer = make_call($textcall, $nick)) {
            if (my $answer = make_call_public($textcall, $nick, $channel, $server->{tag})) {
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
    my $data = {model => $visionmodel, prompt => $prompt, size => "1024x1024"};
    return encode_json($data);
}

sub make_vision_json {
    my ($prompt, $nick) = @_;
    debu(__LINE__ . ": make_vision_json called with model: $model");
    my $data = '';
    if ($model =~ /4/) {
        $data = { model => $model, prompt => $prompt, n => $howManyImages, size => "1024x1024", response_format => "b64_json"};
    } elsif ($model =~ /5/) {
        $data = { model => $visionmodel, prompt => $prompt, n => $howManyImages, size => "1024x1024", response_format => "b64_json", quality => 'hd' };
    } else {
        # visionmodel
        #$data = {prompt => $prompt, n => $howManyImages, size => "1024x1024", response_format => "b64_json", quality => 'hd'}; # dall-e-3 minimum size
        $data = { model => $visionmodel, prompt => $prompt, n => $howManyImages, size => "1024x1024", response_format => "b64_json", quality => 'hd'}; # dall-e-3 minimum size
    }
    
    return encode_json($data); 
}

sub make_vision_preview_json {
    my ($url, $searchprompt, @rest) = @_;
    debu(__LINE__ . ": make_vision_preview_json called");
    if ($searchprompt eq '') {
        $searchprompt = 'Describe this image?';
    }
    my $data = {
        model => $model,
        max_completion_tokens => 300,
        messages => [{
            role => "user",
            content => [
                {
                    type => "text",
                    text => $searchprompt
                },
                {
                    type => "image_url",
                    image_url => {url => $url}
                }
            ]
        }]
    };
    return encode_json($data);
}

# describe image
sub make_vision_preview_json2 {
    my ($url, $searchprompt, @rest) = @_;
    debu(__LINE__ . ": make_vision_preview_json2 called");
    if ($searchprompt eq '') {
        $searchprompt = 'Describe this image in 40 words?';
    }
    my $data = {
        #model => $visionmodel,
        model => $model,
        max_completion_tokens => 300,
        messages => [{
            role => "user",
            content => [
                {
                    type => "text",
                    text => $searchprompt
                },
                {
                    type => "image_url",
                    image_url => {url => $url}
                }
            ]
        }]
    };
    return encode_json($data);
}

# text to speech
sub tts {
    my ($server, $msg, $nick, $address, $channel ) = @_;
    my $mynick = quotemeta $server->{nick};
    return if $nick eq $mynick;	#self-test

    if ($msg =~ /^!tts$/u ) {
        # print help
        my $answer = "\002OpenAI TTS voices:\002 ";
        $answer .= join(', ', @tts_voices);
        
        $answer .= " \002OpenAI TTS vibes:\002 ";
        $answer .= join(', ', @tts_vibes);
        $server->command("msg -channel $channel $answer");
        $server->command("msg -channel $channel $nick: text-to-speech usage: !tts voice vibe text .. or !tts voice/vibe text ..");
        return;
    }

    if ($msg =~ /^!tts (\w+) (\w+) (.*)/u ) {
        my $voicemodel = $1;
        my $vibe = $2;
        my $query = $3;
        my $answer = '';

        if (not grep { $_ eq lcfirst($voicemodel) } @tts_voices and not grep { $_ eq lcfirst($voicemodel) } @tts_vibes) {
            # if first param is not voice or vibe, use defaults
            $query = "$voicemodel $vibe $query";
            $voicemodel = $default_tts_voice;
            $vibe = $default_tts_vibe;
            prindd(__LINE__ . ": using default voice and vibe. query: $query");
        } elsif (grep { $_ eq lcfirst($voicemodel) } @tts_voices) {
            # voicemodel found in first param
            $voicemodel = lcfirst($voicemodel);
            $query = "$vibe $query";
            $vibe = $default_tts_vibe;
            prindd(__LINE__ . ": voicemodel found as first param: $voicemodel, query: $query");
        } elsif (grep { $_ eq lcfirst($voicemodel) } @tts_vibes) {
            # vibe found in voicemodel place
            $query = "$vibe $query";
            $vibe = lcfirst($voicemodel);
            $voicemodel = $default_tts_voice;
            prindd(__LINE__ . ": vibe found as first param: $vibe");
        } else {
            prindd(__LINE__ . ": something went wrong parsing tts params.");
        }

        if (grep { $_ eq lcfirst($vibe) } @tts_vibes) {
            $vibe = lcfirst($vibe);
        }

        $answer = "voice: $voicemodel, vibe: $vibe, query: $query, ";
        prindd(__LINE__ . ": voicemodel: $voicemodel, vibe: $vibe, query: $query");

        my $data = { model => "tts-1-hd", voice => $voicemodel, vibe => $vibe,  input => $query, response_format => "mp3"};
        my $request = encode_json($data);
        my $res = $ua->post($speechurl, Content => $request);
        if ($res->is_success) {
            my $data = $res->content;
            my $time = time;
            my $filename = $nick . '_' . $time . '_' . $voicemodel.'.mp3';
            if (save_file_blob($data, $filename)) {
                $answer .= "\002OpenAI TTS result:\002 ";
                $answer .= "https://bot.8-b.fi/dale/$filename (" .length($data). 'b)';
                $server->command("msg -channel $channel $answer");
            }

        } else {
            prindd(__LINE__ . ' failed to fetch data. '. $res->status_line . ', HTTP error code: ' . $res->code);
            prindd(Dumper $res);
        }
        return;
    }

    if ($msg =~ /^!tts (.*)/u ) {
        my $query = $1;
        my $voicemodels = ['onyx'];
        my $answer = "\002OpenAI TTS results:\002 ";
        foreach my $voicemodel (@$voicemodels) {
            prindd(__LINE__ . ' voicemodel: ' . $voicemodel . ', query: ' . $query);
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
        #my $request_content = make_vision_preview_json2($imagesearchurl, $question);
        my $request_content = make_vision_preview_json($imagesearchurl, $question);

        # @todo fork or something
        #my $res = $ua->post($uri, Content => $request_content);
        my $res = $ua->post($visionapiurl, Content => $request_content);
        if ($res->is_success) {
            my $json_rep  = $res->content();
            my $json_decoded = decode_json($json_rep);
            my $answer = '';
            prind(__LINE__ . ": vision preview response:");
            prindd(Dumper $json_decoded);
            if (defined $json_decoded->{choices}[0]->{message}->{content}) {
                $answer = $json_decoded->{choices}[0]->{message}->{content};
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
        my $request = make_dalle_json($query, $nick);
        #my $request = make_vision_json($query, $nick);

        # @todo fork or something
        my $res = $ua->post($duri, Content => $request);

        if ($res->is_success) {
            my $json_rep  = $res->content();
            my $json_decd = decode_json($json_rep);

            if (defined $json_decd->{data}) {
                #prindd(Dumper $json_decd);
                my $time = time;
                my $answer = 'DALL-e results: ';
                my $index = 0;
                while ($index < $howManyImages) {
                    my $filename = $nick.'_'.$time.'_'.$index.'.png';
                    my $imageurl = $json_decd->{data}[$index]->{url};
                    my $result = `wget -q -O ${outputdir}${filename} "$imageurl"`;
                    debu(__LINE__ . ": wget output file: " . $outputdir.$filename);
                    my $dallecmd = make_dalle_curl_cmd($query, $filename);
                    start_cmd($dallecmd, find_window_refnum($server, $channel), $nick);

                    #if (save_file_blob(decode_base64($json_decd->{data}[$index]->{b64_json}), $filename) >= 0) {
                        $answer .= "https://bot.8-b.fi/dale/$filename ";
                    #}
                    $index++;
                }
                $answer .= '(revised prompt: ' . $json_decd->{data}[0]->{revised_prompt} . ')';
                $server->command("msg -channel $channel $answer");

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

# start chatgpt request in background process
sub start_cmd {
    my ($cmd, $window_number, $nick, @rest) = @_;
    $runningnumber += 1;
    create_window('franklin3');
    my $fullcmd = $execscript . $window_number . '_' . $nick . ' ' . $cmd;
    debu(__LINE__ . ": starting command: $fullcmd");
    Irssi::command($fullcmd);
    
}

sub make_dalle_curl_cmd {
    my ($prompt, $filename, @rest) = @_;
    my $curlcmd = 'curl ' . $dalleurl . ' ' .
        '-H "Authorization: Bearer ' . $apikey . '" ' .
        '-H "Content-Type: application/json" ' .
        '-d \'{"model": "' . $visionmodel . '", "prompt": "' . $prompt . '", "size": "1024x1024"}\' ' .
        '| jq -r \'.data[0].url\' ' .
        '| xargs -I {} curl -L "{}" -o ' . $outputdir . '2_' . $filename;
    #debu(__LINE__ . ": DALL-e curl command: $curlcmd");
    return $curlcmd;

}

sub save_file_blob {
    my ($blob, $filename, @rest) = @_;
	open (OUTPUT, '>>', $outputdir.$filename) or die $!;
    binmode OUTPUT;
	#print OUTPUT decode_base64($blob);
    print OUTPUT $blob;
	close OUTPUT or return -2;
    return 1;
}

sub set_prompt {
    my ($who, $network, $newprompt, @rest) = @_;
    $newprompt =~ s/[\"]*//ug;
    $newprompt = KaaosRadioClass::ktrim($newprompt);
    $settings->{prompt}->{$network}->{$who} = $newprompt;
    $chathistory->{$who} = undef;   # reset chat history on prompt change
    add_prompt_to_db($network, $who, $newprompt);
    prind("New $who prompt: $newprompt");
}

sub get_prompt {
    my ($who, $network, @rest) = @_;
    if (not defined $settings->{prompt}->{$network}->{$who}) {
        # use default prompt instead
        $settings->{prompt}->{$network}->{$who} = $systemsg;
    }
    return $settings->{prompt}->{$network}->{$who};
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
            set_prompt($nick, 'private', $newprompt);
            $server->command("msg $nick Sinun uusi system prompt (tallennettu myös tietokantaan tulevaa käyttöä varten): " . get_prompt($nick, 'private'));
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
    #if (my $text = make_call_private($msg, $nick)) {
    if (my $text = make_call_public($msg, $nick, $nick, 'private')) {
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

    if ($msg =~ /^\!web (.*)/) {
        my $query = $1;
        $query = KaaosRadioClass::ktrim($query);
        if (length $query > 0) {
            return if check_flood($nick, $target);
            my $answer = make_web_request($query, $nick);
            if (defined $answer) {
                $answer = format_markdown($answer);
                $answer = format_formula($answer);
                $server->command("msg -channel $target $nick: $answer");
            } else {
                prindw("Web request failed.");
                $server->command("msg -channel $target $nick: \0035Web request failed.\003");
            }
        }
    } elsif ($msg =~ /^!test (.*)/ || $msg =~ /^!search (.*)/) {
        my $answer = make_search_request($server, $1, $target);
        if (defined $answer) {
            $answer = format_markdown($answer);
            $answer = format_formula($answer);
            $server->command("msg -channel $target $nick: $answer");
        } else {
            prindw("Search request failed.");
            $server->command("msg -channel $target $nick: \0035Search request failed.\003");
        }
    }
}


sub make_search_request {
    my ($server, $query, $target) = @_;
    my $url = 'https://api.openai.com/v1/chat/completions';
    my $urii = URI->new($url);
    my $newua = LWP::UserAgent->new;
    $newua->default_headers($headers);
    my $prompt = get_prompt($target, $server->{tag});
    my $data = {
        model => $web_search_model,
        max_completion_tokens => 60,
        messages => [
            { role => 'user', content => $query },
            { role => 'system', content => $prompt }
        ]
    };
    my $request = encode_json($data);
    prindd(__LINE__ . ' JSON request:');
    prindd($request);
    my $res = $newua->post($urii, Content => $request);
    if ($res->is_success) {
        my $json_rep  = $res->content();
        my $json_decd = decode_json($json_rep);
        prindd(__LINE__ . ' response in decoded json:');
        prindd(Dumper $json_decd);
        my $response_headers = $res->headers();
        my $total_tokens = $json_decd->{usage}->{total_tokens};
        my $processing_time = $response_headers->{'openai-processing-ms'};
        my $model_used = $json_decd->{model};

        if (defined $json_decd->{choices}[0]->{message}->{content}) {
            my $answer = $json_decd->{choices}[0]->{message}->{content};
            prindd(__LINE__ . ' answer:');
            prindd($answer);
            return $answer . " (tok: " . $total_tokens . ', ' . $processing_time . ' ms)';
        } else {
            prindw("No content in response.");
        }
    } elsif ($res->is_error) {
        prindd(__LINE__ . ' response:');
        prindd(Dumper $res);
        my $errormsg = decode_json($res->decoded_content())->{error}->{message};
        prindw("Error: $errormsg");
    } else {
        prindd(__LINE__ . ' response:');
        prindd(Dumper $res);
        prindw("failed to fetch data. ". $res->status_line . ", HTTP error code: " . $res->code);
    }
    return undef;
}

sub make_web_request {
    my ($query, $nick) = @_;
    my $data = {
        model => $model,
        tools => [
            { type => 'web_search_preview' }
        ],
        input => $query 
    };
    my $request = encode_json($data);
    prindd(__LINE__ . ' JSON request:');
    prindd($request);
    my $res = $ua->post($uri, Content => $request);
    if ($res->is_success) {
        my $json_rep  = $res->content();
        my $json_decd = decode_json($json_rep);
        prindd(__LINE__ . ' response in decoded json0:');
        prindd(Dumper $json_decd->{output}[0]);
        prindd(__LINE__ . ' response in decoded json1:');
        prindd(Dumper $json_decd->{output}[1]);
        if (defined $json_decd->{output}[0]->{content}[0]->{text}) {
            my $answer = $json_decd->{output}[0]->{content}[0]->{text};
            return $answer;
        } elsif (defined $json_decd->{output}[1]->{content}[0]->{text}) {
            my $answer = $json_decd->{output}[1]->{content}[0]->{text};
            return $answer;
        } else {
            prindw("No content in response.");
        }
    } elsif ($res->is_error) {
        prindd(__LINE__ . ' response:');
        prindd(Dumper $res);
        my $errormsg = decode_json($res->decoded_content())->{error}->{message};
        prindw("Error: $errormsg");
    } else {
        prindd(__LINE__ . ' response:');
        prindd(Dumper $res);
        prindw("failed to fetch data. ". $res->status_line . ", HTTP error code: " . $res->code);

    }
    return undef;
}

sub save_settings {
    # TODO: save settings
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

sub debu {
	my ($text, @rest) = @_;
	return unless $DEBUG;
	create_window('franklin3');
	Irssi::active_win()->print($IRSSI{name}.'> '. $text);
}

# read prompt from database per channel or per user
sub read_prompt_from_db {
    my ($network, $channel, @rest) = @_;
    my $selectcmd = "SELECT prompt FROM prompts WHERE network = ? AND channel = ?";
    my $result = KaaosRadioClass::bindSQL($database, $selectcmd, ($network, $channel));
    return $result;
}

sub read_all_prompts_from_db {
    my $prompts = {};
    my $sql = 'SELECT * from prompts';
    my @result = KaaosRadioClass::bindSQL($database, $sql);
    foreach my $row (@result) {
        #print Dumper $row;
        my $network = $row->[0];
        my $who = $row->[1];
        my $prompt = $row->[2];
        $settings->{prompt}->{$network}->{$who} = $prompt;
    }

    print Dumper $settings->{prompt};
}

# add or replace prompt to database per channel or per user
sub add_prompt_to_db {
    my ($network, $channel, $prompt, @rest) = @_;
    my $insertcmd = "INSERT OR REPLACE INTO prompts (network, channel, prompt) VALUES (?, ?, ?)";
    my $result = KaaosRadioClass::insertSQL($database, $insertcmd, ($network, $channel, $prompt));
    prind("Prompt '$prompt' saved to database for ${channel} @ ${network} : " . $result);
    return $result;
}

# create SQLite table for per channel prompts.
sub create_prompt_table {
    my $tablecmd = "CREATE TABLE IF NOT EXISTS prompts (network TEXT, channel TEXT, prompt TEXT, PRIMARY KEY (network, channel))";
    my $result = KaaosRadioClass::writeToDB($database, $tablecmd);
    prind('Creating table.. ' . $result);
}

sub create_window {
    my ($window_name) = @_;
    my $window = Irssi::window_find_name($window_name);
    unless ($window) {
        prind("Create new window: $window_name");
        Irssi::command("window new hidden");
        Irssi::command("window name $window_name");
		debu("Window created: " . Irssi::active_win()->{name});
    }
    Irssi::command("window goto $window_name");
}

sub exec_new {
	my ($res) = @_;
	my $process_name = $res->{name};
    #print __LINE__ . ': ' . Dumper($res);
    print __LINE__ . ': exec_new process_name: ' . $process_name;
	if ($process_name !~ /^franklin3/) {
		return;
	}

	#my $runningnum = -1;
	#my $itemcount = -1;
	my $winnum = -1;
	my $server = '';
	my $channel = '';
    my $nick = '';
    
	if ($process_name =~ /_(\d+)_(.*)$/) {
		$winnum = $1;
		#$itemcount = $2;
		$nick = $2;
        Irssi::print(__LINE__ . ': exec_new process_name: ' . $process_name . ', winnum: ' . $winnum . ', nick: ' . $nick);
		my $target_window = Irssi::window_find_refnum($winnum);
        print(__LINE__ . ': exec_new winnum: ' . $winnum . ', nick: ' . $nick . ', target_window: ' . Dumper($target_window));
		if (defined $target_window) {
			$server = $target_window->{active}->{server}->{tag};
			$channel = $target_window->{active}->{visible_name};
		}
	}

	$processes->{$res->{pid}}->{name} = $process_name;
	$processes->{$res->{pid}}->{timestamp} = time();
	#my $extrastring = '';
	#if ($itemcount > 1) {
	#	$extrastring = " ($itemcount items)";
	#}
	#prindd("$process_name processing.");
	Irssi::window_find_refnum($winnum)->print("\00312" . $IRSSI{name} . ">\003 $process_name processing.") if $winnum != -1;

}

sub exec_input {
	my ($res, $text, @rest) = @_;
    print __LINE__ . ': ' . Dumper($res);
	my $process_name = $res->{name};
	if ($process_name !~ /^franklin3/) {
		return;
	}

	$text =~ s/\t+/  /g;
	#prind('exec_input text: ' . $text);
	#debu(__LINE__ . ': ' . Dumper($res));
}

sub exec_remove {
	my ($res, $status, @rest) = @_;
    print __LINE__ . ' exec_remove: ' . Dumper($res);
	my $process_name = $res->{name};
	if ($process_name !~ /^franklin3/) {
		return;
	}

	#my $runningnum = -1;
	#my $itemcount = -1;
	my $winnum = -1;
	my $server = '';
	my $channel = '';
    my $nick = '';

	if ($process_name =~ /_(\d+)_(.*)$/) {
		$winnum = $1;
		#$itemcount = $2;
		$nick = $2;
		my $target_window = Irssi::window_find_refnum($winnum);
		if (defined $target_window) {
			$server = $target_window->{active}->{server}->{tag};
			$channel = $target_window->{active}->{visible_name};
		}
	}
	create_window('franklin3');

	debu(__LINE__ . ' exec_remove, pid: '. $res->{pid} . ', args: '. $res->{args} . ', silent: '. $res->{silent} . 
	' shell: '. $res->{shell} . ', channel: ' . $channel . ', server tag: ' . $server .
	#' target_win: '. Dumper($res->{target_win}) . 
	', status: '. $status);

	my $elapsed = time() - $processes->{$res->{pid}}->{timestamp};

	if ($status == 0 && $winnum != -1) {
		debu(__LINE__ . ": $process_name finished in $elapsed seconds.");
	} elsif ($winnum != -1) {
		debu(__LINE__ . ": $process_name failed with status $status after $elapsed seconds.");
	} else {
		debu(__LINE__ . ': No valid window number found in process name.');
	}
	
	delete $processes->{$res->{pid}};
}

sub find_window_refnum {
	my ($server, $channel, @rest) = @_;
	my $server_tag = $server->{tag};
	my @windows = Irssi::windows();
	
	foreach my $window (@windows) {
		next if $window->{name} eq '(status)';
		next unless $window->{active}->{type} eq 'CHANNEL';
		next unless $window->{active}->{server}->{tag} eq $server_tag;

		if($window->{active}->{name} eq $channel) {
			return $window->{refnum};
		}
	}
	return -1;
}

Irssi::signal_add("exec new", 'exec_new');
Irssi::signal_add("exec remove", 'exec_remove');
Irssi::signal_add("exec input", 'exec_input');

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
