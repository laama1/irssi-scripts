use strict;
use warnings;
use utf8;
use Irssi;
use LWP::UserAgent;
use JSON::PP qw(decode_json);
use URI::Escape qw(uri_escape_utf8);
use vars qw($VERSION %IRSSI);
use HTML::Entities qw(decode_entities);
use Data::Dumper;

$VERSION = '2026-04-02';
%IRSSI = (
	authors     => 'GitHub Copilot',
	contact     => 'local',
	name        => 'steam_search_irssi.pl',
	description => 'Search Steam store and print game info with /steam',
	license     => 'Public Domain',
	changed     => $VERSION,
);

my $app_details_url = 'https://store.steampowered.com/api/appdetails/?appids=%s&l=%s&cc=%s';

my $ua = LWP::UserAgent->new(
	timeout => 15,
	agent   => 'irssi-steam-search/1.0',
);

sub prind {
	my ($text, @rest) = @_;
	print "\0039" . $IRSSI{name} . ">\003 " . $text;
}

sub prindw {
	my ($text, @rest) = @_;
	print "\0034" . $IRSSI{name} . ">\003 " . $text;
}

sub print_help {
	prind('commands:');
	prind('/steam <search words>          - search Steam store');
	prind('/steam_help                    - show this help');
	prind('/steam_setcc <countrycode>     - set country code (default us)');
	prind('/steam_setlang <language>      - set Steam language (default english)');
	prind('/steam_setlimit <1-10>         - set max result lines for /steam');
	prind('/steam_list                    - show current settings');
}

sub cmd_list {
	my $cc = Irssi::settings_get_str('steam_search_cc') || 'us';
	my $lang = Irssi::settings_get_str('steam_search_lang') || 'english';
	my $limit = Irssi::settings_get_int('steam_search_limit');
	$limit = 3 if $limit < 1;
	prind("settings: cc=$cc, lang=$lang, limit=$limit");
}

sub cmd_setcc {
	my ($data) = @_;
	$data //= '';
	$data =~ s/^\s+|\s+$//g;
	$data = lc $data;

	unless ($data =~ /^[a-z]{2}$/) {
		prindw('usage: /steam_setcc <2-letter country code>');
		return;
	}

	Irssi::settings_set_str('steam_search_cc', $data);
	prind("country code set to $data");
}

sub cmd_setlang {
	my ($data) = @_;
	$data //= '';
	$data =~ s/^\s+|\s+$//g;

	unless (length $data) {
		prindw('usage: /steam_setlang <steam language string>');
		return;
	}

	Irssi::settings_set_str('steam_search_lang', $data);
	prind("language set to $data");
}

sub cmd_setlimit {
	my ($data) = @_;
	$data //= '';
	$data =~ s/^\s+|\s+$//g;

	unless ($data =~ /^\d+$/) {
		prindw('usage: /steam_setlimit <1-10>');
		return;
	}

	my $limit = $data + 0;
	if ($limit < 1 || $limit > 10) {
		prindw('limit must be 1-10');
		return;
	}

	Irssi::settings_set_int('steam_search_limit', $limit);
	prind("limit set to $limit");
}

sub send_output {
	my ($server, $witem, $line) = @_;
	return prind($line) unless $server;

	if ($witem && $witem->{type} && ($witem->{type} eq 'CHANNEL' || $witem->{type} eq 'QUERY')) {
		$server->command("msg $witem->{name} $line");
		return;
	}

	prind($line);
}

sub cents_to_amount {
	my ($value) = @_;
	return undef if !defined $value || $value !~ /^\d+$/;
	return $value / 100;
}

sub format_price {
	my ($price) = @_;
	return 'free/unknown' if ref $price ne 'HASH';

	my $currency = $price->{currency} // '';
	my $initial = cents_to_amount($price->{initial});
	my $final = cents_to_amount($price->{final});

	return 'free' if defined $final && $final == 0;

	if (defined $initial && defined $final && $initial > $final) {
		return sprintf('%s %.2f (sale %.2f)', $currency || '', $final, $initial) =~ s/^\s+//r;
	}

	if (defined $final) {
		return sprintf('%s %.2f', $currency || '', $final) =~ s/^\s+//r;
	}

	return 'unknown';
}

sub cmd_steam {
	my ($data, $server, $witem) = @_;
	$data //= '';
	$data =~ s/^\s+|\s+$//g;

	unless (length $data) {
		prindw('usage: /steam <search words>');
		return;
	}

	my $cc = Irssi::settings_get_str('steam_search_cc') || 'fi';
	my $lang = Irssi::settings_get_str('steam_search_lang') || 'english';
	my $limit = Irssi::settings_get_int('steam_search_limit') || 3;
	$limit = 3 if $limit < 1;
	$limit = 10 if $limit > 10;

	my $url = sprintf(
		'https://store.steampowered.com/api/storesearch/?term=%s&l=%s&cc=%s',
		uri_escape_utf8($data),
		uri_escape_utf8($lang),
		uri_escape_utf8($cc),
	);

	my $res = $ua->get($url);
	unless ($res->is_success) {
		prindw('steam request failed: ' . $res->status_line);
		return;
	}

	my $payload;
	eval {
		$payload = decode_json($res->decoded_content);
        #print __LINE__ . ': '. $res->decoded_content;
		1;
	};
	if (!$payload || ref $payload ne 'HASH' || ref $payload->{items} ne 'ARRAY') {
		prindw('unexpected Steam response.');
		return;
	}

	my $items = $payload->{items};
	my $total = $payload->{total} // scalar(@$items);
	if (!@$items) {
		send_output($server, $witem, "Steam: no results for '$data'.");
		return;
	}
	if ($total < $limit) {
		$limit = $total;
	}

	send_output($server, $witem, "Steam search '$data' ($total matches, showing $limit)");

	my $shown = 0;
	foreach my $item (@$items) {
		last if $shown >= $limit;
		my $name = $item->{name} // '(no name)';
		my $id = $item->{id} // '';
		my $type = $item->{type} // 'app';
		my $metascore = defined $item->{metascore} && $item->{metascore} ne '' ? $item->{metascore} : 'n/a';
		my $price = format_price($item->{price});
		my $url_item = $id ne '' ? "https://store.steampowered.com/$type/$id/" : '';
        my $desc = fetch_description($id);
		my $line = ($shown + 1) . ". $name | $price | metascore $metascore";
		$line .= " | $url_item | " if $url_item ne '';
        $line .= "$desc" if $desc ne '';
		send_output($server, $witem, $line);
		$shown++;
	}
}

sub fetch_description {
    my ($id, @rest) = @_;

	my $cc = Irssi::settings_get_str('steam_search_cc') || 'us';
	my $lang = Irssi::settings_get_str('steam_search_lang') || 'english';
	#my $limit = Irssi::settings_get_int('steam_search_limit');
	#$limit = 3 if $limit < 1;
	#$limit = 10 if $limit > 10;

	my $url = sprintf(
		'https://store.steampowered.com/api/appdetails/?appids=%s&l=%s&cc=%s',
		uri_escape_utf8($id),
		uri_escape_utf8($lang),
		uri_escape_utf8($cc),
	);

    my $res = $ua->get($url);
	unless ($res->is_success) {
		prindw('steam request failed: ' . $res->status_line);
		return;
	}

	my $payload;
	eval {
		$payload = decode_json($res->decoded_content);
		1;
	};
#    print __LINE__ . ': ' . $res->decoded_content;
	if (!$payload || ref $payload ne 'HASH' ) { #|| ref $payload->{data} ne 'ARRAY') {
		prindw('unexpected Steam response.');
		return;
	}
    my $short_desc = decode_entities($payload->{$id}->{data}->{short_description});
    #print Dumper __LINE__ . ': ' . $payload->{$id}->{data};
    return $short_desc;
}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	return unless defined $msg;
	return if defined $server->{nick} && lc($nick // '') eq lc($server->{nick} // '');

	return unless $msg =~ /^!steam(?:\s+(.*))?$/i;
	my $query = $1 // '';
	$query =~ s/^\s+|\s+$//g;

	if ($query eq '') {
		$server->command("msg $target usage: !steam <search words>");
		return;
	}

	my $witem = $server->channel_find($target) || $server->query_find($target);
	cmd_steam($query, $server, $witem);
}

Irssi::settings_add_str('steam_search', 'steam_search_cc', 'us');
Irssi::settings_add_str('steam_search', 'steam_search_lang', 'english');
Irssi::settings_add_int('steam_search', 'steam_search_limit', 3);

Irssi::command_bind('steam', \&cmd_steam);
Irssi::command_bind('steam_help', \&print_help);
Irssi::command_bind('steam_setcc', \&cmd_setcc);
Irssi::command_bind('steam_setlang', \&cmd_setlang);
Irssi::command_bind('steam_setlimit', \&cmd_setlimit);
Irssi::command_bind('steam_list', \&cmd_list);
Irssi::signal_add('message public', \&sig_msg_pub);

prind("$VERSION loaded. Use /steam_help for commands.");
