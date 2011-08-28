# @COPYRIGHT@
package Socialtext::Image;
use 5.12.0;
use warnings;

use Socialtext::System qw(shell_run backtick);
use Carp qw/croak confess/;
use File::Temp qw(tempfile);
use Readonly;
use IO::Handle;
use IO::File;
use File::Copy qw/copy/;
use Socialtext::Validate qw( validate SCALAR_TYPE OPTIONAL_INT_TYPE HANDLE_TYPE );

my %SPEC = (
    profile   => sub { "rect-".($_[0] eq 'small' ? 27 : 62) },
    group     => sub { "rect-".($_[0] eq 'small' ? 27 : 62) },
    account   => sub { "thumb-201x36" },
    sigattach => sub { "thumb-64x64" },
);

sub spec_resize_get {
    my ($spec_name, $spec_param) = @_;
    my $resizer = $SPEC{$spec_name};
    return unless $resizer;
    return $resizer->($spec_param);
}

sub spec_resize {
    my ($spec, $from, $to) = @_;
    # The specs are used for filenames in Socialtext::Upload so be sure to
    # constrain these to filesystem-friendly characters (i.e. no dots or
    # slashes)
    confess "invalid resize spec" unless $spec =~ /^[a-z0-9-@]+$/;
    my ($kind,$rest) = split '-',$spec,2;
    if ($kind eq 'resize') {
        my ($w,$h) = split 'x',$rest;
        confess "invalid width/height in thumbnail resize spec"
            if ($w=~/\D/ || $h=~/\D/);
        return resize(
            filename => $from, to_filename => $to,
            max_width => $w, max_height => $h,
            new_width => $w, new_height => $h,
        );
    }
    elsif ($kind eq 'thumb') {
        my ($w,$h) = split 'x',$rest;
        confess "invalid width/height in thumbnail resize spec"
            if ($w=~/\D/ || $h=~/\D/);
        return resize(
            filename => $from, to_filename => $to,
            max_width => $w, max_height => $h
        );
    }
    elsif ($kind eq 'rect') {
        my $max_dim = $rest;
        my ($w,$h) = split 'x',$rest;
        $h //= $w;
        confess "invalid width/height in rectangular resize spec"
            if ($w=~/\D/ || $h=~/\D/);
        return extract_rectangle(
            filename => $from, to_filename => $to,
            width => $max_dim, height => $max_dim
        );
    }
    else {
        confess "invalid resize spec: $spec";
    }
}

{
    Readonly my $spec => {
        max_width  => OPTIONAL_INT_TYPE,
        max_height => OPTIONAL_INT_TYPE,
        new_width  => OPTIONAL_INT_TYPE,
        new_height => OPTIONAL_INT_TYPE,
        filename   => SCALAR_TYPE(default => ''),
        to_filename   => SCALAR_TYPE(default => ''),
    };

    sub resize {
        my %p = validate( @_, $spec );

        my $file = $p{filename} || die "Filename is required";
        my $to_file = $p{to_filename} || $file;

        ($p{img_width}, $p{img_height}) = get_dimensions($file);
        my ($max_w, $max_h) = get_proportions(%p);

        # only resize the image if it has to be resized, otherwise we trigger
        # recompression of the image, which screws up images w/lossy
        # compression algorithms (e.g. JPEGs)
        if ($p{img_width} == $max_w and $p{img_height} == $max_h) {
            copy $file => $to_file unless $file eq $to_file;
            return;
        }

        local $Socialtext::System::SILENT_RUN = 1;
        convert($file, $to_file, scale => "${max_w}x${max_h}");
    }
}

sub shrink {
    my ($w,$h,$max_w,$max_h) = @_;
    my $over_w = $max_w ? $w / $max_w : 0;
    my $over_h = $max_h ? $h / $max_h : 0;
    if ($over_w > 1 and $over_w > $over_h) {
        $w /= $over_w;
        $h /= $over_w;
    }
    elsif ($over_h > 1 and $over_h >= $over_w) {
        $w /= $over_h;
        $h /= $over_h;
    }
    return ($w,$h);
}

sub get_dimensions {
    my $file = shift;
    my $dims = `identify -format '\%w \%h \%n' $file`;
    unless ($dims) {
        my $png = File::Temp->new(SUFFIX => '.png')
            or confess "can't open storage temp file: $!";
        local $Socialtext::System::SILENT_RUN = 1;
        shell_run "convert $file $png";
        $dims = `identify -format '\%w \%h \%n' $png`;
    }
    return split ' ', $dims;
}

# crop an image using an internal, centered rectangle of the desired size
sub extract_rectangle {
    my %p = @_;

    die "a filename parameter is required" unless $p{filename};

    my $file = $p{filename};
    my $to_file = $p{to_filename} || $file;
    my ($max_w, $max_h) = @p{qw(width height)};
    die "must supply width and height" unless $max_w && $max_h;

    my ($w, $h) = get_dimensions($file);

    die "Bad dimensions"
        if ($h == 0 || $w == 0 || $max_h == 0 || $max_w == 0);

    if ($w == $max_w && $h == $max_h) {
        copy $file => $to_file unless $file eq $to_file;
        return;
    }

    my @opts = ();

    # aspect ratios (rise over run):
    # tall:   > 1.0
    # square: = 1
    # wide:   < 1.0

    my $ratio         = $h / $w;
    my $is_square     = ($h == $w);
    my $new_ratio     = $max_h / $max_w;
    my $new_is_square = ($max_h == $max_w);

    if ($new_is_square && $is_square) {
        # same aspect ratio, just scale
        push @opts, resize => $max_w.'x'.$max_h;
    }
    else {
        if ($new_ratio > $ratio) {
            # new image is taller
            # make the two the same height
            push @opts, resize => 'x'.$max_h;
        }
        else {
            # new image is wider
            # make the two the same width
            push @opts, resize => $max_w.'x';
        }

        # now that they're the same size in one dimension, take a
        # center-anchored chunk of the correct size
        push @opts, gravity => 'Center';
        push @opts, crop => $max_w.'x'.$max_h.'+0+0';
    }

    local $Socialtext::System::SILENT_RUN = 1;
    convert($file, $to_file, @opts);
}

sub convert {
    my $in = shift;
    my $out = shift;
    my @opts;
    while (my ($k,$v) = splice(@_,0,2)) {
        push @opts, "-$k", $v;
    }

    backtick('convert', $in, @opts, $out);
}

sub crop_geometry {
    my %p = @_;
    my ($width, $height) = ($p{width}, $p{height});
    my ($max_width, $max_height) = ($p{max_width}, $p{max_height});

    my %geometry = (
        width => $width, height => $height,
        x => 0, y => 0
    );

    if ($width > $max_width && $height <= $max_height) {
        $geometry{width}  = $max_width;
        $geometry{height} = $height;
        $geometry{x}      = ($width - $max_width) / 2;
        $geometry{y}      = 0;
    }
    elsif ($height > $max_height && $width <= $max_width) {
        $geometry{width}  = $width;
        $geometry{height} = $max_height;
        $geometry{x}      = 0;
        $geometry{y}      = ($height - $max_height) / 2;
    }

    return %geometry;
}

sub get_proportions {
    my %p = @_;

    my ($width,$height) = (0,0);
    my $ratio = 1;

    if ($p{new_width} and $p{new_height}) {
        ($width,$height) = shrink($p{new_width}, $p{new_height},
                                  $p{max_width}, $p{max_height});
    }
    elsif ($p{new_width}) {
        $ratio = $p{img_width} / $p{img_height};
        $width = $p{new_width};
        $height = $width / $ratio;
        ($width,$height) = shrink($width,$height,$p{max_width},$p{max_height});
    }
    elsif ($p{new_height}) {
        $ratio = $p{img_width} / $p{img_height};
        $height = $p{new_height};
        $width = $height * $ratio;
        ($width,$height) = shrink($width,$height,$p{max_width},$p{max_height});
    }
    else {
        ($width,$height) = shrink($p{img_width}, $p{img_height},
                                  $p{max_width}, $p{max_height});
    }

    return ($width,$height);
}

1;
