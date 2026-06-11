#!/usr/bin/env perl
use strict;
use warnings;
use Socket qw(AF_INET6 inet_pton);

# Check whether an input string is a valid IPv6 address.

sub is_ipv6 {
    my ($value) = @_;

    return 0 if !defined $value || $value eq '';

    return defined inet_pton(AF_INET6, $value) ? 1 : 0;
}

if (@ARGV != 1) {
    print "Usage: $0 <ip>\n";
    exit 2;
}

my $input = $ARGV[0];

if (is_ipv6($input)) {
    print "valid ipv6\n";
    exit 0;
}

print "not ipv6\n";
exit 1;
