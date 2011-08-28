#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use YAML qw();
use File::Spec;
use File::Temp;
use POSIX qw(fcntl_h);
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 43;

use_ok 'Socialtext::Config::Base';

###############################################################################
### TEST CONFIGURATION CLASS AND DATA
###############################################################################
{
    package MY::Config;
    use Class::Field qw(field const);
    use base qw(Socialtext::Config::Base);
    const config_basename => 'test.yaml';
    field 'id';
    field 'name';
    sub init {
        my $self = shift;
        $self->check_required_fields(qw( id ));
    }
}

our $yaml = <<EOY;
id: 123
name: test config
EOY

###############################################################################
# Check for required fields on instantiation
check_required_fields: {
    foreach my $required (qw( id )) {
        clear_log();

        my $data = YAML::Load($yaml);
        delete $data->{$required};

        my $config = MY::Config->new(%{$data});
        ok !defined $config, "instantiation failed, missing '$required'";

        next_log_like 'error', qr/missing '$required'/,
            "... error thrown about missing '$required' field";
    }
}

###############################################################################
# Instantiation with full config; should be ok
instantiation: {
    my $data = YAML::Load($yaml);
    my $config = MY::Config->new(%{$data});
    isa_ok $config, 'MY::Config', 'valid instantiation';
}

###############################################################################
# Load from non-existent YAML file; should fail
load_nonexistent_file: {
    clear_log();

    my $config = MY::Config->load_from('t/doesnt-exist.yaml');
    ok !defined $config, 'load, missing YAML file';
    next_log_like 'error', qr/error reading config/,
        "... error thrown about reading config file";
}

###############################################################################
# Load from invalid YAML file; should fail
load_invalid_yaml: {
    # write out a YAML file with missing fields
    my $fh = File::Temp->new();
    $fh->print( "# YAML file, with invalid entry\n" );
    $fh->print( "foo: bar\n" );
    seek( $fh, 0, SEEK_SET );

    # run the test
    clear_log();

    my $config = MY::Config->load_from($fh);
    ok !defined $config, 'load, invalid YAML file';
    next_log_like 'error', qr/config missing/, "... config missing something";
    next_log_like 'error', qr/error with config/, "... error in config";
}

###############################################################################
# Load from valid YAML file
load_valid_yaml: {
    # write out a valid YAML file
    my $fh = File::Temp->new();
    $fh->print($yaml);
    seek( $fh, 0, SEEK_SET );

    # run test
    my $config = MY::Config->load_from($fh);
    isa_ok $config, 'MY::Config', 'load, valid YAML';
}

###############################################################################
# Save with missing filename; should fail
save_missing_filename: {
    my $data = YAML::Load($yaml);
    my $config = MY::Config->new(%{$data});
    isa_ok $config, 'MY::Config';
    ok !MY::Config->save_to(), 'save without filename';
}

###############################################################################
# Save with filename
save_ok: {
    my $data = YAML::Load($yaml);
    my $config = MY::Config->new(%{$data});
    isa_ok $config, 'MY::Config';

    # save the config out to disk
    my $tmpfile = File::Spec->catfile(
        File::Spec->tmpdir(),
        "$$.yaml",
    );
    ok !-e $tmpfile, '... temp file does not exist (yet)';
    my $rc = MY::Config->save_to($tmpfile, $config);
    ok $rc, '... saved config to temp file';
    ok  -e $tmpfile, '... temp file exists';

    # verify the contents of the YAML file
    my $reloaded = eval { YAML::LoadFile($tmpfile) };
    ok $reloaded, '... able to reload YAML from temp file';
    is_deeply $reloaded, $data, '... ... and it matches the original data';

    # cleanup
    unlink $tmpfile;
}

###############################################################################
# Save multiple configuration objects
save_multiple_configurations: {
    # create multiple configuration objects
    my $data = YAML::Load($yaml);

    my $first = MY::Config->new(%{$data}, id => 'one');
    isa_ok $first, 'MY::Config';

    my $second = MY::Config->new(%{$data}, id => 'two');
    isa_ok $second, 'MY::Config';

    # save the configs out to disk
    my $tmpfile = File::Spec->catfile(
        File::Spec->tmpdir(),
        "$$.yaml",
    );
    ok !-e $tmpfile, '... temp file does not exist (yet)';
    my $rc = MY::Config->save_to($tmpfile, $first, $second);
    ok $rc, '... saved configs to temp file';
    ok  -e $tmpfile, '... temp file exists';

    # verify the contents of the YAML file
    my @reloaded = eval { YAML::LoadFile($tmpfile) };
    ok @reloaded, '... able to reload YAML from temp file';
    is @reloaded, 2, '... ... and it contains two configurations';
    is_deeply $reloaded[0], $first,  '... ... ... one';
    is_deeply $reloaded[1], $second, '... ... ... two';

    # cleanup
    unlink $tmpfile;
}

###############################################################################
# Load multiple configuration objects
load_multiple_configurations: {
    # create multiple configuration objects
    my $data = YAML::Load($yaml);

    my $first = MY::Config->new(%{$data}, id => 'one');
    isa_ok $first, 'MY::Config';

    my $second = MY::Config->new(%{$data}, id => 'two');
    isa_ok $second, 'MY::Config';

    # save the configs out to disk
    my $tmpfile = File::Spec->catfile(
        File::Spec->tmpdir(),
        "$$.yaml",
    );
    ok !-e $tmpfile, '... temp file does not exist (yet)';
    my $rc = MY::Config->save_to($tmpfile, $first, $second);
    ok $rc, '... saved configs to temp file';
    ok  -e $tmpfile, '... temp file exists';

    # load the configurations back out of the YAML file
    my @reloaded = MY::Config->load_from($tmpfile);
    ok @reloaded, '... able to reload YAML from temp file';
    is @reloaded, 2, '... ... and it contains two configurations';
    is_deeply $reloaded[0], $first,  '... ... ... one';
    is_deeply $reloaded[1], $second, '... ... ... two';

    # cleanup
    unlink $tmpfile;
}

###############################################################################
# Load FIRST configuration (when multiple configs exist)
load_first_configuration: {
    # create multiple configuration objects
    my $data = YAML::Load($yaml);

    my $first = MY::Config->new(%{$data}, id => 'one');
    isa_ok $first, 'MY::Config';

    my $second = MY::Config->new(%{$data}, id => 'two');
    isa_ok $second, 'MY::Config';

    # save the configs out to disk
    my $tmpfile = File::Spec->catfile(
        File::Spec->tmpdir(),
        "$$.yaml",
    );
    ok !-e $tmpfile, '... temp file does not exist (yet)';
    my $rc = MY::Config->save_to($tmpfile, $first, $second);
    ok $rc, '... saved configs to temp file';
    ok  -e $tmpfile, '... temp file exists';

    # load the FIRST configuration back out of the YAML file
    my $reloaded = MY::Config->load_from($tmpfile);
    ok $reloaded, '... able to reload YAML from temp file';
    is_deeply $reloaded, $first,  '... ... and its the first config';

    # cleanup
    unlink $tmpfile;
}
