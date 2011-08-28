package Socialtext::Handler::URIMap;
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::AppConfig;
use YAML qw/LoadFile/;

sub new {
    my $class = shift;
    my %opts  = @_;
    my $self  = {
        config_dir => $opts{config_dir},
    };

    $self->{config_dir}
        ||= File::Basename::dirname(Socialtext::AppConfig->file());

    bless $self, $class;
    return $self;
}

sub uri_map_file { "$_[0]->{config_dir}/uri_map.yaml" }
sub uri_map_dir  { "$_[0]->{config_dir}/uri_map.d" }

sub uri_hooks {
    my $self = shift;
    my $hooks = _load_file( $self->uri_map_file );
    for my $file (sort glob($self->uri_map_dir . '/*.yaml')) {
        my $subhooks =  _load_file( $file );
        push @$hooks, @$subhooks;;
    }
    return $hooks;
}

sub _load_file {
    my $file = shift;
    my $tied_hooks = LoadFile( $file );
    die "$file was an invalid yaml format!" unless ref($tied_hooks) eq 'ARRAY';
    my $hooks = [ @$tied_hooks ];
    return $hooks;
}

1;
