# @COPYRIGHT@
package Socialtext::RequestContext;
use strict;
use warnings;

use Socialtext;
use Socialtext::AppConfig;
use Readonly;
use Socialtext::Workspace;
use Socialtext::Validate qw( validate SCALAR_TYPE CODEREF_TYPE REGEX_TYPE USER_TYPE );


{
    Readonly my $spec => {
        uri                 => SCALAR_TYPE,
        notes_callback      => CODEREF_TYPE( optional => 1 ),
        user                => USER_TYPE,
        workspace_uri_regex => REGEX_TYPE,
    };

    sub new {
        my $class = shift;
        my %p     = validate( @_, $spec );

        if ( $p{notes_callback} ) {
            my $noted_context = $p{notes_callback}->('request_context');
            return $noted_context if $noted_context;
        }

        my $self = bless {}, $class;

        my $ws_name;
        ($ws_name) = $p{uri} =~ /$p{workspace_uri_regex}/
            if $p{workspace_uri_regex};

        $self->{main} = $self->_main( $p{uri}, $ws_name );
        $self->_load_hub( $ws_name, $p{user} )
            if $self->{main} && $ws_name;

        if ($p{notes_callback}) {
            $p{notes_callback}->('request_context', $self);
        }

        return $self;
    }
}

sub _main {
    my $self    = shift;
    my $uri     = shift;
    my $ws_name = shift;

    return if $uri =~ m{^/nlw};

    return Socialtext->new();
}

sub _load_hub {
    my $self    = shift;
    my $ws_name = shift;
    my $user    = shift;

    my $workspace = Socialtext::Workspace->new( name => $ws_name );
    return unless $workspace;

    my $main = $self->{main};

    $main->load_hub(
        current_user      => $user,
        current_workspace => $workspace,
    );
    $main->hub()->registry()->load();
    $main->debug();
}

sub hub {
    my $self = shift;
    return unless $self->{main};

    return $self->{main}->hub;
}


1;

__END__
