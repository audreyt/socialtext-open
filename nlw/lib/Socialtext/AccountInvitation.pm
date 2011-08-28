package Socialtext::AccountInvitation;
# @COPYRIGHT@
use Moose;
use Socialtext::l10n qw(loc);
use namespace::clean -except => 'meta';

extends 'Socialtext::Invitation';

our $VERSION = '0.01';

has 'account' => (
    is       => 'ro', isa => 'Socialtext::Account',
    required => 1,
);

sub object { shift->account }
sub id_hash { return (account_id => shift->account->account_id) }

sub _name {
    my $self = shift;
    return $self->account->name;
}

sub _subject {
    my $self = shift;
    loc("invite.group=name", $self->account->name);
}

sub _template_type { 'account' }

sub _template_args {
    my $self = shift;
    return (
        account_name => $self->account->name,
        account_uri  => Socialtext::URI::uri(path => '/'),
    );
}

__PACKAGE__->meta->make_immutable;
1;
