package Socialtext::Handler::JavaScript;
# @COPYRIGHT@
use Moose;
use methods;
use Socialtext::HTTP ':codes';
use Socialtext::JavaScript::Builder;
use Socialtext::AppConfig;
use File::Basename qw(basename);
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest';
my $code_base = Socialtext::AppConfig->code_base;

has 'path' => (
    is => 'ro', isa => 'Maybe[Str]', lazy_build => 1,
);

method GET ($rest) {
    my $file = $self->__file__;

    my $builder = Socialtext::JavaScript::Builder->new;
    return $self->no_resource($file) unless $builder->is_target($file);

    my $content_type = $file =~ /\.htc$/
        ? 'text/x-component'
        : 'application/javascript';
    
    my $path = $builder->target_path($file);
    $builder->build($file) if !-f $path or $ENV{NLW_DEV_MODE};
    $rest->header(
        -status               => HTTP_200_OK,
        '-content-length'     => -s $path,
        -type                 => $content_type,
        -pragma               => undef,
        '-cache-control'      => undef,
        'Content-Disposition' => "filename=\"$file\"",
        '-X-Accel-Redirect'   => "/nlw/js/$file",
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
