package Socialtext::AccountFactory;
# @COPYRIGHT@
use Moose;
use Socialtext::Account;
use namespace::clean -except => 'meta';

extends 'Socialtext::Base';

sub class_id { 'account_factory' }

sub create {
    my $self = shift;
    my %p    = @_;

    my $acct = Socialtext::Account->create( %p );

    $self->hub->pluggable->hook('nlw.finish_account_create', [$acct]);

    return $acct;
}

no Moose;
__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
1;

=head1 NAME

Socialtext::AccountFactory - a factory for creating accounts.

=head1 SYNOPSIS

  $self->hub->account_factory->create( name => $name );

=head1 DESCRIPTION

C<Socialtext::AccountFactory> creates an account and calls the account_create
pluggable plugin hooks.

=cut
