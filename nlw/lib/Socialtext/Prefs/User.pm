package Socialtext::Prefs::User;
use Moose;
use Socialtext::SQL qw(sql_singlevalue sql_execute);
use Socialtext::Prefs::Account;

with 'Socialtext::Prefs';

has 'user' => (is => 'ro', isa => 'Socialtext::User', required => 1);

sub _get_blob {
    my $self = shift;

    return sql_singlevalue(qq{
        SELECT pref_blob
          FROM user_pref
         WHERE user_id = ?
    }, $self->user->user_id);
}

sub _get_inherited_prefs {
    my $self = shift;
    return $self->user->primary_account->prefs->all_prefs;
}

sub _update_db {
    my $self = shift;
    my $blob = shift;
    my $user_id = $self->user->user_id;

    sql_execute('DELETE FROM user_pref WHERE user_id = ?', $user_id);
    return unless $blob;

    sql_execute(
        'INSERT INTO user_pref (user_id,pref_blob) VALUES (?,?)',
        $user_id, $blob
    );
}

sub _update_objects {
    my $self = shift;
    my $blob = shift;

    $self->_clear_all_prefs;
    $self->_clear_prefs;
}

__PACKAGE__->meta->make_immutable();
1;

=head1 NAME

Socialtext::Prefs::User - An index of preferences for a User.

=head1 SYNOPSIS

    use Socialtext::Prefs::User

    my $user_prefs = Socialtext::Prefs::User->new(user=>$user);

    $user_prefs->prefs; # all prefs
    $user_prefs->all_prefs; # all prefs, including inherited account prefs
    $user_prefs->save({new_index=>{key1=>'value1',key2=>'value2'}});

=head1 DESCRIPTION

Manage the preferences for a User.

=cut
