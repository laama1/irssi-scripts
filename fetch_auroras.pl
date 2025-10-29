#!/usr/bin/perl

#export LC_ALL=en_US.UTF8;
# skripti hakee urlista tiedon revontulista.
# KP-arvo tallennetaan tietokantaan myöhempää käyttöä varten.
# Skripti ajetaan esim. crontabissa näin: 0,30 * * * * /usr/bin/perl /home/laama/.irssi/scripts/irssi-scripts/fetch_auroras.pl
# LAama1 1.10.2016, 7.9.2017 (minor), 14.3.2018 (copy to kiva.vhosti.fi)
use strict;
use Data::Dumper;
#use Irssi;
use lib $ENV{HOME}.'/.irssi/scripts/irssi-scripts';
#use lib Irssi::get_irssi_dir() . '/scripts/irssi-scripts';	# LAama1 2024-07-26
use KaaosRadioClass;
use JSON;

use DBI qw(:sql_types);

my $DEBUG = 0;
my $myname = 'fetch_auroras.pl';
#my $auroraurl = 'http://www.aurora-service.eu/aurora-forecast/';
my $auroraurl = 'http://www.aurora-service.org/aurora-forecast/';
my $aurorasliveurl = 'http://api.auroras.live/v1/';

my $db = $ENV{HOME}.'/public_html/auroras.db';

unless (-e $db) {
	unless(open FILE, '>'.$db) {
		print STDERR ("$myname: Unable to create file: $db");
		die;
	}
	close FILE;
	
	KaaosRadioClass::writeToDB($db, 'CREATE TABLE AURORAS (kpnow TEXT, kp1hforecast TEXT, PVM INT,BZ, DENSITY, SPEED, RFCDATE)');
	print("$myname: Database file created.\n") if $DEBUG;
}

#grepData();
grepJSON();
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

sub grepJSON {
	my $params = '?type=ace&data=all';
	my $json = KaaosRadioClass::getJSON($aurorasliveurl . $params);
	if ($json == "-1") {
		return;
	}
	#print Dumper $json;
	# TODO: sanity check
	my $kp = $json->{kp};
	my $kp1 = $json->{kp1hour};
	my $bz = $json->{bz};
	my $density = $json->{density};		# proton density
	my $speed = $json->{speed};			# proton speed
	my $rfcdate = $json->{date};		# RFC date
	saveAuroras($kp, $kp1, $bz, $density, $speed, $rfcdate);
}

sub saveAuroras {
	my ($value1, $value2, $bz, $density, $speeed, $rfcdate) = @_;
	my $dbh = KaaosRadioClass::connectSqlite($db);
	print "$myname: Saving values to db, $value1, $value2\n" if $DEBUG;
	my $time = time();
	#my $string = ;
	my $sth = $dbh->prepare("insert INTO AURORAS values (?, ?, ?, ?, ?, ?, ?)") or die DBI::errstr;
	$sth->bind_param(1, $value1);
	$sth->bind_param(2, $value2);
	$sth->bind_param(3, $time, { TYPE => SQL_INTEGER });
	$sth->bind_param(4, $bz);
	$sth->bind_param(5, $density);
	$sth->bind_param(6, $speeed);
	$sth->bind_param(7, $rfcdate);
	
	$sth->execute;
	$sth->finish();
	$dbh->disconnect();
}
