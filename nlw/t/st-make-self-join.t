#!perl
# @COPYRIGHT@

use strict;
use warnings;
use IPC::Run;

use Test::Socialtext tests => 11;
use Test::Socialtext::CLIUtils qw/expect_failure expect_success/;

use Socialtext::Permission qw/ST_READ_PERM ST_EDIT_PERM 
                              ST_ATTACHMENTS_PERM
                              ST_COMMENT_PERM
                              ST_DELETE_PERM
                              ST_EMAIL_IN_PERM
                              ST_EMAIL_OUT_PERM
                              ST_EDIT_CONTROLS_PERM 
                              ST_SELF_JOIN_PERM/;

fixtures( 'db' );


test_it: {
    my $now = time;

    my $acctpri = Socialtext::Account->create( name => "msjpacc$now");
    my $acctsec = Socialtext::Account->create( name => "msjsacc$now");

    
    my $priuser = Socialtext::User->create(
        username => "msjprimary$now",
        email_address => "msjprimary$now\@example.com",
        password => 'password',
        primary_account_id => $acctpri->account_id
    );


    my $secuser = Socialtext::User->create(
        username => "msjsecondary$now",
        email_address => "msjsecondary$now\@example.com",
        password => 'password',
        primary_account_id => $acctsec->account_id
    );

    my $workspacepri = Socialtext::Workspace->create(
        name => "msjworkspace$now",
        title => "msjworkspace$now",
        account_id => $acctpri->account_id
    );

    $workspacepri->permissions->set(
        set_name => 'public-authenticate-to-edit',
        allow_deprecated => 1,
    );

    my @command = qw( bin/st-make-self-join --add );
    push(@command,  $acctpri->name );


    my ($in, $out, $err);
    IPC::Run::run( \@command, \$in, \$out, \$err );
    my $return = $? >> 8;
    is( $return, 0, 'command returns proper exit code with simple message' );
    is( $err, '', 'no stderr output with simple message' );

    my $match = "Changing ".$workspacepri->name;
    like( $out, qr/$match/, "Changing right workspace output");
    like( $out, qr/Adding users/);

    my $workspacecompare = Socialtext::Workspace->new( name=> $workspacepri->name);
    
    ok($workspacecompare->permissions->role_can(
            role => Socialtext::Role->Guest(),
            permission => ST_SELF_JOIN_PERM), 
        "self_join permission set for workspace"
    );

    ok(!$workspacecompare->permissions->role_can(
            role => Socialtext::Role->Guest(),
            permission => ST_EDIT_CONTROLS_PERM), 
        "edit_controls permission cleared for workspace"
    );

    ok($workspacecompare->has_user($priuser), "self-join workspaces have pri-account users");

    ok(!$workspacecompare->has_user($secuser), "self-join workspaces do not have other account users");

    IPC::Run::run( \@command, \$in, \$out, \$err );
    $return = $? >> 8;
    is( $return, 0, 'command returns proper exit code with simple message' );
    is( $err, '', 'no stderr output with simple message' );
    is( $out, '', 'rerunning script produces no output' );

}
