#!/usr/bin/env perl
# @COPYRIGHT@

# this is _very_ similar to t/Socialtext/People/Profilephoto.
use strict;
use warnings;

use Socialtext::File;
use Test::Socialtext tests => 12;

fixtures('db');

use_ok 'Socialtext::Group::Photo';

my $group = create_test_group();

################################################################################
access_via_group: {
    is ref $group->photo, 'Socialtext::Group::Photo';
}

################################################################################
default_photo: {
    # We really only need to test the cache here
    cache_is(
        group => $group,
        small => Socialtext::Group::Photo->DefaultPhoto('small'),
        large => Socialtext::Group::Photo->DefaultPhoto('large'),
    );
}

################################################################################
custom_photo: {
    # Set a custom image
    my $custom_img = Socialtext::File::get_contents_binary(
        't/widget/creepy_goat.jpg');
    $group->photo->set(\$custom_img);

    my $small_ref = $group->photo->small;
    my $large_ref = $group->photo->large;

    # Make sure images were resized properly
    resize_is( $small_ref, '27x27' );
    resize_is( $large_ref, '62x62' );


    cache_is(
        group => $group,
        small => $small_ref,
        large  => $large_ref,
    );
}

################################################################################
sub cache_is {
    my %p         = @_;
    my $group     = delete $p{group};
    my $cache_dir = $group->photo->cache_dir;
    my $group_id  = $group->group_id;

    for my $size ( keys %p ) {
        $group->photo->$size;
        my $cache_file = "$cache_dir/$group_id-$size.png";

        ok -f $cache_file, "$cache_file exists";
        ok Socialtext::File::get_contents_binary($cache_file) eq ${$p{$size}},
            "cache file is correct";

        # clean up the cache
        unlink $cache_file;
    }
}

{ 
    my $id = 0;

    sub resize_is {
        my $blob_ref = shift;
        my $dims     = shift;
        my $time     = time;
        $id++;

        my $test_dir = Socialtext::AppConfig->test_dir();
        my $tempfile = "$test_dir/$time-$id-photo.png";
        Socialtext::File::set_contents_binary($tempfile, $$blob_ref);
        like `identify $tempfile`, qr/$dims/, "image was resized to $dims";

        # Clean Up
        unlink $tempfile;
    }
}
