#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::HTTP::Socialtext '-syntax';

use Readonly;
use List::Util 'sum';
use Socialtext::Permission qw(
    ST_READ_PERM ST_EDIT_PERM ST_ATTACHMENTS_PERM ST_COMMENT_PERM
    ST_DELETE_PERM ST_EMAIL_IN_PERM ST_EMAIL_OUT_PERM ST_EDIT_CONTROLS_PERM
    ST_REQUEST_INVITE_PERM ST_ADMIN_WORKSPACE_PERM
);
use Test::Live fixtures => ['admin'];

our ( $a, $b );

Readonly my $BASE => Test::HTTP::Socialtext->url('/data');

# The keys are (method, permission) pairs and the value is a list of URIs.
# Each URI should return 403 if the user attempts method without permission.
# read, edit, attachments, comment, delete, admin_workspace
my %uris = (
    GET => {
        'read' => [
            'workspaces/:ws/pages/:pname/tags/:tag',
            'workspaces/:ws/pages/:pname/tags',
            'workspaces/:ws/pages/:pname/revisions/:revision_id',
            'workspaces/:ws/pages/:pname/revisions',
            'workspaces/:ws/pages/:pname/backlinks',
            'workspaces/:ws/pages/:pname/attachments',
            'workspaces/:ws/pages/:pname',
            'workspaces/:ws/pages',
            'workspaces/:ws/tags/:tag/pages',
            'workspaces/:ws/tags/:tag',
            'workspaces/:ws/tags',
            'workspaces/:ws/attachments/:attachment_id',
            'workspaces/:ws/attachments',
            'workspaces/:ws/users',
            'workspaces/:ws/homepage',
            'workspaces/:ws',
        ],
    },
    PUT => {
        edit => [
            'workspaces/:ws/pages/:pname',
            'workspaces/:ws/pages/:pname/tags/:tag',
        ],
        # is_business_admin => [ '/data/workspaces', ],
    },
    DELETE => {
        'delete' => [
            'workspaces/:ws/pages/:pname',
        ],
        edit => [
            'workspaces/:ws/pages/:pname/tags/:tag',
        ],
        attachments => [
            'workspaces/:ws/attachments/:attachment_id',
        ],
    },
    POST => {
        edit => [
            'workspaces/:ws/pages',
            'workspaces/:ws/pages/:pname/tags',
        ],
        comment => [
            'workspaces/:ws/pages/:pname/comments',
        ],
        attachments => [
            'workspaces/:ws/pages/:pname/attachments',
        ],
    },
);

# FIXME: Add plan() to Test::HTTP.
Test::Builder->new->plan(
    tests => sum map { scalar @$_ }
        map { values %$_ } values %uris
);

# Although many of these are sensical, they shouldn't all have to be in order
# to get the 403.
Readonly my %REPLACEMENTS => (
    ws            => 'admin',
    pname         => 'FormattingTest',
    tag           => 'interesting',
    revision_id   => '20060908130401',
    attachment_id => 'formattingtest:20060908130402-10-23746',
);

sub main {
    while ( my ( $method, $spec ) = each %uris ) {
        while ( my ( $perm, $locations ) = each %$spec ) {
            check_403(
                $method, Socialtext::Permission->new( name => $perm ), $_
            ) for @$locations;
        }
    }
}

sub check_403 {
    my ( $method, $perm, $location ) = @_;
    my $uri = "$BASE/$location";
    $uri =~ s{/:$_\b}{/$REPLACEMENTS{$_}}g for keys %REPLACEMENTS;
    grant_all_but($perm);
    test_http "$method $location" {
        >> $method $uri
        >> Content-type: text/x.socialtext-wiki

        << 403
    }
}

{
    my @all_perms = (
        ST_READ_PERM, ST_EDIT_PERM, ST_ATTACHMENTS_PERM, ST_COMMENT_PERM,
        ST_DELETE_PERM, ST_EMAIL_IN_PERM, ST_EMAIL_OUT_PERM,
        ST_EDIT_CONTROLS_PERM, ST_REQUEST_INVITE_PERM,
        ST_ADMIN_WORKSPACE_PERM
    );
    my $user
        = Socialtext::User->new( email_address => $Test::HTTP::BasicUsername )
        or die;
    my $ws = Socialtext::Workspace->new( name => $REPLACEMENTS{ws} ) or die;
    my $uwr = Socialtext::UserWorkspaceRole->new(
        user_id      => $user->user_id,
        workspace_id => $ws->workspace_id,
    )
    or die;
    my $role = Socialtext::Role->new( role_id => $uwr->role_id );

    sub grant_all_but {
        my ( $perm ) = @_;
        $ws->permissions->add(    permission => $_,    role => $role )
            for @all_perms;
        $ws->permissions->remove( permission => $perm, role => $role );
    }
}

main();
