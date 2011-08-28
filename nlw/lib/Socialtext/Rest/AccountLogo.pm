package Socialtext::Rest::AccountLogo;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::Rest';
use Socialtext::Account;

#sub allowed_methods { 'GET', 'POST' }
sub allowed_methods { 'GET' }
sub workspace { return Socialtext::NoWorkspace->new() }
sub ws { '' }

sub if_authorized {
    my $self = shift;
    my $method = shift;
    my $call = shift;

    if ($method ne 'GET') {
        return $self->bad_method;
    }
#     elsif ($method eq 'POST') {
#         return $self->not_authorized
#             unless ($self->user_can('is_business_admin'));
#     }

    return $self->$call(@_);
}

sub GET_image {
    my $self = shift;
    my $rest = shift;

    my $acct_id = $self->acct;
    my $acct = ($acct_id) ?
        Socialtext::Account->new(account_id => $acct_id) :
        Socialtext::Account->Default();
    my $logo = $acct->logo->logo;
    $rest->header(
        -type          => 'image/png',
        -pragma        => 'no-cache',
        -cache_control => 'no-cache, no-store',
    );
    return $$logo;
}

1;
