#!/usr/bin/perl
# Matija Nalis <mnalis-perl@voyager.hr> GPLv3+ started 2020-04-15
# converts data from Mediagoblin instance to static html

use warnings;
use strict;
use DBI;
use autodie qw/:all/;
use Data::Dumper;

use feature 'say';

my $DB_NAME = 'mediagoblin';
my $MG_ROOT = '/var/lib/mediagoblin/default/media/public/media_entries';

#
# no user serviceable parts below
#

my $dbh = DBI->connect("dbi:Pg:dbname=$DB_NAME", '', '', {AutoCommit => 0, RaiseError => 1});

my $sth = $dbh->prepare('SELECT * from core__users');
$sth->execute();

say Dumper($sth->fetchall_hashref('username'));


$dbh->disconnect;
