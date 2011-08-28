#!perl
use warnings;
use strict;
use Test::Socialtext;
use Test::More;
use File::Temp qw/tempfile/;
use Socialtext::Image;

use_ok 'Socialtext::Upload';

fixtures(qw(db));

my $orig = "$ENV{ST_CURRENT}/nlw/t/attachments/grayscale.png";

small_attachment: {
    my $hub = create_test_hub();
    my $creator = $hub->current_user();
    open my $fh, '<', $orig or die "$orig\: $!";
    my $small = $hub->attachments->create(
        filename => $orig,
        fh => $fh,
        creator => $creator,
    );

    my ($large_fh, $large_filename) = tempfile(SUFFIX => '.png');
    Socialtext::Image::resize(
        filename => $orig, to_filename => $large_filename,
        new_width => 1280, new_height => 1024,
    );

    my $large = $hub->attachments->create(
        filename => $large_filename,
        fh => $large_fh,
        creator => $creator,
    );

    # $small is 300x150
    attachment_resize_ok($small, 'original','',              "300x150x1");
    attachment_resize_ok($small, 'scaled',  'thumb-600x0',   "300x150x1");
    attachment_resize_ok($small, 'small',   'resize-100x0',  "100x50x1" );
    attachment_resize_ok($small, 'medium',  'resize-300x0',  "300x150x1");
    attachment_resize_ok($small, 'large',   'resize-600x0',  "600x300x1");
    attachment_resize_ok($small, '800',     'resize-800x0',  "800x400x1");
    attachment_resize_ok($small, '800x100', 'resize-800x100',"200x100x1");
    attachment_resize_ok($small, '100x800', 'resize-100x800',"100x50x1" );

    # $large is 1280x640
    attachment_resize_ok($large, 'original','',              "1280x640x1");
    attachment_resize_ok($large, 'scaled',  'thumb-600x0',   "600x300x1" );
    attachment_resize_ok($large, 'small',   'resize-100x0',  "100x50x1"  );
    attachment_resize_ok($large, 'medium',  'resize-300x0',  "300x150x1" );
    attachment_resize_ok($large, 'large',   'resize-600x0',  "600x300x1" );
    attachment_resize_ok($large, '800',     'resize-800x0',  "800x400x1" );
    attachment_resize_ok($large, '800x100', 'resize-800x100',"200x100x1" );
    attachment_resize_ok($large, '100x800', 'resize-100x800',"100x50x1"  );

    # no_max_image_size
    my $orig_uri = $large->prepare_to_serve('original');
    my $scaled_uri = $large->prepare_to_serve('scaled');
    isnt $orig_uri, $scaled_uri, 'scaling happens if no_max_image_size=0';

    $hub->current_workspace->update(no_max_image_size => 1);
    $orig_uri = $large->prepare_to_serve('original');
    $scaled_uri = $large->prepare_to_serve('scaled');
    is $orig_uri, $scaled_uri, "scaling doesn't happen if no_max_image_size=1";
}

sub attachment_resize_ok {
    my ($attachment, $name, $flavor, $dims) = @_;

    my $uri = $attachment->prepare_to_serve( $name );
    my $disk_filename = $attachment->upload->disk_filename;
    my $filename = $attachment->filename;

    if ($flavor) {
        $disk_filename .= ".$flavor";
    }
    else {
        $flavor = "original";
    }

    like $uri, qr/\Q$name\/$filename\E$/, "$flavor URI";

    ok -f $disk_filename, "$flavor exists";

    my @actual = Socialtext::Image::get_dimensions($disk_filename);
    is join('x', @actual), $dims, "$flavor dimensions";
}

done_testing;
