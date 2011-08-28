package Socialtext::Rest::Settings::DefaultWorkspace;
# @COPYRIGHT@
use Moose;
use Socialtext::AppConfig;
use Socialtext::Exceptions;
use Socialtext::Workspace;
use Socialtext::HTTP qw/:codes/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Workspace';

sub _my_GET_any {
    my( $self, $rest, $command ) = @_;
    if ($self->workspace->real == 0) {
        $rest->header(
            -status => HTTP_404_Not_Found,
            -type => 'text/plain'
        );
        return "Default Workspace not found.";
    }

    # CopyPasta from ST::Rest:Workspace->_GET_any
    my $super_method = (caller 1)[3];   # - get fully-qualified name of calling sub
    $super_method =~ s/^.+::/SUPER::/;  # - replace package name with SUPER
    return $self->$super_method($rest); # - call the superclass method
}

sub GET_html { _my_GET_any(@_) }
sub GET_text { _my_GET_any(@_) }
sub GET_json { _my_GET_any(@_) }

sub _new_workspace {
    my $self = shift;
    return ( $self->ws )
        ? Socialtext::Workspace->new( name => $self->ws )
        : Socialtext::NoWorkspace->new();
}

sub ws { 
    my ($self, $rest) = shift;
    my $name = Socialtext::AppConfig->default_workspace;
    return $name;
}

__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
1;

