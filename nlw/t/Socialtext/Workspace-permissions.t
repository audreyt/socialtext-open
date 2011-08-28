#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::Account;
use Socialtext::Permission qw( ST_ADMIN_WORKSPACE_PERM ST_EMAIL_IN_PERM ST_LOCK_PERM );
use Socialtext::Role;
use Socialtext::Workspace;
use Test::Socialtext tests => 73;
fixtures(qw( clean db ));

{
    my %sets = (
        'member-only'             => 'Private',
        'self-join'               => 'Self-Join',
        'public'                  => 'Public',
        'authenticated-user-only' => 'Public',
        'public-read-only'        => 'Public',
        'public-comment-only'     => 'Public',
        'public-join-to-edit'     => 'Public',
        'intranet'                => 'Public',
    );
    for my $set_name (keys %sets) {
        my $ws = Socialtext::Workspace->create(
            name       => $set_name,
            title      => 'Test',
            account_id => Socialtext::Account->Socialtext()->account_id,
            skip_default_pages => 1,
        );

        $ws->permissions->set( set_name => $set_name );

        is( $ws->permissions->current_set_name(), $set_name,
            "current permission set is $set_name" );

        is $ws->permissions->current_set_display_name, $sets{$set_name},
           "current permission display name is $sets{$set_name}";

        my %p = (
            role       => Socialtext::Role->Guest(),
            permission => ST_EMAIL_IN_PERM,
        );
        my $guest_has_email_in = $ws->permissions->role_can(%p);

        if ($guest_has_email_in) {
            $ws->permissions->remove(%p);
        }
        else {
            $ws->permissions->add(%p);
        }

        is( $ws->permissions->current_set_name, $set_name,
            "current permission set is still $set_name regardless of guest's email_in permission" );

        $ws->permissions->set( set_name => $set_name );

        is( $ws->permissions->role_can(%p), ( $guest_has_email_in ? 0 : 1 ),
            "guest's email_in permission is unchanged after second call to set_permissions()" );

        %p = (
            role       => Socialtext::Role->Admin(),
            permission => ST_LOCK_PERM,
        );
        my $admin_has_lock = $ws->permissions->role_can(%p);
        is( $admin_has_lock, 1, 'Admin has page lock permissions');

	my %defaults;
        $defaults{allows_html_wafl} = ( $set_name =~ /^(member|intranet|public\-read|self\-join)/ ) ? 1 : 0;
        $defaults{email_addresses_are_hidden} = ( $set_name =~ /^(member|intranet|self\-join)/ ) ? 0 : 1 ;
        $defaults{email_notify_is_enabled} = ( $set_name =~ /^public/ ) ? 0 : 1;
        $defaults{homepage_is_dashboard} = ( $set_name eq 'member-only' ) ? 1 : 0;

        for my $k ( sort keys %defaults ) {
            is( $ws->$k(), $defaults{$k}, "$k is $defaults{$k}" );
        }
    }

    my $ws = Socialtext::Workspace->new( name => 'intranet' );
    $ws->permissions->add(
        role       => Socialtext::Role->Guest(),
        permission => ST_ADMIN_WORKSPACE_PERM,
    );

    is( $ws->permissions->current_set_name(), 'custom',
        'current permission set is custom' );
}


# XXX - needs more tests of methods for setting/removing permissions
