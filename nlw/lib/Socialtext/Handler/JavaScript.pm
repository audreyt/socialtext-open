package Socialtext::Handler::JavaScript;
# @COPYRIGHT@
use Moose;
use Socialtext::HTTP ':codes';
use Socialtext::MakeJS;
use Socialtext::AppConfig;
use File::Basename qw(basename);
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest';
my $code_base = Socialtext::AppConfig->code_base;

has 'path' => (
    is => 'ro', isa => 'Maybe[Str]', lazy_build => 1,
);

my %DIR = (
    'jquery-1.4.2.js' => 'skin/common',
    'jquery-1.4.2.min.js' => 'skin/common',
    'jquery-1.4.4.js' => 'skin/common',
    'jquery-1.4.4.min.js' => 'skin/common',
    'push-client.js' => 'plugin/widgets',
);

sub _build_path {
    my $self = shift;

    # Get the mapped version of the file
    my $file = $DIR{$self->__file__}
        ? $DIR{$self->__file__} . '/' . $self->__file__
        : $self->__file__;

    $file = "skin/common/$file" if $file =~ m{^[^/]+\.js$};

    # Parse the path to make sure we know what it means
    $file =~ m{^(skin|plugin)/([^/]+)/(.*)} or return;
    my $type = $1;
    my $name = $2;
    my $path = $3;

    my $dir;
    $dir = "$type/$name/javascript"       if $type eq 'skin';
    $dir = "$type/$name/share/javascript" if $type eq 'plugin';

    if ($ENV{NLW_DEV_MODE} and Socialtext::MakeJS->Exists($dir, $path)) {
        Socialtext::MakeJS->Build($dir, $path);
    }

    return "$dir/$path";
}

sub GET {
    my ($self, $rest) = @_;

    my $path = $self->path || return $self->no_resource('Invalid path');
    my $url = "/nlw/static/$path";
    $path = "$code_base/$path";

    unless (-f $path) {
        warn "Don't know how to build $path";
        return $self->no_resource($path);
    }

    my $filename = basename($path);
    $rest->header(
        -status               => HTTP_200_OK,
        '-content-length'     => -s $path,
        -type                 => 'application/javascript',
        -pragma               => undef,
        '-cache-control'      => undef,
        'Content-Disposition' => "filename=\"$filename\"",
        '-X-Accel-Redirect'   => $url,
    );
}

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

__END__

=head1 NAME

Socialtext::Handler::JavaScript - rebuilds JS as needed in a dev-env

=head1 SYNOPSIS

  # its mapped in automatically in "uri_map.yaml"

=head1 DESCRIPTION

Rebuilds JS as necessary in your dev-env.

=cut
