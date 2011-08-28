# @COPYRIGHT@
package Socialtext::EmailReceiver::Factory;
use strict;
use Readonly;
use Socialtext::l10n qw(system_locale);
use Socialtext::EmailReceiver::en;
use Socialtext::Validate
    qw( validate SCALAR_TYPE HANDLE_TYPE WORKSPACE_TYPE );
use Email::MIME;

Readonly my $spec_with_handle => {
    handle    => HANDLE_TYPE,
    workspace => WORKSPACE_TYPE,
};

Readonly my $spec_with_stirng => {
    string    => SCALAR_TYPE,
    workspace => WORKSPACE_TYPE,
};


sub _create_email {
    my $class  = shift;
    my $param = shift;
    my $handle = $param->{handle};
    my $string = $param->{string};
    my $workspace = $param->{workspace};
    my $email;
    if( $handle )
    {
       my @param = ('handle', $handle, 'workspace', $workspace);
       my $spec = $spec_with_handle;
       my %p = validate(@param, $spec);
       my $h = $p{handle};
       $email = Email::MIME->new( do { local $/; <$h>} );

    }
    elsif( $string )
    { 
        my @param =('string', $string, 'workspace', $workspace);
        my $spec = $spec_with_stirng;
        my %p = validate(@param, $spec);
        $email = Email::MIME->new( $p{string}, $p{workspace}  );
    }
    else
    {
        die "spec must be specified.";
    }

    return $email;
}

sub create {
    my $class = shift;
    my $param = shift;
    my $email = $class->_create_email($param);
    my $workspace = $param->{workspace};
    my $locale = $param->{locale};

    my $receiver_class = _get_class($locale);
    eval "use $receiver_class";
    if ($@) {
        $locale = system_locale();
        $receiver_class = _get_class($locale);

        # this code is used when we use test locale
        eval "use $receiver_class";
        if($@) {
            $receiver_class = 'Socialtext::EmailReceiver::en'
        }
    }

    return $receiver_class->_new($email, $workspace);
}

sub _get_class {
    my $locale = shift;
    my $receiver_class  = "Socialtext::EmailReceiver::" . $locale;
    return $receiver_class;
}

1;
