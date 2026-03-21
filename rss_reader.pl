use warnings;
use strict;
use utf8;
use Irssi;
use LWP::UserAgent;
use XML::RSS;
use HTML::Entities qw(decode_entities);

use vars qw($VERSION %IRSSI);

$VERSION = '2026-03-21';
%IRSSI = (
    authors     => 'GitHub Copilot',
    contact     => 'local',
    name        => 'rss_reader',
    description => 'Read RSS feed from configured URL and post new items to configured channels',
    license     => 'Public Domain',
    changed     => $VERSION,
);

my $SCRIPT_NAME = 'rss_reader.pl';
my %seen_ids;
my $first_poll = 1;
my $last_poll = 0;

my $ua = LWP::UserAgent->new(
    timeout => 10,
    agent   => 'irssi-rss-reader/1.0',
);

sub print_help {
    Irssi::print("$SCRIPT_NAME commands:");
    Irssi::print('/rss_reader_seturl <url>         - set RSS feed URL');
    Irssi::print('/rss_reader_addchan <#channel>    - add channel for announcements');
    Irssi::print('/rss_reader_delchan <#channel>    - remove channel from announcements');
    Irssi::print('/rss_reader_list                  - show current settings');
    Irssi::print('/rss_reader_update                - fetch feed now and announce latest/new items');
}

sub normalize_channel {
    my ($chan) = @_;
    $chan //= '';
    $chan =~ s/^\s+|\s+$//g;
    return lc $chan;
}

sub get_enabled_channels {
    my $raw = Irssi::settings_get_str('rss_reader_channels');
    my @channels = grep { length $_ } map { normalize_channel($_) } split(/\s+/, $raw);
    return @channels;
}

sub save_enabled_channels {
    my (@channels) = @_;
    my %unique;
    @channels = grep { !$unique{$_}++ } grep { length $_ } map { normalize_channel($_) } @channels;
    Irssi::settings_set_str('rss_reader_channels', join(' ', @channels));
}

sub broadcast_message {
    my ($text) = @_;
    my @enabled = get_enabled_channels();
    return unless @enabled;

    my %enabled_map = map { $_ => 1 } @enabled;
    my $sent = 0;

    foreach my $channel (Irssi::channels()) {
        my $channel_name = normalize_channel($channel->{name});
        next unless $enabled_map{$channel_name};
        $channel->{server}->command("msg $channel->{name} $text");
        $sent++;
    }

    if ($sent == 0) {
        Irssi::print("$SCRIPT_NAME: no enabled channels are currently joined.");
    }
}

sub trim_seen_cache {
    my $max_seen = 2000;
    return if scalar(keys %seen_ids) <= $max_seen;

    my @keys = keys %seen_ids;
    my $remove_count = scalar(@keys) - $max_seen;
    for (my $i = 0; $i < $remove_count; $i++) {
        delete $seen_ids{$keys[$i]};
    }
}

sub fetch_and_process_feed {
    my ($manual_request) = @_;
    my $url = Irssi::settings_get_str('rss_reader_url');

    unless (defined $url && $url =~ m{^https?://}i) {
        Irssi::print("$SCRIPT_NAME: set URL first with /rss_reader_seturl <url>");
        return;
    }

    my $response = $ua->get($url);
    unless ($response->is_success) {
        Irssi::print("$SCRIPT_NAME: failed to fetch feed ($url): " . $response->status_line);
        return;
    }

    my $rss = XML::RSS->new();
    eval {
        $rss->parse($response->decoded_content);
    };
    if ($@) {
        Irssi::print("$SCRIPT_NAME: failed to parse RSS feed: $@");
        return;
    }

    my @items = @{ $rss->{items} || [] };
    @items = reverse @items;

    my $max_items = Irssi::settings_get_int('rss_reader_max_items');
    $max_items = 3 if $max_items < 1;

    my @to_announce;
    foreach my $item (@items) {
        my $id = $item->{guid} || $item->{link} || $item->{title};
        next unless defined $id && length $id;

        my $is_new = !$seen_ids{$id};
        $seen_ids{$id} = 1;

        if ($manual_request) {
            push @to_announce, $item;
            next;
        }

        if ($first_poll) {
            next;
        }

        push @to_announce, $item if $is_new;
    }

    trim_seen_cache();

    if ($manual_request && @to_announce > $max_items) {
        @to_announce = @to_announce[-$max_items .. -1];
    }

    foreach my $item (@to_announce) {
        my $title = decode_entities($item->{title} // '(no title)');
        my $link = $item->{link} // '';
        my $line = $link ne '' ? "$title -> $link" : $title;
        broadcast_message($line);
    }

    $first_poll = 0;

    if ($manual_request) {
        Irssi::print("$SCRIPT_NAME: announced " . scalar(@to_announce) . " item(s).");
    }
}

sub timer_tick {
    my $interval = Irssi::settings_get_int('rss_reader_interval');
    $interval = 300 if $interval < 10;

    my $now = time;
    return if ($now - $last_poll) < $interval;

    $last_poll = $now;
    fetch_and_process_feed(0);
}

sub cmd_seturl {
    my ($data) = @_;
    $data //= '';
    $data =~ s/^\s+|\s+$//g;

    unless ($data =~ m{^https?://}i) {
        Irssi::print("$SCRIPT_NAME: usage: /rss_reader_seturl <http(s)://...>");
        return;
    }

    Irssi::settings_set_str('rss_reader_url', $data);
    Irssi::print("$SCRIPT_NAME: URL set to $data");
}

sub cmd_addchan {
    my ($data) = @_;
    my $channel = normalize_channel($data);

    unless ($channel =~ /^#\S+/) {
        Irssi::print("$SCRIPT_NAME: usage: /rss_reader_addchan <#channel>");
        return;
    }

    my @channels = get_enabled_channels();
    push @channels, $channel;
    save_enabled_channels(@channels);
    Irssi::print("$SCRIPT_NAME: channel added: $channel");
}

sub cmd_delchan {
    my ($data) = @_;
    my $channel = normalize_channel($data);

    unless ($channel =~ /^#\S+/) {
        Irssi::print("$SCRIPT_NAME: usage: /rss_reader_delchan <#channel>");
        return;
    }

    my @channels = grep { $_ ne $channel } get_enabled_channels();
    save_enabled_channels(@channels);
    Irssi::print("$SCRIPT_NAME: channel removed: $channel");
}

sub cmd_list {
    my @channels = get_enabled_channels();
    my $url = Irssi::settings_get_str('rss_reader_url') || '(not set)';
    my $interval = Irssi::settings_get_int('rss_reader_interval');
    my $max_items = Irssi::settings_get_int('rss_reader_max_items');

    Irssi::print("$SCRIPT_NAME settings:");
    Irssi::print("  URL: $url");
    Irssi::print("  Interval: $interval sec");
    Irssi::print("  Manual update max items: $max_items");
    Irssi::print('  Channels: ' . (@channels ? join(', ', @channels) : '(none)'));
}

sub cmd_update {
    fetch_and_process_feed(1);
}

Irssi::settings_add_str('rss_reader', 'rss_reader_url', '');
Irssi::settings_add_str('rss_reader', 'rss_reader_channels', '');
Irssi::settings_add_int('rss_reader', 'rss_reader_interval', 300);
Irssi::settings_add_int('rss_reader', 'rss_reader_max_items', 3);

Irssi::command_bind('rss_reader_help', \&print_help);
Irssi::command_bind('rss_reader_seturl', \&cmd_seturl);
Irssi::command_bind('rss_reader_addchan', \&cmd_addchan);
Irssi::command_bind('rss_reader_delchan', \&cmd_delchan);
Irssi::command_bind('rss_reader_list', \&cmd_list);
Irssi::command_bind('rss_reader_update', \&cmd_update);

Irssi::timeout_add(60_000, 'timer_tick', undef);

Irssi::print("$SCRIPT_NAME v$VERSION loaded. Use /rss_reader_help for commands.");
