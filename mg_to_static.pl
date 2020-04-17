#!/usr/bin/perl
# Matija Nalis <mnalis-perl@voyager.hr> GPLv3+ started 2020-04-15
# converts data from Mediagoblin instance to static html
#
# run as: 
#   sudo -u postgres ./mg_to_static.pl
#

# FIXME ordering vidi za sloveniju i za sifon kade, koji je ispravan ordering?
# FIXME htpa portganih -- https://media.mnalis.com/u/biciklijade/collection/info/ ? ili https://media.mnalis.com/u/biciklijade/collection/rapha-2016-zagrijavanje-1/ ? i https://media.mnalis.com/u/biciklijade/m/karlovac-1-maj-2015-9c9e/ ? why?
# FIXME CSS referenciraj i napravi neki defaultni?
# FIXME zali se na "Use of uninitialized value $filename in substitution" za hrpu stvari, check
# FIXME user template dodaj (sa listom collectiona), kao i naslovnica glavna index.html sa listom usera
# FIXME media info kada je created/added?
# FIXME vidi za .webm i ostale tipove, ne samo za jpg da radi! (glob? i pazi za thumbnail i medium!)
# FIXME zali se na UTF8 "Wide character in print" , zasto
# FIXME check da li ima fileova u $MG_ROOT koje nismo referencirali u $NEW_ROOT
# FIXME commit updates to github

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

# returns URI for media matching given regexp
sub _get_media_uri_regex($$$) {
    my ($media_id, $title, $regexp) = @_;
    
    my $media_dir = "$MG_ROOT/$media_id";
    opendir(my $dh, $media_dir);
    my @files = grep { /$regexp/ && -f "$media_dir/$_" } readdir($dh);
    closedir $dh;

    return undef if !@files;
    my $filename = $files[0];
    warn "undefined filename is $filename for id=$media_id and title=$title and regexp=$regexp (also $files[1])" if !defined $filename;
    return "/media_entries/$media_id/$filename";
}

# get small thumbnail image only
sub get_media_uri_thumb_img($$) {
    my ($media_id, $title) = @_;
    return	_get_media_uri_regex ($media_id, $title, qr/\.thumbnail\./);
}

# get original media (image or video or pdf or ...) in full size (or failing that, in medium)
sub get_media_uri_orig($$) {
    my ($media_id, $title) = @_;
    return 	_get_media_uri_regex ($media_id, $title, qr/(?<!medium|mbnail)\.(png|gif|jpg|jpeg|webm|pdf)$/i) ||	# FIXME not ideal, as we hardcode extensions... 'fgrep -v' would be better
                _get_media_uri_regex ($media_id, $title, qr/\.medium\./);						# if original media not found, use medium media

}

# prefer medium sized image, but for non-image media (like video, pdf) use thumbnail image instead -  FIXME: should probably use video player, or PDF viewer etc instead, but that is more work...
sub get_media_uri_med_img($$) {
    my ($media_id, $title) = @_;
    return	_get_media_uri_regex ($media_id, $title, qr/\.medium\.(jpg|jpeg|png|gif)$/) ||
                _get_media_uri_regex ($media_id, $title, qr/\.(jpg|jpeg|png|gif)$/i);
}


# creates new HTML::Template
sub template_new ($) {
    my ($tmpl) = @_;
    return HTML::Template->new(
        die_on_bad_params => 1,
        strict => 1,
        case_sensitive => 1,
        path => $RealBin,
        filename => "${tmpl}.tmpl",
        utf8 => 1,
    );
}

# creates index.html in specified directory
sub template_write_html ($$) {
    my ($out_dir, $template) = @_;
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

    my $media_template = template_new('media');

    #say "debug1 /mn/ FIXME u=$$collection{'username'} ct=$$collection{'title'} cid=$$collection{'id'} cs=$$collection{'slug'} mt=$$media{'title'} mid=$$media{id}";
    
    # media template headers
    $media_template->param(
        username => $$collection{'username'}, 
        collection_name => $$collection{'title'},
        collection_slug => $$collection{'slug'},
        title => $$media{'title'},
        description => $$media{'description'},
        img => get_media_uri_med_img ($$media{id}, $$media{title}),
        org_media => get_media_uri_orig ($$media{id}, $$media{title}),
    );
    template_write_html ($m_dir, $media_template);

    my %one_media = (
        thumb => get_media_uri_thumb_img ($$media{id}, $$media{title}),
        url => "/$m_dir/",
    );
    return \%one_media;
}

# create whole collection
sub create_collection($) {
    my ($c) = @_;

    my $collection_template = template_new('collection');

    $$c{'description'} =~ s{\[(.+?)\]\s*\((.+?)\)}{<A HREF="$2">$1</A>}gi;	# convert HTTP links to <A HREF>

    
    # template loop for each picture
    my $one_collection_sth = $dbh->prepare ("SELECT core__media_entries.id,  core__media_entries.title, core__media_entries.slug, core__media_entries.description FROM core__collection_items LEFT JOIN core__media_entries ON core__media_entries.id = core__collection_items.media_entry WHERE collection=? ORDER BY position DESC, core__collection_items.id DESC");
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
        username => $$c{'username'}, 
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
