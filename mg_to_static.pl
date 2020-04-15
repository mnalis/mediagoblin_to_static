#!/usr/bin/perl
# Matija Nalis <mnalis-perl@voyager.hr> GPLv3+ started 2020-04-15
# converts data from Mediagoblin instance to static html
#
# run as: 
#   sudo -u postgres ./mg_to_static.pl > runme.sh && sh runme.sh
#

# FIXME zali se na UTF8 "Wide character in print" , zasto
# FIXME check da li ima fileova u $MG_ROOT koje nismo referencirali u $NEW_ROOT

use warnings;
use strict;
use autodie qw/:all/;
use feature 'say';
use utf8;

use DBI;
use Data::Dumper;
use HTML::Template;
use FindBin qw( $RealBin );
use File::Path qw(make_path);

my $DB_NAME = 'mediagoblin';
my $MG_ROOT = '/var/lib/mediagoblin/default/media/public/media_entries';
my $NEW_ROOT = './mg_html';

#
# no user serviceable parts below
#

my $dbh;

# creates directory if it doesn't exists
sub do_mkdir ($) {
    my ($dir) = @_;
    make_path ($dir) unless -d $dir;
}

# create whole collection
sub create_collection($) {
    my ($c) = @_;

    my $collection_template = HTML::Template->new(path => $RealBin, filename => 'collection.tmpl', utf8 => 1);

    $$c{'description'} =~ s{\[(.+?)\]\s*\((.+?)\)}{<A HREF="$2">$1</A>}gi;	# convert HTTP links to <A HREF>

    # template headers
    $collection_template->param(
        title => $$c{'title'},
        description => $$c{'description'},
    );
    
    # template loop for each picture
    my $one_collection_sth = $dbh->prepare ("SELECT core__media_entries.id,  core__media_entries.title, core__media_entries.slug, core__media_entries.description FROM core__collection_items LEFT JOIN core__media_entries ON core__media_entries.id = core__collection_items.media_entry WHERE collection=? ORDER BY position, core__collection_items.id");
    $one_collection_sth->execute($$c{'id'});
    
    while (my $media = $one_collection_sth->fetchrow_hashref) {
        say "collection=$$c{id} media=$$media{id} title=$$media{title} slug=$$media{slug} desc=$$media{description}";
    }



    # create index.html
    my $c_dir = "./u/$$c{username}/collection/$$c{slug}";
    do_mkdir ($c_dir);

    open my $c_index, '>', "$c_dir/index.html";
    print $c_index $collection_template->output;
    close $c_index;
}

#
# main
#

$dbh = DBI->connect("dbi:Pg:dbname=$DB_NAME", '', '', {AutoCommit => 0, RaiseError => 1});

do_mkdir ($NEW_ROOT);
chdir $NEW_ROOT or die "can't chdir to $NEW_ROOT: $!";

my $collections_sth = $dbh->prepare('SELECT core__collections.id, title, slug, core__users.username, description FROM core__collections LEFT JOIN core__users ON core__collections.creator = core__users.id;');
$collections_sth->execute();

while (my $collection = $collections_sth->fetchrow_hashref) {
    create_collection ($collection);
}

$dbh->disconnect;
