use strict;
use vars qw($VERSION %IRSSI);
use utf8;
use Irssi;
use IO::File;
$VERSION = '0.01.06';
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

sub ask_question {
	my ($server, $msg, $nick, $target) = @_;
	$_ = $msg;
	my $answer = "";
	
	if (/^!poker/i) {
        if (defined $players->{$target}->{$nick}) {
            $server->command("msg $target $nick, You already have a hand. Use !hold command to hold cards and get new ones, or !shuffle to start a new round.");
            return;
        }
        my @hand = get_five_random_cards($target, $nick);
        #my $hand_str = join(", ", @hand);
        # remove space after commas
        
        my $hand_str = format_hand_with_colors(@hand);
        my ($is_winning, $hand_name) = check_player_winning_hand($target, $nick);
        my $result_text = $is_winning ? "Winning hand: $hand_name" : "No winning hand ($hand_name)";
        $server->command("msg $target $nick, Your hand:$hand_str - $result_text");
        restart_inactivity_timer($server, $target);
        
        return;
    } elsif (/^!shuffle/i) {
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

    clear_table_state($target);
    delete $table_timers->{$target};

    my $server = Irssi::server_find_tag($server_tag);
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

sub evaluate_poker_hand {
    my @cards = @_;
    my $hand_name = "";
    my $has_joker = 0;
    # Treat joker as a wild card marker for now.
    if (grep { defined $_ && $_ =~ /^Joker/ } @cards) {
        $has_joker = 1;
        return "Joker Wild";
    }

    my %rank_map = (
        '2'  => 2,  '3'  => 3,  '4'  => 4,  '5'  => 5,
        '6'  => 6,  '7'  => 7,  '8'  => 8,  '9'  => 9,
        '10' => 10, 'J'  => 11, 'Q'  => 12, 'K'  => 13, 'A' => 14,
    );

    my %rank_counts = ();
    my %suit_counts = ();
    my @values = ();

    foreach my $card (@cards) {
        next if !defined $card;
        $card =~ s/\\003\d?//g;  # remove IRC color codes
        if ($card =~ /^(10|[2-9JQKA])([♠♥♦♣])/u) {
            # we are not adding Joker to the rank map
            my ($rank, $suit) = ($1, $2);
            my $value = $rank_map{$rank};
            print(__LINE__ . ": Card: $card, Rank: $rank, Suit: $suit, Value: $value") if $DEBUG;
            $rank_counts{$value}++;
            $suit_counts{$suit}++;
            push @values, $value;
        }
    }

    return "High Card" if scalar(@values) != 5;

    # sort cards by value for straight checking
    @values = sort { $a <=> $b } @values;
    my $is_flush = (scalar(keys %suit_counts) == 1) ? 1 : 0;
    print(__LINE__ . ": Values: " . join(", ", @values) . ", is Flush: $is_flush") if $DEBUG;

    my $is_straight = 0;
    my %unique = map { $_ => 1 } @values;
    if (scalar(keys %unique) == 5) {
        # 5 different cards, check if they are consecutive
        my $consecutive = 1;
        for my $i (1..4) {
            print(__LINE__ . ": Checking straight: comparing $values[$i] and " . ($values[$i - 1] + 1)) if $DEBUG;
            if ($values[$i] != $values[$i - 1] + 1) {
                $consecutive = 0;
                last;
            }
        }
        $is_straight = $consecutive;
        # Ace-low straight: A,2,3,4,5
        if (!$is_straight && join(',', @values) eq '2,3,4,5,14') {
            $is_straight = 1;
        }
    }

    my @count_values = sort { $b <=> $a } values %rank_counts;

    if ($is_straight && $is_flush && join(',', @values) eq '10,11,12,13,14') {
        return "Royal Flush";
    }
    if ($is_straight && $is_flush) {
        return "Straight Flush";
    }
    if ($count_values[0] == 4) {
        return "Four of a Kind";
    }
    if ($count_values[0] == 3 && $count_values[1] == 2) {
        return "Full House";
    }
    if ($count_values[0] == 2 && $count_values[1] == 3) {
        return "Full House2";
    }
    if ($is_flush) {
        return "Flush";
    }
    if ($is_straight) {
        return "Straight";
    }
    if ($count_values[0] == 3) {
        return "Three of a Kind";
    }
    if ($count_values[0] == 2 && $count_values[1] == 2) {
        return "Two Pair";
    }
    if ($count_values[0] == 2) {
        return "One Pair";
    }
    return "High Card";
}

sub prind {
	my ($text, @rest) = @_;
	print("\0034" . $IRSSI{name} . ">\003 ". $text);
}

Irssi::signal_add("message public", "sig_msg_pub");

prind("v.$VERSION loaded");
prind("new commands: !shuffle !poker !hold <numbers>");
