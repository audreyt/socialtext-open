package Socialtext::Rest::UserSharedAccounts;
# @COPYRIGHT@

use warnings;
use strict;

use base 'Socialtext::Rest::Collection';

use Socialtext::User;
use Socialtext::HTTP qw(:codes);

# FIXME: Attention paid to permissions is incomplete.

our $k;

# We punt to the permission handling stuff below.
sub permission { +{ GET => undef } }
sub entity_name { "User " . $_[0]->username . " accounts" }

sub authorized_to_view {
    my ($self, $user) = @_;
    my $acting_user = $self->rest->user;
    return $user
        && (   $acting_user->is_business_admin()
            || ( $user->username eq $acting_user->username )
        );
}

sub _entities_for_query {
    my ($self, $rest) = @_;

    my $user = Socialtext::User->new( username => $self->username );
    my $other = Socialtext::User->new( username => $self->otheruser );

    unless ($self->authorized_to_view($user)) {
        $self->rest->header( -status => HTTP_401_Unauthorized );
        return ();
    }
    return $user->shared_accounts($other);
}

sub _entity_hash {
    my ($self, $account) = @_;
    $account->hash_representation(user_count => 1);
}

1;
