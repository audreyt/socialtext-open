package Socialtext::Authz::SimpleChecker;
# @COPYRIGHT@
use Moose;

use Carp qw/croak/;
use Socialtext::Authz;
use Socialtext::Permission;
use namespace::clean -except => 'meta';

has 'user' => (
    is => 'ro', isa => 'Socialtext::User',
    required => 1,
);

has 'container' => (
    is => 'ro', isa => 'Object',
    required => 1,
);

has 'authz' => (
    is => 'ro', isa => 'Socialtext::Authz',
    lazy_build => 1,
);
sub _build_authz {
    return Socialtext::Authz->new();
};

has 'version' => (
    is => 'ro', isa => 'Str',
    default => sub { '0.01' },
);

sub check_permission {
    my $self       = shift;
    my $perm_name  = shift;
    my $permission = Socialtext::Permission->new(name => $perm_name);

    if ($self->container->isa('Socialtext::Workspace')) {
        return $self->authz->user_has_permission_for_workspace(
            user       => $self->user,
            permission => $permission,
            workspace  => $self->container,
        );
    }
    elsif ($self->container->isa('Socialtext::Group')) {
        return $self->authz->user_has_permission_for_group(
            user       => $self->user,
            permission => $permission,
            group      => $self->container,
        );
    }
    elsif ($self->container->isa('Socialtext::Account')) {
        return $self->authz->user_has_permission_for_account(
            user       => $self->user,
            permission => $permission,
            account    => $self->container,
        );
    }
    else {
        croak "Unknown container type: " . ref($self->container);
    }
}

sub can_modify_locked {
    my $self = shift;
    my $page = shift;

    croak 'container may only be a Workspace'
        unless $self->container->isa('Socialtext::Workspace');

    return 1 unless ($self->container->allows_page_locking);
    return 1 unless ($page->locked);
    return $self->check_permission('lock');
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 NAME

Socialtext::Authz::SimpleChecker - Simplified permission checks

=head1 SYNOPSIS

  use Socialtext::Authz::SimpleChecker

  my $checker = Socialtext::Authz::SimpleChecker->new(
      user       => $user,
      workspace  => $workspace,
  );

  if ( $checker->check_permission('read') ) {
      ....
  }

=head1 DESCRIPTION

This module simplifies permission checking by storing a user and
workspace internally, and accepting permission names as strings. It is
primarily intended for use inside templates, to make them read more
nicely in the common case of checking permissions for the current user
on the current workspace.

=head1 METHODS/FUNCTIONS

This class provides the following methods:

=head2 Socialtext::Authz::SimpleChecker->new(PARAMS)

Returns a new C<Socialtext::Authz::SimpleChecker> object for a given
user and workspace.

Requires the following PARMS:

=over 8

=item * user - a user object

=item * container - a workspace or group object

=back

=head2 $checker->check_permission($perm_name)

Given a permission name (not an object), returns a boolean indicating
whether the object's user has that permission for the object's workspace.

=head2 $checker->can_modify_locked($page)

Given a page, returns true if the page can be locked or unlocked.

=head1 AUTHOR

Socialtext, C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc. All Rights Reserved.

=cut
