#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use IPC::Run qw(run);
use mocked 'Socialtext::Log', qw(:tests);
use Socialtext::NTLM::Config;
use Test::Socialtext tests => 45;

###############################################################################
# Fixtures: base_layout
# - need the basic directory structure laid out, but that's it
fixtures(qw( base_layout ));

###############################################################################
### Command to run 'st-ntlm-config' from blib/ with our @INC.
###############################################################################
sub st_ntlm_config {
    my @args = @_;

    my ($stdin, $stdout, $stderr);
    my @cmd = ($^X, '-Ilib', 'bin/st-ntlm-config', @args);
    IPC::Run::run( \@cmd, \$stdin, \$stdout, \$stderr );

    return wantarray ? ($stdout, $stderr) : $stdout;
}

###############################################################################
# Figure out where the configuration file is being kept.
my $filename = Socialtext::NTLM::Config->config_filename();

###############################################################################
# print configuration filename
print_config_filename: {
    my $stdout = st_ntlm_config(qw( file ));
    like $stdout, qr/$filename/, 'got NTLM config filename';
}

###############################################################################
# cat configuration file, when it doesn't exist
cat_missing_config_file: {
    unlink $filename;

    my ($stdout, $stderr) = st_ntlm_config(qw( cat ));
    ok !$stdout, 'no "cat" of config file';
    like $stderr, qr/no such file/i, '... error: no such file or directory';
}

###############################################################################
# try to add configuration without --domain; should fail
add_without_domain: {
    unlink $filename;

    my ($stdout, $stderr) = st_ntlm_config(qw( set ));
    ok !$stdout, 'add was unsuccessful';
    like $stderr, qr/need to specify --domain/, '... error: need to specify --domain';
}

###############################################################################
# try to add configuration without --primary; should fail
add_without_primary: {
    unlink $filename;

    my ($stdout, $stderr) = st_ntlm_config(qw( set --domain SOCIALTEXT ));
    ok !$stdout, 'add was unsuccessful';
    like $stderr, qr/one of --primary/, '... error: need to specify --primary';
}

###############################################################################
# add configuration with --primary
add_with_primary: {
    unlink $filename;

    # add the configuration
    my ($stdout, $stderr) = st_ntlm_config(qw(
        set --domain SOCIALTEXT --primary PRIMARY
        ));
    like $stdout, qr/Adding new configuration for 'SOCIALTEXT'/, 'add was successful';
    ok !$stderr, '... and threw no errors';

    # make sure the configuration got added properly
    my $config = Socialtext::NTLM::Config->load();
    is $config->domain(), 'SOCIALTEXT', '... domain was set into config';
    is $config->primary(), 'PRIMARY', '... PDC was set into config';

    my $backups = $config->backup();
    ok !@{$backups}, '... no BDC set into config';
}

###############################################################################
# add configuration with --primary and --backup
add_with_primary_and_backup: {
    unlink $filename;

    # add the configuration
    my ($stdout, $stderr) = st_ntlm_config(qw(
        set --domain SOCIALTEXT --primary PRIMARY --backup BACKUP
        ));
    like $stdout, qr/Adding new configuration for 'SOCIALTEXT'/, 'add was successful';
    ok !$stderr, '... and threw no errors';

    # make sure the configuration got added properly
    my $config = Socialtext::NTLM::Config->load();
    is $config->domain(), 'SOCIALTEXT', '... domain was set into config';
    is $config->primary(), 'PRIMARY', '... PDC was set into config';

    my $backups = $config->backup();
    is_deeply $backups, [qw(BACKUP)], '... BDC was set into config';
}

###############################################################################
# add configuration with --primary and multiple --backup
add_with_primary_and_multiple_backups: {
    unlink $filename;

    # add the configuration
    my ($stdout, $stderr) = st_ntlm_config(qw(
        set --domain SOCIALTEXT --primary PRIMARY --backup ONE --backup TWO
        ));
    like $stdout, qr/Adding new configuration for 'SOCIALTEXT'/, 'add was successful';
    ok !$stderr, '... and threw no errors';

    # make sure the configuration got added properly
    my $config = Socialtext::NTLM::Config->load();
    is $config->domain(), 'SOCIALTEXT', '... domain was set into config';
    is $config->primary(), 'PRIMARY', '... PDC was set into config';

    my $backups = $config->backup();
    is_deeply $backups, [qw(ONE TWO)], '... two BDCs were set';
}

###############################################################################
# update existing configuration, changing --primary
update_changing_primary: {
    unlink $filename;

    # save an initial configuration
    my $config = Socialtext::NTLM::Config->new(
        domain  => 'SOCIALTEXT',
        primary => 'PRIMARY',
        backup  => 'BACKUP',
    );
    Socialtext::NTLM::Config->save($config);

    # update the configuration
    my ($stdout, $stderr) = st_ntlm_config(qw(
        set --domain SOCIALTEXT --primary UPDATED
        ));
    like $stdout, qr/Updating existing configuration for 'SOCIALTEXT'/, 'update was successful';
    ok !$stderr, '... and threw no errors';

    # make sure the configuration got updated properly
    my $reloaded = Socialtext::NTLM::Config->load();
    is $reloaded->domain(), 'SOCIALTEXT', '... domain was left as-is';
    is $reloaded->primary(), 'UPDATED', '... PDC was updated';

    my $backups = $reloaded->backup();
    is_deeply $backups, [qw(BACKUP)], '... BDC was left as-is';
}

###############################################################################
# update existing configuration, changing --backup
update_changing_backup: {
    unlink $filename;

    # save an initial configuration
    my $config = Socialtext::NTLM::Config->new(
        domain  => 'SOCIALTEXT',
        primary => 'PRIMARY',
        backup  => 'BACKUP',
    );
    Socialtext::NTLM::Config->save($config);

    # update the configuration
    my ($stdout, $stderr) = st_ntlm_config(qw(
        set --domain SOCIALTEXT --backup UPDATED
        ));
    like $stdout, qr/Updating existing configuration for 'SOCIALTEXT'/, 'update was successful';
    ok !$stderr, '... and threw no errors';

    # make sure the configuration got updated properly
    my $reloaded = Socialtext::NTLM::Config->load();
    is $reloaded->domain(), 'SOCIALTEXT', '... domain was left as-is';
    is $reloaded->primary(), 'PRIMARY', '... PDC was left as-is';

    my $backups = $reloaded->backup();
    is_deeply $backups, [qw(UPDATED)], '... BDC was updated';
}

###############################################################################
# remove config without --domain; should fail
remove_without_domain: {
    unlink $filename;

    my ($stdout, $stderr) = st_ntlm_config(qw( remove ));
    ok !$stdout, 'remove was unsuccessful';
    like $stderr, qr/need to specify --domain/, '... error: need to specify --domain';
}

###############################################################################
# remove config for non-existent --domain; should fail
remove_nonexistent_domain: {
    unlink $filename;

    my ($stdout, $stderr) = st_ntlm_config(qw( remove --domain SOCIALTEXT ));
    ok !$stdout, 'remove was unsuccessful';
    like $stderr, qr/No configuration for 'SOCIALTEXT' found/, '... error: unknown domain';
}

###############################################################################
# remove config for only configured --domain
remove_only_domain: {
    unlink $filename;

    # save out some initial configuration
    my $config = Socialtext::NTLM::Config->new(
        domain  => 'SOCIALTEXT',
        primary => 'PRIMARY',
        backup  => 'BACKUP',
    );
    Socialtext::NTLM::Config->save($config);

    # remove the configuration
    my ($stdout, $stderr) = st_ntlm_config(qw(
        remove --domain SOCIALTEXT
        ));
    like $stdout, qr/Removed configuration for 'SOCIALTEXT'/, 'remove was successful';
    ok !$stderr, '... and threw no errors';

    # make sure that the config file can be loaded (it should be empty, but it
    # should be load-able without going boom)
    clear_log();
    my $reloaded = Socialtext::NTLM::Config->load();
    is logged_count(), 0, '... no errors thrown on re-loading config';
}

###############################################################################
# remove config for one of the configured --domain
remove_one_domain: {
    unlink $filename;

    # save out some initial configuration
    my $first = Socialtext::NTLM::Config->new(
        domain  => 'SOCIALTEXT',
        primary => 'PRIMARY',
        backup  => 'BACKUP',
    );
    my $second = Socialtext::NTLM::Config->new(
        domain  => 'EXAMPLE',
        primary => 'EX_PRIMARY',
        backup  => 'EX_BACKUP',
    );
    Socialtext::NTLM::Config->save($first, $second);

    # remove the configuration
    my ($stdout, $stderr) = st_ntlm_config(qw(
        remove --domain SOCIALTEXT
        ));
    like $stdout, qr/Removed configuration for 'SOCIALTEXT'/, 'remove was successful';
    ok !$stderr, '... and threw no errors';

    # verify the contents of the configuration file
    my @reloaded = Socialtext::NTLM::Config->load();
    is scalar @reloaded, 1, '... only one configuration left in file';
    is $reloaded[0]->domain(), 'EXAMPLE', '... ... EXAMPLE domain';
    is $reloaded[0]->primary(), 'EX_PRIMARY', '... ... ... with its PDC';

    my $backups = $reloaded[0]->backup();
    is_deeply $backups, [qw(EX_BACKUP)], '... ... ... with its BDC';
}
