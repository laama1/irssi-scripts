use strict;
use Irssi qw(
	settings_get_int settings_get_str
	settings_add_int settings_add_str
	signal_add_last
	);
use Fcntl;
use IO::Handle;
use vars qw($VERSION %IRSSI);

$VERSION = "0.1";
%IRSSI =
(
	authors     => 'LAama1',
	contact		=> 'LAama1@ircnet',
	name        => 'read_fifo',
	description => 'Print fifo to irssi',
	license     => 'GPLv2',
	changed     => '2019-01-01'
);

my $fifo_file = Irssi::get_irssi_dir . '/read.fifo';
my $last_values = {};

my @colors = ("","\033[0;36;40m","\033[1;37;40m","\033[1;35;40m");

sub fifo_stop
{
	close FIFO;
	Irssi::print('Fifo closed.');
}

sub item_status_changed
{
	my ($item, $oldstatus) = @_;
	
	return if ! ref $item->{server};

	my $tag = $item->{server}{tag};
	my $name = $item->{name};

	return if ! $tag || ! $name;

	store_status() if ! $last_values->{$tag}{$name} ||
	$last_values->{$tag}{$name}{level} != $item->{data_level};
}


sub store_status
{
	my $new_values = {};
	my @items = ();

	for my $window ( sort { $a->{refnum} <=> $b->{refnum} } Irssi::windows() )
	{

		for my $item ( $window->items() )
		{

			next if ! ref $item->{server};

			my $tag = $item->{server}{tag};
			my $name = $item->{name};

			next if ! $tag || ! $name || $item->{data_level} == 0;

			$new_values->{$tag}{$name} =
			{
				level => $item->{data_level},
				window => $window->{refnum},
			};

			push @items, $new_values->{$tag}{$name};
		}
	}


	print FIFO "\033[2J\033[1;1H" or fifo_stop();

	my $maxw = settings_get_int('act_fifo_width');
	my $w = 0;

	if(scalar(@items) > 0)
	{
		my $hi = settings_get_int('act_fifo_hilight');
		if($hi == 1)
		{
			print FIFO "ACT:" or fifo_stop();
			$w += 4;

		}
		elsif($hi == 2)
		{
			print FIFO "\033[1;37;41mACT:\033[0m" or fifo_stop();
			$w += 4;
		}
		elsif($hi > 2)
		{
			print FIFO "\033[1;37;41m ACT: \033[0m" or fifo_stop();
			$w += 6;
		}
	}

	for ( @items )
	{
		my $win = $_->{window};
		my $winw = int(log($win)/log(10))+1;
		if($winw + 2 + $w > $maxw)
		{
			print FIFO "\033[1;31;40mM\033[0m";
			last;
		}
		print FIFO "$colors[$_->{level}] $win\033[0m" or fifo_stop();
		$w += $winw + 1;
	}


	$last_values = $new_values;

}

sub msg_to_fifo {
	my ($msg, @rest) = @_;
	print FIFO "caca";

}

sub read_fifo {
	my $fifo_fh;
	my $fifo_file = Irssi::get_irssi_dir.'/read.fifo';
	open($fifo_fh, "+< $fifo_file") or die "The FIFO file \"$fifo_file\" is missing, and this program can't run without it.";
	# just keep reading from the fifo and processing the events we read
	my $stopsign = 0;
	#while (<$fifo_fh> && $stopsign == 0)
	if (<$fifo_fh> && $stopsign == 0)
	{
		$stopsign = &handle_fifo_record($_);
	}

	# should never really come down here ...
	close $fifo_fh;
	#exit(0);
}

sub handle_fifo_record {
	my ($string, @rest) = @_;
	Irssi::print('fifo: '.$string);
	if ($string =~ /stop/i) {
		return 1;
	}
	return 0;
}

sub flush_fifo {

}
settings_add_int('act_fifo','act_fifo_width',25);
settings_add_int('act_fifo','act_fifo_hilight',2);
settings_add_str('act_fifo', 'act_fifo_path', Irssi::get_irssi_dir . '/act_fifo');

## open/create FIFO
my $path = settings_get_str('act_fifo_path');
unless (-p $path)
{ # not a pipe
	if (-e _)
	{ # but a something else
		die "$0: $path exists and is not a pipe, please remove it\n";
	}
	else
	{
		require POSIX;
		POSIX::mkfifo($path, oct(666)) or die "can\'t mkfifo $path: $!";
		Irssi::print("Fifo created. Start reading it (\"cat $path\") and try again.");
		return;
	}
}
if (!sysopen(FIFO, $path, O_WRONLY | O_NONBLOCK))
{ # or die "can't write $path: $!";
	print("Couldn\'t write to the fifo ($!). Please start reading the fifo (\"cat $path\") and try again.");
	return;
}
FIFO->autoflush(1);
print FIFO "\033[2J\033[1;1H"; # erase screen & jump to 0,0

# store initial status
store_status();
Irssi::print('act_fifo.pl loaded.');
Irssi::command_bind('act_fifo', \&msg_to_fifo, 'read_fifo');
Irssi::command_bind('act_fifo_read', \&read_fifo, 'read_fifo');
Irssi::command_bind('act_fifo_flush', \&flush_fifo, 'read_fifo');
signal_add_last('setup changed', \&store_status);
signal_add_last('window item activity', \&item_status_changed);
signal_add_last('window refnum changed', \&store_status);

