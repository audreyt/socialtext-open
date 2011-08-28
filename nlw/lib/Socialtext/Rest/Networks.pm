package Socialtext::Rest::Networks;
# @COPYRIGHT@
use Moose;
use Socialtext::Group;
use Socialtext::HTTP ':codes';
use Socialtext::JSON qw/encode_json/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Collection';
with 'Socialtext::Rest::Pageable';

# Anybody can see these, since they are just the list of groups & accounts
# the user is in.
sub permission { +{} }

sub collection_name { 'Networks' }

sub _entity_hash { 
    my ($self, $thing) = @_;

    (my $type = ref($thing)) =~ s/^Socialtext::(.+)/lc($1)/e;
    my $id_method = $type . '_id';
    return {
        type => $type,
        id => $thing->$id_method,
        name => $thing->name,
    };
}

sub _get_total_results {
    my $self = shift;
    my $user = $self->rest->user;
    return $self->{_total} || 0;
}

# Possible improvements:
# * First filter by the filter prefix, then limit by visibility for this user
# * Single query with two left joins (all user sets i can see, joined with
#   groups, joined with account), filter by account_name OR group_name match
sub _get_entities {
    my $self = shift;
    my $user = $self->rest->user;
    my $q    = $self->rest->query;

    my $filter = $q->param('filter') || '';
    my $discoverable = $q->param('discoverable');
 
    # Return all accounts
    my @networks = (
        $user->accounts(),
        $user->groups(discoverable => $discoverable)->all,
    );

    if ($filter) {
        @networks = grep { $_->name =~ m/^\Q$filter\E/i } @networks;
    }

    $self->{_total} = scalar @networks;
    return \@networks;
}

override extra_headers => sub {
    my $self = shift;
    my $resource = shift;

    return (
        '-cache-control' => 'private',
    );
};

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::Networks - List accounts and groups on the system.

=head1 SYNOPSIS

    GET /data/networks

=head1 DESCRIPTION

View the list of accounts and discoverable groups.

Each result entity has a C<type> field, with C<account> and C<group>
as possible values.

=cut
