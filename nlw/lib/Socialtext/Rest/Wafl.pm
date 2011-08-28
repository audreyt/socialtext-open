package Socialtext::Rest::Wafl;
# @COPYRIGHT@
use strict;
use warnings;

use base 'Socialtext::Rest';

use Encode qw(decode_utf8 encode_utf8);
use Imager;
use Socialtext::Paths;
use Socialtext::File qw(get_contents ensure_directory);
use Socialtext::AppConfig;
use Socialtext::String;
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use namespace::clean;

my @font_table = grep {
    -f Socialtext::AppConfig->code_base . '/fonts/' . $_->{font}
} YAML::LoadFile(
    Socialtext::AppConfig->code_base . '/fonts/config.yaml'
);
die "Invalid font table in 'fonts/config.yaml'"
    unless @font_table and $font_table[0]->{default};
unshift @font_table, 'dummy first entry';

my $font_path = Socialtext::AppConfig->code_base .  '/fonts';
my $widgets_path = Socialtext::AppConfig->code_base . '/widgets';
my $max = 300;
my $height = 19;
my $ellipsis = '...';

sub GET_image {
    my $self = shift;
    my $uneditable = $self->rest->query->param('uneditable') ? 1 : 0;
    my $current = 0;

    my $cache_dir = Socialtext::Paths::cache_directory('wafl');
    $cache_dir = abs_path($cache_dir);
    ensure_directory($cache_dir);

    my $text = decode_utf8($self->__text__);
    my $image_file = abs_path("$cache_dir/".Socialtext::String::uri_escape($text)."$uneditable.png");

    die 'Bad Text' unless dirname($image_file) eq $cache_dir;
    return $self->return_file($image_file) if -f $image_file;

    my @texts;
    my $text_num = 0;
    $texts[$text_num] = {str => '', type => 0};
    for my $char (split //, $text) {
        my $ord = ord($char);
        if ($current) {
            my $entry = $font_table[$current];
            if ($ord >= $entry->{lower} and
                $ord <= $entry->{upper}) {
                $texts[$text_num]{str} .= $char;
                next;
            }
        }
        my $font_type = 0;
        for (my $i = 1; $i < @font_table; $i++) {
            if ($ord >= $font_table[$i]{lower} and
                $ord <= $font_table[$i]{upper}) {
                $font_type = $i;
                last;
            }
        }
        unless ($font_type) {
            $char = '?';
            $font_type = 1;
        }
        unless ($texts[$text_num]{type}) {
            $texts[$text_num]{type} = $font_type;
        }
        if ($texts[$text_num]{type} == $font_type) {
            $texts[$text_num]{str} .= $char;
            next;
        }
        $texts[++$text_num] = {str => $char, type => $font_type};
    }

    my %fonts;

    my $x = 4;
    my $overflow = 0;
    for my $text (@texts) {
        my $type = $text->{type};
        my $str = $text->{str};
        $text->{x} = $x;
        my $font = $fonts{$type} ||= $self->new_font($type);
        my ($neg, $xxx, $pos) = $font->bounding_box(string => $str);
        $x += $pos - $neg;
        if ($x >= $max) {
            $font = $fonts{1} ||= $self->new_font(1);
            my ($neg, $xxx, $pos) = $font->bounding_box(string => $ellipsis);
            $overflow = $pos - $neg;
            last;
        }
    }
    $x += 4;

    my $width = $x > $max ? $max : $x;
    $width+=2;

    my $image = Imager->new(xsize => $width, ysize => $height, channels => 4);

    my $background_color = $uneditable ? Imager::Color->new(238,238,238) : Imager::Color->new(208, 208, 208);
    my $font_color = Imager::Color->new( 47,47,47 );
    my @boundary_points = (
        [3,0], [$width-4,0],
        [$width-1,3], [$width-1,$height-3],
        [$width-4,$height-1], [3,$height-1],
        [0,$height-3], [0,3], [3,0]
    );
    $image->polygon(
        points => \@boundary_points,
        color => $background_color
    );

    $image->polyline(
        points => \@boundary_points,
        color => Imager::Color->new( 160, 160, 160),
        aa => 1,
    );

    for my $text (@texts) {
        last unless $text->{x};
        my $font = $fonts{$text->{type}};
        $font->align(
            string => $text->{str},
            color => $font_color,
            x => $text->{x},
            y => int($height / 2) + 1,
            halign => 'left',
            valign => 'center',
            image => $image,
        );
    }
    if ($overflow) {
        my $font = $fonts{1};
        my @overflow_boundary_points = (
            [$width - $overflow - 8,2], [$width-4,2],
            [$width-1,4], [$width-1,$height-4],
            [$width - $overflow - 8,$height-3]
        );

        $image->polygon(
            points => \@overflow_boundary_points,
            color => $background_color
        );

        $font->align(
            string => $ellipsis,
            color => $font_color,
            x => $max - $overflow - 2,
            y => int($height / 2) + 1,
            halign => 'left',
            valign => 'center',
            image => $image,
        );
    }

    $image->write(
        file => $image_file,
    ) or die "Cannot save $image_file ", $image->errstr;

    return $self->return_file($image_file);
}

sub new_font {
    my $self = shift;
    my $type = shift;

    # see also: WikiwygPlugin
    my $font = Imager::Font->new(
        file => $font_path . '/' . $font_table[$type]{font},
        size => $font_table[$type]{size},
        utf8 => 1,
        aa => 1,
        type => 'ft2',
    );
    unless ($font) {
        die "Cannot load $font_path ", Imager->errstr, "#";
    }
    return $font;
}

sub return_file {
    my ($self, $file) = @_;
    my $content = get_contents($file);
    $self->rest->header(-type => 'image/png');
    return $content;
}

1;
