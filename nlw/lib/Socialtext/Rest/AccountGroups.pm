package Socialtext::Rest::AccountGroups;
# @COPYRIGHT@
use Moose;
use Socialtext::Account;
use Socialtext::HTTP ':codes';
use Socialtext::JSON qw/decode_json/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Collection';

has 'account' => (is => 'ro', isa => 'Maybe[Object]', lazy_build => 1);

sub permission { +{ GET => undef, POST => undef } }
sub allowed_methods { 'POST', 'GET', 'DELETE' }
sub collection_name { "Account Groups" }

sub _entities_for_query {
    my $self      = shift;
    my $rest      = $self->rest;
    my $user      = $rest->user;
    my $account   = $self->account or return ();

    my @groups;
    my $group_cursor = $account->groups();
    if ($user->is_business_admin) {
        @groups = $group_cursor->all();
    }
    else {
        while (my $g = $group_cursor->next) {
            eval {
                if ($g->creator->user_id == $user->user_id 
                        or $g->has_user($user)) {
                    push @groups, $g;
                }
            };
            warn $@ if $@;
        }
    }

    return @groups;
}

sub _build_account {
    my $self = shift;

    return Socialtext::Account->Resolve(Socialtext::String::uri_unescape( $self->acct ));
}

sub _entity_hash {
    my $self  = shift;
    my $group = shift;

    return $group->to_hash( show_members => $self->{_show_members} );
}

around get_resource => sub {
    my $orig = shift;
    my $self = shift;

    $self->{_show_members} = $self->rest->query->param('show_members') ? 1 : 0;
    return $orig->($self, @_);
};

sub POST_json {
    my $self = shift;
    my $rest = shift;
    my $data = decode_json( $rest->getContent() );

    unless ($self->user_can('is_business_admin')) {
        $rest->header(
            -status => HTTP_401_Unauthorized,
        );
        return '';
    }

    my $account = $self->account;
    unless ( defined $account ) {
        $rest->header(
            -status => HTTP_404_Not_Found,
        );
        return '';
    }

    unless ( defined $data and ref($data) eq 'HASH' ) {
        $rest->header(
            -status => HTTP_400_Bad_Request,
        );
        return '';
    }

    my $group_id = $data->{group_id};
    unless ($group_id) {
        $rest->header(
            -status => HTTP_400_Bad_Request,
        );
        return "Missing a group_id";
    }

    my $group = Socialtext::Group->GetGroup(group_id => $group_id);
    unless ($group) {
        $rest->header(
            -status => HTTP_400_Bad_Request,
        );
        return "Group_id ($group_id) is not a valid group";
    }

    my $role;
    if (my $role_name = $data->{role_name}) {
        $role = Socialtext::Role->new(name => $role_name);
    }

    if ($account->has_group($group)) {
        $rest->header(
            -status => HTTP_409_Conflict,
        );
        return "Group_id ($group_id) is already in this account.";
    }

    $account->add_group(
        group => $group,
        ($role ? (role => $role) : ()),
    );

    $rest->header(
        -status => HTTP_204_No_Content,
    );
    return '';
}

sub DELETE {
    my ($self, $rest) = @_;
    return $self->if_authorized('DELETE', sub {
        $self->_DELETE($rest);
    });
}

sub _DELETE {
    my ( $self, $rest ) = @_;

    unless ( $self->account ) {
        $rest->header( -status => HTTP_404_Not_Found );
        return "Could not find that account.";
    }

    my $group_id = $self->group_id;
    my $group = Socialtext::Group->GetGroup(group_id => $group_id);
    if ($@ or !defined $group) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return "Could not find group $group_id";
    }

    if ($group->primary_account->account_id == $self->account->account_id) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return "Cannot remove a group from their primary account.";
    }

    eval { $self->account->remove_group(group => $group) };
    if ( $@ ) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return "Could not remove group from the account: $@";
    }

    $rest->header( -status => HTTP_204_No_Content );
    return '';
}


__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
1;

=head1 NAME

Socialtext::Rest::AccountGroups - Groups in an account.

=head1 SYNOPSIS

    GET /data/accounts/:acct/groups

    POST /data/accounts/:acct/groups as application/json
    - Body should be a JSON hash containing a group_id and optionally a role_name.

=head1 DESCRIPTION

Every Socialtext account has a collection of zero or more groups
associated with it. At the URI above, it is possible to view a list of those
groups.

=cut
