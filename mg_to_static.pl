#!/usr/bin/perl
# Matija Nalis <mnalis-perl@voyager.hr> GPLv3+ started 2020-04-15
# converts data from Mediagoblin instance to static html
#
# run as: 
#   sudo -u postgres ./mg_to_static.pl > runme.sh && sh runme.sh
#

use warnings;
use strict;
use autodie qw/:all/;
use feature 'say';

use DBI;
use Data::Dumper;
use HTML::Template;
use FindBin qw( $RealBin );

my $DB_NAME = 'mediagoblin';
my $MG_ROOT = '/var/lib/mediagoblin/default/media/public/media_entries';
my $NEW_ROOT = './mg_html';

#
# no user serviceable parts below
#

# creates directory if it doesn't exists
sub do_mkdir ($) {
    my ($dir) = @_;
    mkdir $dir unless -d $dir;
}

# create whole collection
sub create_collection($) {
    my ($c) = @_;

    my $collection_template = HTML::Template->new(path => $RealBin, filename => 'collection.tmpl', utf8 => 1);

    $collection_template->param(
        title => $$c{'title'},
        description => $$c{'description'},
    );

    print $collection_template->output;
    die;
}

#
# main
#

my $dbh = DBI->connect("dbi:Pg:dbname=$DB_NAME", '', '', {AutoCommit => 0, RaiseError => 1});

do_mkdir ($NEW_ROOT);
chdir $NEW_ROOT or die "can't chdir to $NEW_ROOT: $!";

my $collection_sth = $dbh->prepare('SELECT core__collections.id, title, slug, core__users.username, description FROM core__collections LEFT JOIN core__users ON core__collections.creator = core__users.id;');
$collection_sth->execute();

while (my $collection = $collection_sth->fetchrow_hashref) {
    create_collection ($collection);
}

$dbh->disconnect;
