use strict;
use vars qw($VERSION %IRSSI);

use Irssi qw(command_bind signal_add);
use IO::File;
$VERSION = '0.00.05';
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

# Generate a standard deck of 52 cards
my @suits  = ('♠', '♥', '♦', '♣');
my @values = ('A', 2, 3, 4, 5, 6, 7, 8, 9, 10, 'J', 'Q', 'K');
@deck = ();
for my $suit (@suits) {
    for my $value (@values) {
        push @deck, "$value$suit";
    }
}
push @deck, "Joker🃏";   # add joker

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	question($server, $msg, $nick, $target);
}

sub question($server, $msg, $nick, $target) {
	my ($server, $msg, $nick, $target) = @_;
	$_ = $msg;
	my $answer = "";
	
	if (/^!poker/i) {
        my @hand = get_five_random_cards($nick);
        my $hand_str = join(", ", @hand);
        # remove space after commas
        $hand_str =~ s/,\s+(\0034)/,$1/g;
        $server->command("msg $target $nick, Your hand:$hand_str");
        return;
    } elsif (/^!shuffle/i) {
        %$used_cards = ();
        %$players = ();
        $server->command("msg $target Deck shuffled. All cards are back in the deck. Time to start a new round.");
        return;
    } elsif (/^!hold\s+((?:\d+\s*)+)$/i) {
        my @hold_numbers = split /\s+/, $1;
        my @new_hand = hold_cards_by_number($nick, @hold_numbers);
        my $hand_str = join(", ", @new_hand);
        # remove space after commas
        $hand_str =~ s/,\s+(\0034)/,$1/g;
        $server->command("msg $target $nick, Your new hand:$hand_str");
        return;
    } else {
        return;
    }
}

sub get_five_random_cards {
    my $nick = shift;
    # when dealing fresh hands to players.
    if (scalar(keys %$used_cards) > 48) {
        return ("No more cards in the deck. Please shuffle the deck with !shuffle command.");
    }
    my @hand = ();
    my $index = 0;
    while (scalar(@hand) < 5) {
        $index++;
        my $card = get_one_random_card();
        my $colored_card = '';
        if ($card =~ /(♦|♥)$/) {
            $colored_card = "\0034 " . ${card} . "\003";  # \0034 is red in IRC color codes
        } else {
            $colored_card = $card;  # \0031 is blue in IRC color codes
        }
        push @hand, $colored_card || $card;
        $players->{$nick}->{$index} = $card;
    }
    return @hand;
}

sub get_one_random_card {
    while (1) {
        my $random_index = int(rand(scalar(@deck)));
        my $card = $deck[$random_index];
        next if exists $used_cards->{$card};
        $used_cards->{$card} = 1;
        return $card;
    }
}

sub hold_cards_by_number {
    # hold cards by their position in the hand (1-5) and replace the rest with new random cards
    my ($nick, @hold_numbers) = @_;
    my $player_cards = $players->{$nick} || {};
    my @held_cards = ();
    foreach my $card_index (1..5) {
        if (grep { $_ == $card_index } @hold_numbers) {
            my $colored_card = '';
            if ($player_cards->{$card_index} && $player_cards->{$card_index} =~ /(♦|♥)$/) {
                #$colored_card = "\0034 " . ${$player_cards->{$card_index}} . "\003";  # \0034 is red in IRC color codes
                $colored_card = "\0034 " . $player_cards->{$card_index} . "\003";  # \0034 is red in IRC color codes
            } else {
                $colored_card = $player_cards->{$card_index} || "Unknown Card";  # \0031 is blue in IRC color codes
            }
            push @held_cards, $colored_card || $player_cards->{$card_index} || "Unknown Card";
        } else {
            my $new_card = get_one_random_card();
            my $colored_card = '';
            if ($new_card =~ /(♦|♥)$/) {
                $colored_card = "\0034 " . ${new_card} . "\003";  # \0034 is red in IRC color codes
            } else {
                $colored_card = $new_card;  # \0031 is blue in IRC color codes
            }
            $player_cards->{$card_index} = $new_card;
            push @held_cards, $colored_card || $new_card;
        }
    }
    return @held_cards;
}


signal_add("message public", "sig_msg_pub");

