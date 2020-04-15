#!/usr/bin/perl
# Matija Nalis <mnalis-perl@voyager.hr> GPLv3+ started 2020-04-15
# converts data from Mediagoblin instance to static html
#
# run as: 
#   sudo -u postgres ./mg_to_static.pl
#

# FIXME CSS referenciraj i napravi neki defaultni?
# FIXME zali se na "Use of uninitialized value $filename in substitution" za hrpu stvari, check
# FIXME user template dodaj (za listom collectiona), kao i naslovnica glavna index.html sa listom usera
# FIXME media info kada je created/added?
# FIXME vidi za .webm i ostale tipove, ne samo za jpg da radi! (glob? i pazi za thumnail i medium!)
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

# creates new HTML::Template
sub new_template ($) {
    my ($tmpl) = @_;
    return HTML::Template->new(path => $RealBin, filename => "${tmpl}.tmpl", utf8 => 1);
}

# detects type of given media, and returns its URI
sub get_media_uri($$$) {
    my ($media_id, $title, $glob) = @_;
    my @all_matched = glob "$MG_ROOT/$media_id/$title.$glob";
    my $filename=$all_matched[0];	# should always be only one...
    #say "debug filename is $filename for id=$media_id and title=$title";
    $filename =~ s{^.*/}{};		# remove all directory parts
    return "/media_entries/$media_id/$filename";
}

# creates index.html in specified directory
sub template_write_html ($$) {
    my ($out_dir, $template)
    open my $html_file, '>', "$out_dir/index.html";
    print $html_file $template->output;
    close $html_file;
}

# create one media file
sub create_media ($$) {
    my ($collection, $media) = @_;
    #say "user=$$collection{'username'} collection=$$collection{'title'} (slug=$$collection{'slug'}) media=$$media{id} title=$$media{title} slug=$$media{slug} desc=$$media{description}";

    my $m_dir = "u/$$collection{'username'}/m/$$media{slug}";
    do_mkdir ($m_dir);

    my $media_template = new_template('media');

    # media template headers
    $media_template->param(
        username => $$collection{'username'}, 
        collection_name => $$collection{'title'},
        collection_slug => $$collection{'slug'},
        title => $$media{'title'},
        description => $$media{'description'},
        img => get_media_uri ($$media{id}, $$media{title}, '{medium,thumbnail}?{jpg,png,gif}'),			# prefer medium .jpg, but for non-image (like video, pdf) use thumbnail image instead
        org_media => get_media_uri ($$media{id}, $$media{title}, '[a-z0-9][a-z0-9][a-z0-9]{,[a-z0-9]}'),	# match 3 or 4 letter extension ONLY
    );

    template_write_html ($m_dir, $media_template);

    my %one_media = (
        thumb => get_media_uri ($$media{id}, $$media{title}, 'thumbnail.*'),
        url => "/$m_dir/",
    );
    return \%one_media;
}

# create whole collection
sub create_collection($) {
    my ($c) = @_;

    my $collection_template = new_template('collection');

    $$c{'description'} =~ s{\[(.+?)\]\s*\((.+?)\)}{<A HREF="$2">$1</A>}gi;	# convert HTTP links to <A HREF>

    
    # template loop for each picture
    my $one_collection_sth = $dbh->prepare ("SELECT core__media_entries.id,  core__media_entries.title, core__media_entries.slug, core__media_entries.description FROM core__collection_items LEFT JOIN core__media_entries ON core__media_entries.id = core__collection_items.media_entry WHERE collection=? ORDER BY position, core__collection_items.id");
    $one_collection_sth->execute($$c{'id'});
    my @loop_data = ();
    
    while (my $media = $one_collection_sth->fetchrow_hashref) {
        my $one_media_href = create_media ($c, $media);
        push(@loop_data, $one_media_href);
    }

    # create index.html
    my $c_dir = "./u/$$c{username}/collection/$$c{slug}";
    do_mkdir ($c_dir);

    # collection template params
    $collection_template->param(
        title => $$c{'title'},
        description => $$c{'description'},
        media_loop => \@loop_data,
    );

    template_write_html ($c_dir, $collection_template);
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
