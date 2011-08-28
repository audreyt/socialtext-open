package Test::Socialtext::AccountContext::features::Users;
# @COPYRIGHT@
use Moose;
use Test::Socialtext;
use namespace::clean -except => 'meta';

with 'Test::Socialtext::AccountContext::features';

sub Tests { 6 }

sub prepare {
    my $self = shift;
    my $account = $self->fetch_feature_share('Accounts', 'export');
    my $account_user = create_test_user(
        unique_id => 'account.user',
        account   => $account,
    );
    return $self->_validate();
}

sub validate { return shift->_validate() };

sub _validate {
    my $self = shift;
    my $account = $self->fetch_feature_share('Accounts', 'export');
    my $account_user = Socialtext::User->new(
        email_address => 'account.user@ken.socialtext.net');
    isa_ok $account_user, 'Socialtext::User', 'account user exists';

    my $role = $account->role_for_user($account_user);
    ok $role, 'account user has role in account';
    is $role->name, 'member', '... is a member role';

    # return the stuff we want to share with other features.
    return +{account_user=>$account_user};
}

__PACKAGE__->meta->make_immutable;
1;

=head1 NAME

Test::Socialtext::AccountContext::features::Users - A Users feature for
contextual Accounts.

=head1 SYNOPSIS

    use Test::Socialtext::AccountContext;

    my $context = Test::Socialtext::AccountContext->new(export_name=>$name);
    my $users = $context->registry->{Users};

    ...

=head1 DESCRIPTION

A Feature for contextual Accounts that can be used to manage Users.

=cut
