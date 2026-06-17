use strict;
use vars qw($VERSION %IRSSI);
use utf8;
use Irssi;
use IO::File;
use DBI;
$VERSION = '0.02.06';
%IRSSI = (
	authors			=> 'LAama1',
	contact			=> 'laama@8u.fi',
	name			=> 'poker',
	description		=> 'Poker simulator that will give 5 random cards from the deck when you write !poker. All played cards are removed from the deck until the deck is shuffled with command !shuffle.',
	license			=> 'GNU GPL Version 2 or later',
	url				=> 'http://www.enumerator.org/component/option,com_docman/task,view_category/Itemid,34/subcat,7/'	
);

my $used_cards = {};
my @deck = ();
my $players = {};
my $table_timers = {};
my $table_activity_seq = {};
my $stats_db_file = Irssi::get_irssi_dir() . '/scripts/poker_stats.sqlite';
my $DEBUG = 1;

=pod

Poker hand ranking (highest to lowest)

1. Royal Flush
    A, K, Q, J, 10 of the same suit.

2. Straight Flush
    Five consecutive cards of the same suit.

3. Four of a Kind
    Four cards of the same rank.

4. Full House
    Three of a kind plus a pair.

5. Flush
    Five cards of the same suit, not consecutive.

6. Straight
    Five consecutive cards, not all the same suit.

7. Three of a Kind
    Three cards of the same rank.

8. Two Pair
    Two different pairs.

9. One Pair
    Two cards of the same rank.

10. High Card
     None of the above; highest card wins.

Tie-break notes:
- If two hands are the same type, compare the highest relevant card(s).
- If still tied, compare next highest card(s) (kickers).
- If all ranks are equal, the hand is a tie.

Joker handling:
Real cards	                        Joker becomes	                        Result
--------------------------------------------------------------------------------------------
4 same suit, all from {10,J,Q,K,A}	missing royal card	                    Royal Flush
4 same suit, 4 consecutive ranks	missing rank	                        Straight Flush
4 of same rank	                    5th of same rank	                    Five of a Kind
3 of same rank	                    4th of same rank	                    Four of a Kind
Two pairs	                        3rd of either pair	                    Full House
4 same suit	                        matching suit	                        Flush
4 consecutive ranks (not same suit)	missing rank	                        Straight
One pair	                        3rd of same rank	                    Three of a Kind
All different	                    pairs with best card	                One Pair

=cut


# Generate a standard deck of 52 cards
my @suits  = ('♠', '♥', '♦', '♣');
my @values = ('A', 2, 3, 4, 5, 6, 7, 8, 9, 10, 'J', 'Q', 'K');

# initialize the deck
for my $suit (@suits) {
    for my $value (@values) {
        push @deck, "$value$suit";
    }
}

push @deck, "Joker🃏";   # add one joker

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	ask_question($server, $msg, $nick, $target);
}

sub get_stats_dbh {
    my $dbh;
    eval {
        $dbh = DBI->connect(
            "dbi:SQLite:dbname=$stats_db_file",
            "",
            "",
            {
                RaiseError => 1,
                PrintError => 0,
                AutoCommit => 1,
            }
        );
    };
    if ($@) {
        prind("Stats DB connect failed: $@") if $DEBUG;
        return;
    }
    return $dbh;
}

sub init_stats_db {
    my $dbh = get_stats_dbh();
    return if !defined $dbh;

    eval {
        $dbh->do(q{
            CREATE TABLE IF NOT EXISTS poker_channel_stats (
                channel TEXT PRIMARY KEY,
                rounds_played INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        });

        $dbh->do(q{
            CREATE TABLE IF NOT EXISTS poker_player_stats (
                channel TEXT NOT NULL,
                nick TEXT NOT NULL,
                hands_played INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (channel, nick)
            )
        });
    };

    if ($@) {
        prind("Stats DB schema init failed: $@") if $DEBUG;
    }

    $dbh->disconnect;
}

sub add_hand_stats {
    my ($target, $nick, $is_new_round) = @_;
    my $dbh = get_stats_dbh();
    return if !defined $dbh;

    eval {
        if ($is_new_round) {
            $dbh->do(
                'INSERT OR IGNORE INTO poker_channel_stats (channel, rounds_played) VALUES (?, 0)',
                undef,
                $target
            );
            $dbh->do(
                'UPDATE poker_channel_stats SET rounds_played = rounds_played + 1, updated_at = CURRENT_TIMESTAMP WHERE channel = ?',
                undef,
                $target
            );
        }

        $dbh->do(
            'INSERT OR IGNORE INTO poker_player_stats (channel, nick, hands_played) VALUES (?, ?, 0)',
            undef,
            $target,
            $nick
        );
        $dbh->do(
            'UPDATE poker_player_stats SET hands_played = hands_played + 1, updated_at = CURRENT_TIMESTAMP WHERE channel = ? AND nick = ?',
            undef,
            $target,
            $nick
        );
    };

    if ($@) {
        prind("Stats DB update failed: $@") if $DEBUG;
    }

    $dbh->disconnect;
}

sub get_channel_rounds_played {
    my ($target) = @_;
    my $dbh = get_stats_dbh();
    return 0 if !defined $dbh;

    my $rounds = 0;
    eval {
        my $sth = $dbh->prepare('SELECT rounds_played FROM poker_channel_stats WHERE channel = ?');
        $sth->execute($target);
        my ($value) = $sth->fetchrow_array;
        $rounds = defined $value ? $value : 0;
        $sth->finish;
    };

    if ($@) {
        prind("Stats DB read failed (rounds): $@") if $DEBUG;
    }

    $dbh->disconnect;
    return $rounds;
}

sub get_channel_top_players {
    my ($target, $limit) = @_;
    $limit = 5 if !defined $limit;

    my $dbh = get_stats_dbh();
    return () if !defined $dbh;

    my @rows = ();
    eval {
        my $sth = $dbh->prepare('SELECT nick, hands_played FROM poker_player_stats WHERE channel = ? ORDER BY hands_played DESC, nick ASC LIMIT ?');
        $sth->execute($target, $limit);
        while (my ($nick, $hands_played) = $sth->fetchrow_array) {
            push @rows, {
                nick => $nick,
                hands_played => $hands_played,
            };
        }
        $sth->finish;
    };

    if ($@) {
        prind("Stats DB read failed (players): $@") if $DEBUG;
    }

    $dbh->disconnect;
    return @rows;
}

sub ask_question {
	my ($server, $msg, $nick, $target) = @_;
	$_ = $msg;
	my $answer = "";
	
	if (/^!poker\s+stats(?:\s+(\d+))?$/i) {
        my $limit = defined $1 ? $1 : 5;
        $limit = 1 if $limit < 1;
        $limit = 20 if $limit > 20;

        my $rounds = get_channel_rounds_played($target);
        my @top_players = get_channel_top_players($target, $limit);

        my $players_text = scalar(@top_players)
            ? join(', ', map { $_->{nick} . ': ' . $_->{hands_played} } @top_players)
            : 'no player stats yet';

        $server->command("msg $target Poker stats for $target | rounds played: $rounds | top players: $players_text");
        return;
    } elsif (/^!poker/i) {
        my $is_new_round = (!defined $used_cards->{$target} || scalar(keys %{$used_cards->{$target}}) == 0) ? 1 : 0;
        if (defined $players->{$target}->{$nick}) {
            $server->command("msg $target $nick, You already have a hand. Use !hold command to hold cards and get new ones, or !shuffle to start a new round.");
            return;
        }
        my @hand = get_five_random_cards($target, $nick);
        if (scalar(@hand) == 1 && $hand[0] =~ /^No more cards in the deck/) {
            $server->command("msg $target $hand[0]");
            return;
        }
        add_hand_stats($target, $nick, $is_new_round);
        #my $hand_str = join(", ", @hand);
        # remove space after commas
        
        my $hand_str = format_hand_with_colors(@hand);
        my ($is_winning, $hand_name) = check_player_winning_hand($target, $nick);
        my $result_text = $is_winning ? "Winning hand: $hand_name" : "No winning hand ($hand_name)";
        $server->command("msg $target $nick, Your hand:$hand_str - $result_text");
        restart_inactivity_timer($server, $target);
        
        return;
    } elsif (/^!shuffle/i) {
        announce_round_winner($server, $target);
        clear_table_state($target);
        stop_inactivity_timer($target);
        $server->command("msg $target Deck shuffled. All cards are back in the deck. Time to start a new round.");
        return;
    } elsif (/^!hold\s+((?:\d+\s*)+)$/i) {
        if (not defined $players->{$target}->{$nick}) {
            $server->command("msg $target $nick, You don't have a hand to hold cards from. Use !poker to get a hand first.");
            return;
        }
        if ($players->{$target}->{$nick}->{held}) {
            $server->command("msg $target $nick, You can only hold cards once per game. Wait for !shuffle.");
            return;
        }
        $players->{$target}->{$nick}->{held} = 1;
        my @hold_numbers = split /\s+/, $1;
        my @new_hand = hold_cards_by_number($target, $nick, @hold_numbers);
        my $hand_str = format_hand_with_colors(@new_hand);
        my ($is_winning, $hand_name) = check_player_winning_hand($target, $nick);
        my $result_text = $is_winning ? "Winning hand: $hand_name" : "No winning hand ($hand_name)";
        $server->command("msg $target $nick, Your new hand:$hand_str - $result_text");
        restart_inactivity_timer($server, $target);
        return;
    } else {
        return;
    }
}

sub clear_table_state {
    my ($target) = @_;
    delete $used_cards->{$target};
    delete $players->{$target};
}

sub announce_round_winner {
    my ($server, $target) = @_;
    return if !defined $server || !defined $target;

    my $result = compare_current_players_hands($target);
    if (!defined $result) {
        $server->command("msg $target Round ended. No complete hands to compare.");
        return;
    }

    my @winners = @{ $result->{winners} || [] };
    return if !@winners;

    my $winning_hand = $result->{winning_hand} || 'High Card';
    if (scalar(@winners) == 1) {
        my $winner = $winners[0];
        my $cards_text = format_hand_with_colors(@{ $winner->{cards} || [] });
        $server->command("msg $target Round winner: $winner->{nick} with $winning_hand ($cards_text)");
        return;
    }

    my $winner_nicks = join(', ', map { $_->{nick} } @winners);
    $server->command("msg $target Round tied: $winner_nicks with $winning_hand");
}

sub stop_inactivity_timer {
    my ($target) = @_;
    if (defined $table_timers->{$target}) {
        Irssi::timeout_remove($table_timers->{$target});
        delete $table_timers->{$target};
    }
}

sub restart_inactivity_timer {
    my ($server, $target) = @_;
    stop_inactivity_timer($target);

    $table_activity_seq->{$target} = ($table_activity_seq->{$target} || 0) + 1;
    my $seq = $table_activity_seq->{$target};
    my $server_tag = $server->{tag} || '';
    my $timer_data = join("\x1f", $target, $server_tag, $seq);

    $table_timers->{$target} = Irssi::timeout_add_once(60_000, 'table_inactivity_timeout', $timer_data);
}

sub table_inactivity_timeout {
    my ($timer_data) = @_;
    my ($target, $server_tag, $seq) = split(/\x1f/, $timer_data, 3);

    # Ignore stale timers that were superseded by newer actions.
    return if !defined $target;
    return if !defined $table_activity_seq->{$target};
    return if $table_activity_seq->{$target} != $seq;

    my $server = Irssi::server_find_tag($server_tag);
    if (defined $server) {
        announce_round_winner($server, $target);
    }

    clear_table_state($target);
    delete $table_timers->{$target};

    if (defined $server) {
        $server->command("msg $target No card actions for 60 seconds. Auto-shuffling this table.");
    }
}

sub get_five_random_cards {
    my ($target, $nick) = @_;
    # when dealing fresh hands to players.
    if (scalar(keys %{$used_cards->{$target}}) > 48) {
        return ("No more cards in the deck. Please shuffle the deck with !shuffle command.");
    }
    my @hand = ();
    my $index = 0;
    while (scalar(@hand) < 5) {
        $index++;
        my $card = get_one_random_card($target);
        push @hand, $card;
        $players->{$target}->{$nick}->{$index} = $card;
    }
    return @hand;
}

sub format_hand_with_colors {
    my (@hand) = @_;
    for my $i (0..$#hand) {
        if ($hand[$i] =~ /(♦|♥)$/) {
            # red cards. add space because otherwise the card number will mix with color code.
            $hand[$i] = "\0034 " . $hand[$i] . "\003";  # \0034 is red in IRC color codes
        }
    }
    my $return_str = join(", ", @hand);
    # double space when red card
    $return_str =~ s/,\s+(\0034)/,$1/g;
    return $return_str;
}

sub get_one_random_card {
    my $target = shift;
    while (1) {
        my $random_index = int(rand(scalar(@deck)));
        my $card = $deck[$random_index];
        next if exists $used_cards->{$target}->{$card};
        $used_cards->{$target}->{$card} = 1;
        return $card;
    }
}

sub hold_cards_by_number {
    # hold cards by their position in the hand (1-5) and replace the rest with new random cards
    my ($target, $nick, @hold_numbers) = @_;
    my $player_cards = $players->{$target}->{$nick} || {};
    my @held_cards = ();
    foreach my $card_index (1..5) {
        if (grep { $_ == $card_index } @hold_numbers) {
            push @held_cards, $player_cards->{$card_index} || "Unknown Card";
        } else {
            my $new_card = get_one_random_card($target);
            $player_cards->{$card_index} = $new_card;
            push @held_cards, $new_card;
        }
    }
    return @held_cards;
}

sub check_player_winning_hand {
    my ($target, $nick) = @_;
    my $player_cards = $players->{$target}->{$nick} || {};
    my @cards = map { $player_cards->{$_} } (1..5);
    return (0, "Incomplete Hand") if grep { !defined $_ } @cards;

    my $hand_name = evaluate_poker_hand(@cards);
    my $is_winning = ($hand_name ne "High Card") ? 1 : 0;
    return ($is_winning, $hand_name);
}

sub parse_card_value_and_suit {
    my ($card) = @_;
    return if !defined $card;
    return if $card =~ /^Joker/;

    my %rank_map = (
        '2'  => 2,  '3'  => 3,  '4'  => 4,  '5'  => 5,
        '6'  => 6,  '7'  => 7,  '8'  => 8,  '9'  => 9,
        '10' => 10, 'J'  => 11, 'Q'  => 12, 'K'  => 13, 'A' => 14,
    );

    $card =~ s/\003\d?//g;
    if ($card =~ /^(10|[2-9JQKA])([♠♥♦♣])/u) {
        return ($rank_map{$1}, $2);
    }
    return;
}

sub score_hand_without_wildcards {
    my ($values_ref, $suits_ref) = @_;
    my @values = sort { $a <=> $b } @{$values_ref};
    my @suits = @{$suits_ref};

    my %rank_counts = ();
    $rank_counts{$_}++ for @values;
    my @groups = sort {
        $rank_counts{$b} <=> $rank_counts{$a}
            || $b <=> $a
    } keys %rank_counts;

    my $is_flush = (scalar(keys %{ { map { $_ => 1 } @suits } }) == 1) ? 1 : 0;

    my $is_straight = 0;
    my $straight_high = 0;
    if (scalar(keys %rank_counts) == 5) {
        my $consecutive = 1;
        for my $i (1..4) {
            if ($values[$i] != $values[$i - 1] + 1) {
                $consecutive = 0;
                last;
            }
        }
        if ($consecutive) {
            $is_straight = 1;
            $straight_high = $values[4];
        } elsif (join(',', @values) eq '2,3,4,5,14') {
            $is_straight = 1;
            $straight_high = 5;
        }
    }

    my @freq = sort { $b <=> $a } values %rank_counts;
    my @desc_values = sort { $b <=> $a } @values;

    if ($freq[0] == 5) {
        return [11, $groups[0]]; # Five of a Kind
    }
    if ($is_straight && $is_flush && $straight_high == 14) {
        return [10]; # Royal Flush
    }
    if ($is_straight && $is_flush) {
        return [9, $straight_high]; # Straight Flush
    }
    if ($freq[0] == 4) {
        my ($quad) = grep { $rank_counts{$_} == 4 } keys %rank_counts;
        my ($kicker) = grep { $rank_counts{$_} == 1 } keys %rank_counts;
        return [8, $quad, $kicker];
    }
    if ($freq[0] == 3 && $freq[1] == 2) {
        my ($trip) = grep { $rank_counts{$_} == 3 } keys %rank_counts;
        my ($pair) = grep { $rank_counts{$_} == 2 } keys %rank_counts;
        return [7, $trip, $pair];
    }
    if ($is_flush) {
        return [6, @desc_values];
    }
    if ($is_straight) {
        return [5, $straight_high];
    }
    if ($freq[0] == 3) {
        my ($trip) = grep { $rank_counts{$_} == 3 } keys %rank_counts;
        my @kickers = sort { $b <=> $a } grep { $rank_counts{$_} == 1 } keys %rank_counts;
        return [4, $trip, @kickers];
    }
    if ($freq[0] == 2 && $freq[1] == 2) {
        my @pairs = sort { $b <=> $a } grep { $rank_counts{$_} == 2 } keys %rank_counts;
        my ($kicker) = grep { $rank_counts{$_} == 1 } keys %rank_counts;
        return [3, $pairs[0], $pairs[1], $kicker];
    }
    if ($freq[0] == 2) {
        my ($pair) = grep { $rank_counts{$_} == 2 } keys %rank_counts;
        my @kickers = sort { $b <=> $a } grep { $rank_counts{$_} == 1 } keys %rank_counts;
        return [2, $pair, @kickers];
    }

    return [1, @desc_values];
}

sub compare_score_arrays {
    my ($a_ref, $b_ref) = @_;
    my $len = @$a_ref > @$b_ref ? scalar(@$a_ref) : scalar(@$b_ref);
    for my $i (0..($len - 1)) {
        my $av = defined $a_ref->[$i] ? $a_ref->[$i] : 0;
        my $bv = defined $b_ref->[$i] ? $b_ref->[$i] : 0;
        return 1 if $av > $bv;
        return -1 if $av < $bv;
    }
    return 0;
}

sub best_hand_score {
    my @cards = @_;
    my @real_values = ();
    my @real_suits = ();
    my $has_joker = 0;

    foreach my $card (@cards) {
        if (defined $card && $card =~ /^Joker/) {
            $has_joker = 1;
            next;
        }
        my ($value, $suit) = parse_card_value_and_suit($card);
        return [1, 0] if !defined $value || !defined $suit;
        push @real_values, $value;
        push @real_suits, $suit;
    }

    if (!$has_joker) {
        return score_hand_without_wildcards(\@real_values, \@real_suits);
    }

    # Try every joker substitution and keep the best hand score.
    my @suits = ('♠', '♥', '♦', '♣');
    my $best = [1, 0];
    for my $value (2..14) {
        for my $suit (@suits) {
            my @values = (@real_values, $value);
            my @all_suits = (@real_suits, $suit);
            my $score = score_hand_without_wildcards(\@values, \@all_suits);
            if (compare_score_arrays($score, $best) > 0) {
                $best = $score;
            }
        }
    }

    return $best;
}

sub hand_name_from_score {
    my ($score_ref) = @_;
    my %hand_name = (
        11 => 'Five of a Kind',
        10 => 'Royal Flush',
        9  => 'Straight Flush',
        8  => 'Four of a Kind',
        7  => 'Full House',
        6  => 'Flush',
        5  => 'Straight',
        4  => 'Three of a Kind',
        3  => 'Two Pair',
        2  => 'One Pair',
        1  => 'High Card',
    );

    my $rank = $score_ref->[0] || 1;
    return $hand_name{$rank} || 'High Card';
}

sub evaluate_poker_hand {
    my @cards = @_;
    my $score_ref = best_hand_score(@cards);
    return hand_name_from_score($score_ref);
}

sub compare_current_players_hands {
    my ($target) = @_;
    my $table_players = $players->{$target} || {};
    my @evaluated = ();

    foreach my $nick (keys %{$table_players}) {
        my @cards = map { $table_players->{$nick}->{$_} } (1..5);
        next if grep { !defined $_ } @cards;

        my $score_ref = best_hand_score(@cards);
        push @evaluated, {
            nick => $nick,
            cards => \@cards,
            score => $score_ref,
            hand_name => hand_name_from_score($score_ref),
        };
    }

    return if !@evaluated;

    my $best_score = $evaluated[0]->{score};
    for my $entry (@evaluated) {
        if (compare_score_arrays($entry->{score}, $best_score) > 0) {
            $best_score = $entry->{score};
        }
    }

    my @winners = grep {
        compare_score_arrays($_->{score}, $best_score) == 0
    } @evaluated;

    return {
        winners => \@winners,
        all_players => \@evaluated,
        winning_hand => hand_name_from_score($best_score),
    };
}

sub prind {
	my ($text, @rest) = @_;
	print("\0034" . $IRSSI{name} . ">\003 ". $text);
}

init_stats_db();

Irssi::signal_add("message public", "sig_msg_pub");

prind("v.$VERSION loaded");
prind("new commands: !shuffle !poker !hold <numbers>");
