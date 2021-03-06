#!/usr/bin/perl -T
# Matija Nalis <mnalis-perl@voyager.hr> GPLv3+ started 2020-04-15
# converts data from Mediagoblin instance to static html
#
# run as: 
#   sudo -u postgres ./mg_to_static.pl
#

use warnings;
use strict;
use autodie qw/:all/;
use feature 'say';
use utf8;
use open ':std', ':encoding(UTF-8)';

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
        #force_untaint => 2,
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
    $$media{'description'} =~ s{\[(.+?)\]\s*\((.+?)\)}{<A HREF="$2">$1</A>}gi;	# convert HTTP links to <A HREF>
    
    # media template headers
    $media_template->param(
        username => $$collection{'username'}, 
        collection_name => $$collection{'title'},
        collection_slug => $$collection{'slug'},
        title => $$media{'title'},
        description => $$media{'description'},
        created => $$media{'created'},
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

my %ALL_COLLECTIONS= ();

# create whole collection
sub create_collection($) {
    my ($c) = @_;

    my $collection_template = template_new('collection');

    $$c{'description'} =~ s{\[(.+?)\]\s*\((.+?)\)}{<A HREF="$2">$1</A>}gi;	# convert HTTP links to <A HREF>

    
    # template loop for each picture
    my $one_collection_sth = $dbh->prepare ("
        SELECT core__media_entries.id,  core__media_entries.title, core__media_entries.slug, core__media_entries.description, core__media_entries.created
        FROM core__collection_items
        LEFT JOIN core__media_entries ON core__media_entries.id = core__collection_items.media_entry
        WHERE collection=?
        ORDER BY position DESC, core__collection_items.id");
    $one_collection_sth->execute($$c{'id'});

    my @loop_media = ();

    while (my $media = $one_collection_sth->fetchrow_hashref) {
        #say "debug2 for ciod=$$c{id}: mid=$$media{id} mtitle=$$media{title} mcreated=$$media{created}";
        my $one_media_href = create_media ($c, $media);
        push @loop_media, $one_media_href;
    }

    # create index.html
    my $c_dir = "./u/$$c{username}/collection/$$c{slug}";
    do_mkdir ($c_dir);

    # collection template params
    $collection_template->param(
        username => $$c{'username'}, 
        title => $$c{'title'},
        description => $$c{'description'},
        media_loop => \@loop_media,		# list of all media in collection
    );

    template_write_html ($c_dir, $collection_template);
    push @{$ALL_COLLECTIONS{$$c{'username'}}}, { c_title => $$c{'title'}, c_slug => $$c{'slug'} };
}

#
# main
#

$dbh = DBI->connect("dbi:Pg:dbname=$DB_NAME", '', '', {AutoCommit => 0, RaiseError => 1, Taint => 0});	# FIXME should use Taint => 1

do_mkdir ($NEW_ROOT);
chdir $NEW_ROOT or die "can't chdir to $NEW_ROOT: $!";

# create all collections
my $collections_sth = $dbh->prepare("
    SELECT core__collections.id, title, slug, core__users.username, description
    FROM core__collections
    LEFT JOIN core__users ON core__collections.creator = core__users.id");
$collections_sth->execute();


while (my $collection = $collections_sth->fetchrow_hashref) {
    create_collection ($collection);
}

# create all users
foreach my $username (keys %ALL_COLLECTIONS) {
    my $user_template = template_new('user');
    $user_template->param(
        username => $username,
        col_loop => $ALL_COLLECTIONS{$username},
    );
    my $u_dir = "./u/$username";
    template_write_html ($u_dir, $user_template);
}

# create main index.html
my $main_template = template_new('main');
my @loop_users = ();
foreach my $username (keys %ALL_COLLECTIONS) {
        push @loop_users, { username => $username };
}
$main_template->param(
    user_loop =>  \@loop_users,
);
template_write_html ('./', $main_template);

$dbh->disconnect;
