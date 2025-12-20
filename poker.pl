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

# Generate a standard deck of 52 cards
my @suits  = ('♠', '♥', '♦', '♣');
my @values = ('A', 2, 3, 4, 5, 6, 7, 8, 9, 10, 'J', 'Q', 'K');
@deck = ();
for my $suit (@suits) {
    for my $value (@values) {
        push @deck, "$value$suit";
    }
    push @deck, "Joker🃏";   # add joker
}


sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	question($server, $msg, $nick, $target);
}

sub question($server, $msg, $nick, $target) {
	my ($server, $msg, $nick, $target) = @_;
	$_ = $msg;
	my $answer = "";
	
	if (/^!poker/i) {
        my @hand = get_five_random_cards();
        my $hand_str = join(", ", @hand);
        # remove space after commas
        $hand_str =~ s/,\s+(\0034)/,$1/g;
        $server->command("msg $target Your hand:$hand_str");
        return;
    } elsif (/^!shuffle/i) {
        %$used_cards = ();
        $server->command("msg $target Deck shuffled. All cards are back in the deck.");
        return;
    } else {
        return;
    }
}

sub get_five_random_cards {
    if (scalar(keys %$used_cards) > 47) {
        return ("No more cards in the deck. Please shuffle the deck with !shuffle command.");
    }
    my @hand = ();
    while (scalar(@hand) < 5) {
        my $random_index = int(rand(scalar(@deck)));
        my $card = $deck[$random_index];
        #Irssi::print("Selected card: $card");

        next if exists $used_cards->{$card};
        # Color red if suit is diamond or hearts
        my $colored_card = '';
        if ($card =~ /(♦|♥)$/) {
            $colored_card = "\0034 " . ${card} . "\003";  # \0034 is red in IRC color codes
        } else {
            $colored_card = $card;  # \0031 is blue in IRC color codes
        }
        push @hand, $colored_card || $card;
        $used_cards->{$card} = 1;
    }
    return @hand;
}


signal_add("message public", "sig_msg_pub");

