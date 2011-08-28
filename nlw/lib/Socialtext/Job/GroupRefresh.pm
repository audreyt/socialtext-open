package Socialtext::Job::GroupRefresh;
# @COPYRIGHT@
use Moose;
use Socialtext::Group;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

# LDAP Group Refresh jobs are expected to be long running
# XXX: this'd be *far* better done using MooseX::ClassAttribute
sub is_long_running { 1 }

has proto_group => (
    is => 'ro', isa => 'HashRef',
    lazy_build => 1,
);

# If we were to fetch the group directly, we may fire off an unintented
# refresh, so let's peek at it's prototype.
sub _build_proto_group {
    my $self = shift;
    my $group_id = $self->arg->{group_id};

    my $proto_group =
        Socialtext::Group->GetProtoGroup( { group_id => $group_id } );

    unless ( $proto_group ) {
        my $msg = "group_id $group_id does not exist\n";
        $self->permanent_failure( $msg );
        die "$msg\n";
    }

    return $proto_group;
}

sub do_work {
    my $self          = shift;
    my $proto         = $self->proto_group;

    # always force the refresh from the underlying store
    local $Socialtext::Group::Factory::CacheEnabled = 0;
    local $Socialtext::Group::Factory::Asynchronous = 0;

    # clear the in-memory Group cache, so we *know* we're going to the DB
    # and to LDAP to refresh the Group.
    Socialtext::Group->cache->clear();

    # refresh the Group
    Socialtext::Group->GetGroup( { group_id => $proto->{group_id} } );

    $self->completed();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::GroupRefresh - Refresh an LDAP group cache.

=head1 SYNOPSIS

    use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::GroupRefresh',
        { group_id => 10 },
    );

=head1 DESCRIPTION

Schedule a job to be run by TheCeq which will refresh an LDAP group's cache of
user data.

=cut
