#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext;

BEGIN {
    unless ( eval { require Image::Size; require MIME::Base64; 1 } ) {
        plan skip_all => 'These tests require Image::Size and MIME::Base64 to run.';
    }
    if ($^O eq 'darwin') {
        plan 'skip_all';
    }
    else {
        plan  tests => 42;
    }
}

BEGIN {
    use_ok( 'Socialtext::File' );
    use_ok( 'Socialtext::Image' );
}

CROP_EXTRA: {
    my %test = (
        "width > max_width" => {
            width => 30, max_width => 20,
            height => 15, max_height => 20,
            exp_geometry => {
                width => 20, height => 15,
                x => 5, y => 0,
            }
        },
        "height > max_height" => {
            width => 15, max_width => 20,
            height => 26, max_height => 20,
            exp_geometry => {
                width => 15, height => 20,
                x => 0, y => 3
            }
        },
        "width = max_width" => {
            width => 20, max_width => 20,
            height => 15, max_height => 20,
            exp_geometry => {
                width => 20, height => 15,
                x => 0, y => 0
            }
        },
        "height = max_height" => {
            width => 15, max_width => 20,
            height => 20, max_height => 20,
            exp_geometry => {
                width => 15, height => 20,
                x => 0, y => 0
            }
        }
    );
    while (my ($name,$test) = each %test) {
        my $exp_geometry = delete $test->{exp_geometry};
        my %geometry = Socialtext::Image::crop_geometry(%$test);
        is($exp_geometry->{x}, $geometry{x}, "x: $name");
        is($exp_geometry->{y}, $geometry{y}, "y: $name");
        is($exp_geometry->{width}, $geometry{width}, "width: $name");
        is($exp_geometry->{height}, $geometry{height}, "height: $name");
    }
}

PROPORTIONS: {
    my %test = (
        "unconstrained" => {
            new_width => 100, new_height => 200,
            img_width => 50,  img_height => 60,
            exp_width => 100, exp_height => 200,
        },

        # Two dimension scaling
        "constrained to new, scaled to max_height" => {
            new_width  => 100, new_height => 200,
            img_width  => 50,  img_height => 60,
            max_height => 10,
            exp_width  => 5,   exp_height => 10,
        },
        "constrained to new, scaled to max_width" => {
            new_width => 100, new_height => 200,
            img_width => 50,  img_height => 60,
            max_width => 10,
            exp_width => 10,  exp_height => 20,
        },
        "constrained to new, scaled to max_height" => {
            new_width  => 100, new_height => 200,
            img_width  => 50,  img_height => 60,
            max_width  => 7,   max_height => 10,
            exp_width  => 5,   exp_height => 10,
        },
        "constrained to new, scaled to max_width" => {
            new_width => 100, new_height => 200,
            img_width => 50,  img_height => 60,
            max_width => 10,  max_height => 24,
            exp_width => 10,  exp_height => 20,
        },
        "constrained to new, scaled to max_width" => {
            new_width  => 100, new_height => 200,
            img_width  => 50,  img_height => 60,
            max_width  => 4,   max_height => 10,
            exp_width  => 4,   exp_height => 8,
        },
        "constrained to new, exceding max_height" => {
            new_width => 100, new_height => 200,
            img_width => 50,  img_height => 60,
            max_width => 10,  max_height => 10,
            exp_width => 5,   exp_height => 10,
        },
        
        # One dimension scaling
        "constrained to img, scaled to new_width" => {
            new_width => 200, max_height => 300,
            img_width => 50,  img_height => 75,
            exp_width => 200, exp_height => 300,
        },
        "constrained to img, scaled to new height" => {
            max_width => 200, new_height => 100,
            img_width => 31,  img_height => 50,
            exp_width => 62,  exp_height => 100,
        },
        "constrained to img, new_width, scaled to max_width" => {
            new_width => 200,
            max_width => 100,
            img_width => 50,  img_height => 75,
            exp_width => 100, exp_height => 150,
        },
        "constrained to img, new_height, scaled to max height" => {
            max_height => 150,
            new_height => 200,
            img_width  => 31,  img_height => 50,
            exp_width  => 93,  exp_height => 150,
        },
        "constrained to img, new_height, scaled to max_width" => {
            max_width => 100, new_height => 200,
            img_width => 50,  img_height => 20,
            exp_width => 100, exp_height => 40,
        },
        "constrained to img, new_width, scaled to max height" => {
            new_width  => 200, max_height => 150,
            img_width  => 10,  img_height => 50,
            exp_width  => 30,  exp_height => 150,
        },

        # Check for /0 errors
        "never divide by zero" => {
            new_width => 0, new_height => 0,
            img_width => 5, img_height => 5,
            exp_width => 5, exp_height => 5,
        },
        "never divide by zero" => {
            new_width => 3, new_height => 0,
            img_width => 5, img_height => 5,
            exp_width => 3, exp_height => 3,
        },
        "never divide by zero" => {
            new_width => 0, new_height => 3,
            img_width => 5, img_height => 5,
            exp_width => 3, exp_height => 3,
        },
        "never divide by zero" => {
            new_width => 0, new_height => 0,
            img_width => 5, img_height => 5,
            max_width => 0,
            exp_width => 5, exp_height => 5,
        },
        "never divide by zero" => {
            max_height => 0,
            new_width => 3, new_height => 0,
            img_width => 5, img_height => 5,
            exp_width => 3, exp_height => 3,
        },
        "never divide by zero" => {
            new_width => 0, new_height => 3,
            img_width => 0, img_height => 5,
            exp_width => 0, exp_height => 3,
        },
    );
    while (my ($name,$test) = each %test) {
        my $ex = delete $test->{exp_width};
        my $ey = delete $test->{exp_height};
        my ($x,$y) = Socialtext::Image::get_proportions(%$test);
        is($x,$ex,"X: $name");
        is($y,$ey,"Y: $name");
    }
}

our $original_file = "/tmp/image.t-$$.png";
our $resized_file = "/tmp/image.t-resized-$$.png";

RESIZE: {
    my $data = do { local $/; <DATA>; };

    Socialtext::File::set_contents( $original_file, MIME::Base64::decode_base64($data) );

    File::Copy::copy($original_file, $resized_file);
    Socialtext::Image::resize(
        max_width  => 200,
        max_height => 60,
        filename   => $resized_file,
    );

    my ( $width, $height ) = Image::Size::imgsize($resized_file);
    is( $width, 60, 'width is now 60' );
    is( $height, 60, 'height is now 60' );

    for my $f ( $original_file, $resized_file ) {
        unlink $f or die "Cannot unlink $f: $!";
    }
}

__DATA__
iVBORw0KGgoAAAANSUhEUgAAAyAAAAMgCAIAAABUEpE/AAAACXBIWXMAAAsTAAALEwEAmpwY
AAAAB3RJTUUH1QUPEDQ3ARVNkgAAAB10RVh0Q29tbWVudABDcmVhdGVkIHdpdGggVGhlIEdJ
TVDvZCVuAAALsklEQVR42u3WMQ0AAAgEMcC/58cEC0kr4abrJAUAwJ2RAADAYAEAGCwAAIMF
AIDBAgAwWAAABgsAAIMFAGCwAAAMFgAABgsAwGABABgsAACDBQCAwQIAMFgAAAYLAACDBQBg
sAAADBYAAAYLAMBgAQAYLAAADBYAgMECADBYAAAGCwAAgwUAYLAAAAwWAAAGCwDAYAEAGCwA
AAwWAIDBAgAwWAAAGCwAAIMFAGCwAAAMFgAABgsAwGABABgsAAAMFgCAwQIAMFgAABgsAACD
BQBgsAAAMFgAAAYLAMBgAQAYLAAADBYAgMECADBYAAAYLAAAgwUAYLAAADBYAAAGCwDAYAEA
GCwAAAwWAIDBAgAwWAAAGCwAAIMFAGCwAAAwWAAABgsAwGABAGCwAAAMFgCAwQIAMFgAABgs
AACDBQBgsAAAMFgAAAYLAMBgAQBgsAAADBYAgMECAMBgAQAYLAAAgwUAYLAAADBYAAAGCwDA
YAEAYLAAAAwWAIDBAgDAYAEAGCwAAIMFAIDBAgAwWAAABgsAwGABAGCwAAAMFgCAwQIAwGAB
ABgsAACDBQCAwQIAMFgAAAYLAMBgAQBgsAAADBYAgMECAMBgAQAYLAAAgwUAgMECADBYAAAG
CwAAgwUAYLAAAAwWAIDBAgDAYAEAGCwAAIMFAIDBAgAwWAAABgsAAIMFAGCwAAAMFgAABgsA
wGABABgsAACDBQCAwQIAMFgAAAYLAACDBQBgsAAADBYAAAYLAMBgAQAYLAAADBYAgMECADBY
AAAGCwAAgwUAYLAAAAwWAAAGCwDAYAEAGCwAAAwWAIDBAgAwWAAABgsAAIMFAGCwAAAMFgAA
BgsAwGABABgsAAAMFgCAwQIAMFgAABgsAACDBQBgsAAADBYAAAYLAMBgAQAYLAAADBYAgMEC
ADBYAAAYLAAAgwUAYLAAADBYAAAGCwDAYAEAGCwAAAwWAIDBAgAwWAAAGCwAAIMFAGCwAAAw
WAAABgsAwGABAGCwAAAMFgCAwQIAMFgAABgsAACDBQBgsAAAMFgAAAYLAMBgAQBgsAAADBYA
gMECADBYAAAYLAAAgwUAYLAAADBYAAAGCwDAYAEAYLAAAAwWAIDBAgDAYAEAGCwAAIMFAGCw
AAAwWAAABgsAwGABAGCwAAAMFgCAwQIAwGABABgsAACDBQCAwQIAMFgAAAYLAMBgAQBgsAAA
DBYAgMECAMBgAQAYLAAAgwUAgMECADBYAAAGCwAAgwUAYLAAAAwWAIDBAgDAYAEAGCwAAIMF
AIDBAgAwWAAABgsAAIMFAGCwAAAMFgCAwZIAAMBgAQAYLAAAgwUAgMECADBYAAAGCwAAgwUA
YLAAAAwWAAAGCwDAYAEAGCwAAIMFAIDBAgAwWAAABgsAAIMFAGCwAAAMFgAABgsAwGABABgs
AAAMFgCAwQIAMFgAAAYLAACDBQBgsAAADBYAAAYLAMBgAQAYLAAADBYAgMECADBYAAAYLAAA
gwUAYLAAAAwWAAAGCwDAYAEAGCwAAAwWAIDBAgAwWAAAGCwAAIMFAGCwAAAwWAAABgsAwGAB
ABgsAAAMFgCAwQIAMFgAABgsAACDBQBgsAAAMFgAAAYLAMBgAQAYLAAADBYAgMECADBYAAAY
LAAAgwUAYLAAADBYAAAGCwDAYAEAYLAAAAwWAIDBAgAwWAAAGCwAAIMFAGCwAAAwWAAABgsA
wGABAGCwAAAMFgCAwQIAwGABABgsAACDBQBgsAAAMFgAAAYLAMBgAQBgsAAADBYAgMECAMBg
AQAYLAAAgwUAgMECADBYAAAGCwDAYAEAYLAAAAwWAIDBAgDAYAEAGCwAAIMFAIDBAgAwWAAA
BgsAwGABAGCwAAAMFgCAwQIAwGABABgsAACDBQCAwQIAMFgAAAYLAACDBQBgsAAADBYAgMEC
AMBgAQAYLAAAgwUAgMECADBYAAAGCwAAgwUAYLAAAAwWAAAGCwDAYAEAGCwAAIMFAIDBAgAw
WAAABgsAAIMFAGCwAAAMFgAABgsAwGABABgsAAAMFgCAwQIAMFgAAAYLAACDBQBgsAAADBYA
AAYLAMBgAQAYLAAADBYAgMECADBYAAAGCwAAgwUAYLAAAAwWAAAGCwDAYAEAGCwAAAwWAIDB
AgAwWAAAGCwAAIMFAGCwAAAMFgAABgsAwGABABgsAAAMFgCAwQIAMFgAABgsAACDBQBgsAAA
MFgAAAYLAMBgAQAYLAAADBYAgMECADBYAAAYLAAAgwUAYLAAADBYAAAGCwDAYAEAYLAAAAwW
AIDBAgAwWAAAGCwAAIMFAGCwAAAwWAAABgsAwGABAGCwAAAMFgCAwQIAMFgAABgsAACDBQBg
sAAAMFgAAAYLAMBgAQBgsAAADBYAgMECAMBgAQAYLAAAgwUAYLAAADBYAAAGCwDAYAEAYLAA
AAwWAIDBAgDAYAEAGCwAAIMFAIDBAgAwWAAABgsAwGABAGCwAAAMFgCAwQIAwGABABgsAACD
BQCAwQIAMFgAAAYLAACDBQBgsAAADBYAgMECAMBgAQAYLAAAgwUAgMECADBYAAAGCwAAgwUA
YLAAAAwWAIDBkgAAwGABABgsAACDBQCAwQIAMFgAAAYLAACDBQBgsAAADBYAAAYLAMBgAQAY
LAAAgwUAgMECADBYAAAGCwAAgwUAYLAAAAwWAAAGCwDAYAEAGCwAAAwWAIDBAgAwWAAABgsA
AIMFAGCwAAAMFgAABgsAwGABABgsAAAMFgCAwQIAMFgAABgsAACDBQBgsAAADBYAAAYLAMBg
AQAYLAAADBYAgMECADBYAAAYLAAAgwUAYLAAADBYAAAGCwDAYAEAGCwAAAwWAIDBAgAwWAAA
GCwAAIMFAGCwAAAwWAAABgsAwGABABgsAAAMFgCAwQIAMFgAABgsAACDBQBgsAAAMFgAAAYL
AMBgAQBgsAAADBYAgMECADBYAAAYLAAAgwUAYLAAADBYAAAGCwDAYAEAYLAAAAwWAIDBAgDA
YAEAGCwAAIMFAGCwAAAwWAAABgsAwGABAGCwAAAMFgCAwQIAwGABABgsAACDBQCAwQIAMFgA
AAYLAMBgAQBgsAAADBYAgMECAMBgAQAYLAAAgwUAgMECADBYAAAGCwDAYAEAYLAAAAwWAIDB
AgDAYAEAGCwAAIMFAIDBAgAwWAAABgsAAIMFAGCwAAAMFgCAwQIAwGABABgsAACDBQCAwQIA
MFgAAAYLAACDBQBgsAAADBYAAAYLAMBgAQAYLAAAgwUAgMECADBYAAAGCwAAgwUAYLAAAAwW
AAAGCwDAYAEAGCwAAAwWAIDBAgAwWAAABgsAAIMFAGCwAAAMFgAABgsAwGABABgsAAAMFgCA
wQIAMFgAAAYLAACDBQBgsAAADBYAAAYLAMBgAQAYLAAADBYAgMECADBYAAAYLAAAgwUAYLAA
AAwWAAAGCwDAYAEAGCwAAAwWAIDBAgAwWAAAGCwAAIMFAGCwAAAwWAAABgsAwGABABgsAAAM
FgCAwQIAMFgAABgsAACDBQBgsAAAMFgAAAYLAMBgAQBgsAAADBYAgMECADBYAAAYLAAAgwUA
YLAAADBYAAAGCwDAYAEAYLAAAAwWAIDBAgAwWAAAGCwAAIMFAGCwAAAwWAAABgsAwGABAGCw
AAAMFgCAwQIAwGABABgsAACDBQBgsAAAMFgAAAYLAMBgAQBgsAAADBYAgMECAMBgAQAYLAAA
gwUAgMECADBYAAAGCwDAYAEAYLAAAAwWAIDBAgDAYAEAGCwAAIMFAIDBAgAwWAAABgsAAIMF
AGCwAAAMFgCAwQIAwGABABgsAACDBQCAwQIAMFgAAAYLAACDBQBgsAAADBYAgMGSAADAYAEA
GCwAAIMFAIDBAgAwWAAABgsAAIMFAGCwAAAMFgAABgsAwGABABgsAACDBQCAwQIAMFgAAAYL
AACDBQBgsAAADBYAAAYLAMBgAQAYLAAADBYAgMECAPhiAYGyCT3o/foJAAAAAElFTkSuQmCC
