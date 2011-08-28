package Socialtext::Rest::AccountPluginPrefs;
# @COPYRIGHT@
use Moose;
use Socialtext::AppConfig;
use Socialtext::HTTP ':codes';
use Socialtext::JSON 'decode_json';
use Socialtext::Log 'st_log';
use Socialtext::JSON::Proxy::Helper;
use List::MoreUtils 'all';
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Entity';

has 'account' => (
    is => 'ro', isa => 'Maybe[Socialtext::Account]',
    lazy_build => 1,
);

sub allowed_methods {'PUT'}

sub _build_account {
    my $self = shift;
    return Socialtext::Account->Resolve(Socialtext::String::uri_unescape( $self->acct ));
}

sub PUT_json {
    my $self = shift;

    $self->can_admin(sub {
        my $rest    = $self->rest;
        require Socialtext::Pluggable::Adapter;
        my $adapter = Socialtext::Pluggable::Adapter->new;
        $adapter->make_hub($self->rest->user);
        my $plugin  = $adapter->plugin_object($self->plugin);
        my $acct    = $self->account;
        my $data    = eval { decode_json($self->rest->getContent()) };
        my %valid   = map { $_ => 1 } $plugin->valid_account_prefs();

        if (!$data or ref($data) ne 'HASH') {
            $rest->header( -status => HTTP_400_Bad_Request );
            return 'Content should be a JSON hash.';
        }

        unless (all { defined $valid{$_} } keys %$data) {
            $rest->header( -status => HTTP_400_Bad_Request );
            return 'Unrecognized JSON key';
        }

        eval { $plugin->CheckAccountPluginPrefs($data) };
        if ($@) {
            $rest->header( -status => HTTP_400_Bad_Request );
            chomp $@;
            return $@;
        }

        my $prefs = $plugin->GetAccountPluginPrefTable($acct->account_id);
        $prefs->set(%$data);

        # Clear the json cache so activities widgets get the new limit
        Socialtext::JSON::Proxy::Helper->ClearForAccount($acct->account_id);

        my $plugin_name = $self->plugin;
        st_log()->info(
            $rest->user->username 
            . "changed $plugin_name preferences for " 
            . $acct->name
        );

        $rest->header(-status => HTTP_204_No_Content);
        return "";
    });
}

sub can_admin {
    my $self     = shift;
    my $callback = shift;
 
    return $self->no_resource('Account')
        unless $self->account && $self->account->is_plugin_enabled('signals');

    return $self->not_authorized()
        unless $self->rest->user->is_business_admin;

    return $callback->();
}

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor =>0);
1;

=head1 NAME

Socialtext::Rest::AccountPluginPrefs - Account plugin preferences handler 

=head1 SYNOPSIS

    GET /data/accounts/:acct/plugins/:plugin/preferences

=head1 DESCRIPTION

Update per-account plugin preferences.

=cut

