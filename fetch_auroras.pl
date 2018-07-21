#!/usr/bin/perl

#export LC_ALL=en_US.UTF8;
# skripti hakee urlista tiedon revontulista.
# KP-arvo tallennetaan tietokantaan myöhempää käyttöä varten.
# LAama1 1.10.2016, 7.9.2017 (minor), 14.3.2018 (copy to kiva.vhosti.fi)

#use HTML::Entities;
#use LWP::UserAgent;
#use LWP::Simple;
use Data::Dumper;

use lib '/home/laama/.irssi/scripts';
use KaaosRadioClass;

use strict;
use DBI qw(:sql_types);

my $DEBUG = 0;
my $myname = 'fetch_auroras.pl';
my $auroraurl = 'http://www.aurora-service.eu/aurora-forecast/';

my $db = '/home/laama/public_html/auroras.db';

unless (-e $db) {
	unless(open FILE, '>'.$db) {
		print STDERR ("$myname: Unable to create file: $db");
		die;
	}
	close FILE;
	
	KaaosRadioClass::writeToDB($db, "CREATE TABLE AURORAS (kpnow TEXT, kp1hforecast TEXT, PVM INT)");
	print("$myname: Database file created.\n") if $DEBUG;
}

grepData();
#saveAuroras():

sub grepData {
	print "$myname: GREPPING DATA\n" if $DEBUG;
	my $stats = KaaosRadioClass::fetchUrl($auroraurl, 0, 20);
	#print Dumper $stats if $DEBUG;

	my $kpnow;
	if ($stats =~ /var kpnow =\s*(\-?\d\.\d{1,3});/) {
		$kpnow = $1;
		print("$myname: Fetching some Auroras is success! ". $kpnow."\n") if $DEBUG;
	}
	
	my $kpst;
	if ($stats =~ /var kpst =\s*(\d\.\d{1,3});/) {
		$kpst = $1;
		print("$myname: Aurora forecast: ".$kpst."\n") if $DEBUG;
	}
	saveAuroras($kpnow, $kpst) if ($kpnow && $kpst);
}

sub saveAuroras {
	my ($value1, $value2) = @_;
	my $dbh = KaaosRadioClass::connectSqlite($db);
	print "$myname: Saving values to db, $value1, $value2\n" if $DEBUG;
	my $time = time();
	#my $string = ;
	my $sth = $dbh->prepare("insert INTO AURORAS values (?, ?, ?)") or die DBI::errstr;
	$sth->bind_param(1, $value1);
	$sth->bind_param(2, $value2);
	$sth->bind_param(3, $time, { TYPE => SQL_INTEGER });
	
	$sth->execute;
	$sth->finish();
	$dbh->disconnect();
}
