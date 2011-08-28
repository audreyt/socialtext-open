package Socialtext::Rest::Account;
# @COPYRIGHT@
use Moose;
use Socialtext::Account;
use Socialtext::JSON 'encode_json';
use Socialtext::Role;
use Socialtext::String;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Entity';

has 'account' => (
    is => 'ro', isa => 'Maybe[Socialtext::Account]',
    lazy_build => 1,
);
sub _build_account {
    my $self = shift;
    return Socialtext::Account->Resolve(Socialtext::String::uri_unescape( $self->acct ));
}

sub allowed_methods { 'GET' }

sub GET_json {
    my $self = shift;

    $self->can_view(sub {
        require Socialtext::Pluggable::Adapter;
        my $acct = $self->account;

        my $data = {
            name               => $acct->name,
            account_id         => $acct->account_id,
            account_type       => $acct->account_type,
            skin_name          => $acct->skin_name,
            restrict_to_domain => $acct->restrict_to_domain,
            plugins            => [$acct->plugins_enabled],
            plugin_preferences => 
                Socialtext::Pluggable::Adapter->new->account_preferences(
                    account       => $acct,
                    with_defaults => 1,
                ),
        };

        $self->rest->header(-type => 'application/json');
        return encode_json($data);
    });
}

sub can_view {
    my $self = shift;
    my $cb   = shift;

    return $self->no_resource('Account') unless $self->account;

    return $self->not_authorized()
        unless $self->rest->user->is_business_admin;

    return $cb->();
}

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::Account - Account resource handler

=head1 SYNOPSIS

    GET /data/accounts/:acct

=head1 DESCRIPTION

View an Account.

=cut
