package Socialtext::Rest::AccountUsers;
# @COPYRIGHT@
use Moose;
use Socialtext::Account;
use Socialtext::JSON qw/decode_json/;
use Socialtext::HTTP ':codes';
use Socialtext::User::Find::Container;
use Socialtext::String;
use Socialtext::User;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Users';

has 'account' => (
    is => 'ro', isa => 'Maybe[Socialtext::Account]',
    lazy_build => 1,
);
sub _build_account {
    my $self = shift;
    Socialtext::Account->Resolve($self->acct);
};

sub allowed_methods { 'POST', 'GET', 'DELETE' }
sub collection_name { 
    my $acct =  ( $_[0]->acct =~ /^\d+$/ ) 
            ? 'with ID ' . $_[0]->acct
            : $_[0]->acct; 
    return 'Users in Account ' . $acct;
}

sub workspace { return Socialtext::NoWorkspace->new() }
sub ws { '' }

sub if_authorized {
    my $self = shift;
    my $method = shift;
    my $call = shift;

    my $acting_user = $self->rest->user;
    my $checker = $self->hub->checker;

    if ($method eq 'POST' or $method eq 'DELETE') {
        return $self->not_authorized 
            unless $acting_user->is_business_admin();
    }
    elsif ($method eq 'GET') {
        return $self->no_resource('Account') unless $self->account;

        return $self->not_authorized
            unless $acting_user->is_business_admin()
                || $self->account->has_user($acting_user);
    }
    else {
        return $self->bad_method;
    }

    return $self->$call(@_);
}

sub _build_user_find {
    my $self = shift;
    my $query = $self->rest->query;

    my $show_pvt = $query->param('want_private_fields') 
        && $self->rest->user->is_business_admin;

    return Socialtext::User::Find::Container->new(
        viewer => $self->rest->user,
        limit  => $self->items_per_page,
        offset => $self->start_index,
        filter => $query->param('filter') || undef,
        container => $self->account,
        direct => $query->param('direct') || 0,
        minimal => $query->param('minimal') || 0,
        order => $query->param('order') || '',
        reverse => $query->param('reverse') || 0,
        all => $query->param('all') || 0,
        show_pvt => $show_pvt,
    )
}

sub POST_json {
    my ($self, $rest) = @_;
    return $self->if_authorized('POST', sub {
        $self->_POST_json($rest);
    });
}

sub _POST_json {
    my $self = shift;
    my $rest = shift;

    my $account = Socialtext::Account->Resolve(Socialtext::String::uri_unescape( $self->acct ));
    unless ( defined $account ) {
        $rest->header( -status => HTTP_404_Not_Found );
        return "Could not find that account.";
    }

    my $data = eval { decode_json( $rest->getContent ) };
    if ($@) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return "Could not parse JSON";
    }

    my $user_id = $data->{email_address}
        || $data->{username}
        || $data->{user_id};
    unless ( defined $user_id ) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return "No email_address, username or user_id provided!";
    }
    my $user = eval { Socialtext::User->Resolve($user_id) };
    if ($@ or !defined $user) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return "Could not resolve the user: $user_id";
    }

    my $role_name = $data->{role_name} || 'member';
    my $role = Socialtext::Role->new(name => $role_name);
    unless ($role) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return "Invalid role name: '$role_name'";
    }

    my $has_role = $account->role_for_user($user, direct => 1);
    unless ($has_role && $has_role->role_id == $role->role_id) {
        eval {
            $account->assign_role_to_user( user => $user, role => $role );
        };
        if ( $@ ) {
            $rest->header( -status => HTTP_400_Bad_Request );
            return "Could not add user to the account: $@";
        }

        if ($user->is_deactivated) {
            my $deleted_account = $user->primary_account;
            $user->primary_account($account);
            $deleted_account->remove_user(user => $user);
        }
    }

    $rest->header( -status => HTTP_201_Created );
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

    my $account = Socialtext::Account->Resolve(Socialtext::String::uri_unescape( $self->acct ));
    unless ( defined $account ) {
        $rest->header( -status => HTTP_404_Not_Found );
        return "Could not find that account.";
    }

    my $user_id = $self->username;
    my $user = eval { Socialtext::User->Resolve($user_id) };
    if ($@ or !defined $user) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return "Could not resolve the user: $user_id";
    }

    if ($user->primary_account->account_id == $account->account_id) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return "Cannot remove a user from their primary account.";
    }

    my @roles = Socialtext::Account::Roles->RolesForUserInAccount(
        user => $user,
        account => $account,
        direct => "yes",
    );
    unless (@roles) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return "User does not belong to this account.";
    }

    eval { $account->remove_user(user => $user) };
    if ( $@ ) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return "Could not remove user from the account: $@";
    }

    $rest->header( -status => HTTP_204_No_Content );
    return '';
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
