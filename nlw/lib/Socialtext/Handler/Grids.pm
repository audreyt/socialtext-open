package Socialtext::Handler::Grids;
# @COPYRIGHT@
use Moose;
use methods-invoker;
use Socialtext::HTTP qw(:codes);
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Entity';

method GET_css ($rest) {
    my $width = $->width;
    my $cols = $->cols;
    my $output = "grids.$cols.$width";

    my $params = {
        containers => $cols,
        margin => '10px',
    };

    my $filename;
    if ($width =~ /^\d+$/) {
        $filename = 'grids.fixed';
        $params->{width} = "${width}px";
    }
    elsif ($width eq 'full') {
        $filename = 'grids.full';
    }

    my $sass = Socialtext::SASSy->Fetch(
        filename => $filename,
        output_filename => $output,
        dir_name => 'Global',
        params => $params,
    );
    $sass->render if $sass->needs_update;

    my $size = -s $sass->sass_file;

    $rest->header(
        -status               => HTTP_200_OK,
        '-content-length'     => $size || 0,
        -type                 => 'text/css',
        -pragma               => undef,
        '-cache-control'      => undef,
        'Content-Disposition' => qq{filename="$output.css.txt"},
        '-X-Accel-Redirect'   => $sass->protected_uri("$output.css"),
    );
}

=head1 NAME

Socialtext::Handler::Base - CSS handler for adaptive grids

=head1 SYNOPSIS

  GET /st/grids/:cols/:width

=head1 DESCRIPTION

This handler defines CSS representations tailor-made to the specified
number of columns under a given screen width.

=cut
