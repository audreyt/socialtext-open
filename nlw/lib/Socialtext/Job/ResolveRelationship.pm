package Socialtext::Job::ResolveRelationship;
# @COPYRIGHT@
use Moose;
use namespace::clean -except => 'meta';
use Socialtext::Cache;
use Socialtext::User;

# Ensure these modules are loaded
use Socialtext::User::LDAP::Factory;
use Socialtext::Pluggable::Plugin::People;

extends 'Socialtext::Job';

# LDAP User Relationship Resolution jobs are potentially long running
sub is_long_running { 1 }

sub do_work {
    my $self    = shift;
    my $user_id = $self->arg->{user_id};

    # force synchronous resolution of the User and their relationships
    local $Socialtext::User::LDAP::Factory::CacheEnabled = 0;
    local $Socialtext::Pluggable::Plugin::People::Asynchronous = 0;

    # clear in-memory caches, so we *know* we're going to the DB and to LDAP
    # to refresh the User.
    Socialtext::Cache->clear();

    # forcably refresh the User from LDAP, triggering the resolution of any
    # relationships that may exist in their People Profile
    eval { Socialtext::User->new(user_id => $user_id) };
    if ($@) {
        my $msg = "Unable to resolve relationships for UserId $user_id; $@";
        $self->permanent_failure($msg);
        die "$msg\n";
    }

    $self->completed();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::ResolveRelationship - Resolve People Profile relationships

=head1 SYNOPSIS

  use Socialtext::JobCreator
  Socialtext::JobCreator->resolve_relationships(
      user_id => $user->user_id,
  );

=head1 DESCRIPTION

Schedule a job to be run which will refresh the User and resolve all of the
relationships in their People Profile (which may require us to make multiple
LDAP requests in order to follow through a chain of relationships).

=cut
