package Socialtext::Prefs::Account;
use Moose;
use Socialtext::SQL qw(sql_execute);
use Socialtext::Prefs::System;

with 'Socialtext::Prefs';

has 'account' => (is => 'ro', isa => 'Socialtext::Account', required => 1);

sub _get_blob {
    my $self = shift;
    return $self->account->pref_blob;
}

sub _get_inherited_prefs {
    return Socialtext::Prefs::System->new()->all_prefs;
}

sub _update_db {
    my $self = shift;
    my $blob = shift;

    sql_execute(
        'UPDATE "Account" SET pref_blob = ? WHERE account_id = ?',
        $blob, $self->account->account_id
    );
}

sub _update_objects {
    my $self = shift;
    my $blob = shift;

    $self->account->pref_blob($blob);
    $self->_clear_all_prefs;
    $self->_clear_prefs;
}

__PACKAGE__->meta->make_immutable();
1;

=head1 NAME

Socialtext::Prefs::Account - An index of preferences for an Account.

=head1 SYNOPSIS

    use Socialtext::Prefs::Account

    my $acct_prefs = Socialtext::Prefs::Account->new(account=>$account);

    $acct_prefs->prefs; # all prefs
    $acct_prefs->all_prefs; # all prefs, including inherited system prefs
    $acct_prefs->save({new_index=>{key1=>'value1',key2=>'value2'}});

=head1 DESCRIPTION

Manage the preferences for an Account.

=cut
