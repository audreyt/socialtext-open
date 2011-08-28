package Socialtext::User::Restrictions::base;

use Moose::Role;
use Socialtext::Date;
use Socialtext::MooseX::Types::Pg;
use Socialtext::User::Restrictions;

requires '_restriction_type';
requires 'send';
requires 'confirm';
around 'confirm' => sub {
    my $orig = shift;
    my $self = shift;
    $self->$orig();
    $self->clear;
};

has 'user_id' => (
    is          => 'ro',
    isa         => 'Int',
    required    => 1,
);

has 'restriction_type' => (
    is         => 'ro',
    isa        => 'Str',
    lazy_build => 1,
);
sub _build_restriction_type {
    return shift->_restriction_type;
}

has 'user' => (
    is         => 'ro',
    isa        => 'Socialtext::User',
    lazy_build => 1,
);
sub _build_user {
    my $self = shift;
    require Socialtext::User;
    my $user = Socialtext::User->new(user_id => $self->user_id);
}

has 'token' => (
    is       => 'ro',
    isa      => 'Str',
    writer   => '_set_token',
);

has 'expires_at' => (
    is       => 'ro',
    isa      => 'Pg.DateTime',
    writer   => '_set_expires_at',
    required => 1,
    coerce   => 1,
);

has 'workspace_id' => (
    is  => 'ro',
    isa => 'Maybe[Int]',
);

has 'workspace' => (
    is         => 'ro',
    isa        => 'Maybe[Socialtext::Workspace]',
    lazy_build => 1,
);
sub _build_workspace {
    my $self = shift;
    my $wsid = $self->workspace_id;
    return unless $wsid;
    require Socialtext::Workspace;
    return Socialtext::Workspace->new(workspace_id => $wsid);
}

sub CreateOrReplace {
    my $class = shift;
    my %opts  = @_;
    Socialtext::User::Restrictions->CreateOrReplace( {
        %opts,
        restriction_type => $class->_restriction_type,
    } );
}

sub Get {
    my $class = shift;
    my %opts  = @_;
    return Socialtext::User::Restrictions->Get( {
        %opts,
        restriction_type => $class->_restriction_type,
    } );
}

sub update {
    my $self  = shift;
    my $proto = shift;
    Socialtext::User::Restrictions->Update($self, $proto);
}

sub clear {
    my $self = shift;
    Socialtext::User::Restrictions->Delete($self);
}

sub has_expired {
    my $self       = shift;
    my $now        = Socialtext::Date->now;
    my $expires_at = $self->expires_at;
    return $expires_at < $now;
}

sub renew {
    my $self = shift;
    my $when = Socialtext::User::Restrictions->DefaultExpiry;
    $self->update( { expires_at => $when } );
}

sub to_hash {
    my $self = shift;
    return {
        restriction_type => $self->restriction_type,
        token            => $self->token,
        expires_at       => $self->expires_at,
        workspace_id     => $self->workspace_id,
    };
}

1;

=head1 NAME

Socialtext::User::Restrictions::base - Base role for User Restrictions

=head1 SYNOPSIS

    my $restriction = Socialtext::User::Restrictions->FetchByToken($token);

    # check if restriction has expired
    if ($restriction->has_expired) {
        ...
    }

    # clear/remove/delete the restriction
    $restriction->clear;

=head1 DESCRIPTION

This module provides a Moose Role for User Restrictions; restrictions placed
on a User record that would prevent them from having access to the system
until some other condition has been met (and the restriction cleared).

=head1 REQUIREMENTS

In order to consume this Role, your class will need to provide implementations
for the following methods:

=over

=item _restriction_type()

Returns the restriction type to be stored in the DB.  B<Must> match up with
your class name.

=item send()

Method which performs whatever actions are necessary to send out notification
to the User that they have a restriction on their user record and that a
confirmation is required.

If your particular restriction has no notification to be sent out to the User,
simply implement an empty sub.

=item confirm()

Method which performs whatever actions are necessary to confirm the
restriction.  This base Role will ensure that the restriction is
cleared/removed immediately after this method is called; you do not need to
clear the restriction in your class.

=back

=head1 ATTRIBUTES

=over

=item user_id

B<Required.>  Id for the User that this restriction is for.

=item user

Easy accessor to a User object for our C<user_id>.

=item token

A unique sha/hash/token that can be used to uniquely identify this Restriction.

=item expires_at

B<Required.>  Date/time that the restriction expires at.

=item workspace_id

Workspace Id for the Workspace that the User is being invited into.

Yes, this B<is> somewhat out of place here; its present because the original
implementation allowed for a Workspace Id to be provided when confirming an
e-mail address so that the User would be auto-added to the Workspace once the
e-mail address was confirmed.

=item workspace

Easy accessor to a Workspace object for our C<workspace_id>.

=back

=head1 METHODS

=over

=item $class->CreateOrReplace(%params)

Creates (or replaces) an existing Restriction of the derived type, for the
User.

B<Note,> a User can B<only> have I<one> Restriction of any given Type at any
time; thus the desire for a quick/easy way to create/replace the existing
record in the DB with an almost identical one.

=item $class->Get(user_id => $user_id)

Retrieves the Email Confirmation Restriction for the User specified by the
provided C<$user_id>.

=item $restriction->update( { ... } )

Updates the Restriction based on the hash-ref of information provided.

=item $restriction->clear()

Clears the restriction, removing it from the DB.

=item $restriction->has_expired()

Returns true if the Restriction has expired and can not be completed any
longer, returning false otherwise.

=item $restriction->renew()

Renews the restriction, extending it by the default expration period.

=back

=head1 COPYRIGHT

Copyright 2011 Socialtext, Inc., All Rights Reserved.

=cut
