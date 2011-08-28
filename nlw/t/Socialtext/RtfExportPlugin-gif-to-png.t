#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext tests => 8;

use Socialtext::RtfExportPlugin;
use Socialtext::File;
use Imager;
use Readonly;

# We're going to test that a gif string gets turned into a png
# string. This should point out that the method is an alien
# to RtfExportPlugin, and indeed it is and should be moved
# to Socialtext::Image when that class is updated to support
# Imager instead of Image::Magick

Readonly my $GIF_FILE => 't/attachments/socialtext-logo-30.gif';
Readonly my $PNG_FILE => 't/extra-attachments/FormattingTest/thing.png';

# success with a GIF
{
    my $gif       = read_image($GIF_FILE);
    my $gif_image = new Imager();
    eval { $gif_image->read( data => $gif, type => 'gif' ) };
    is( $@, '', "reading the gif creates no error: $@" );
    is( $gif_image->tags( name => 'i_format' ), 'gif',
        'disk image is a gif' );

    my $png;
    eval { $png = HTML::FormatRTFWithImages->_gif_to_png($gif) };
    is( $@, '', "generating the png creates no error: $@" );

    my $png_image = new Imager();

    eval { $png_image->read( data => $png, type => 'png' ) };
    is( $@, '', "reading the png creates no error: $@" );
    is( $png_image->tags( name => 'i_format' ), 'png',
        'translated image is a png' );
}

# failure with a PNG
{
    my $png       = read_image($PNG_FILE);
    my $png_image = new Imager();
    eval { $png_image->read( data => $png, type => 'png' ) };
    is( $@, '', "reading the png creates no error: $@" );
    is( $png_image->tags( name => 'i_format' ), 'png',
        'disk image is a png' );

    my $png2;
    eval { $png2 = HTML::FormatRTFWithImages->_gif_to_png($png) };
    isnt( $@, '', "generating the png creates an error: $@" );
}

sub read_image {
    my $filename = shift;

    return Socialtext::File::get_contents($filename);
}
