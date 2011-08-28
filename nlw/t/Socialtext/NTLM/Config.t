#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use YAML qw();
use File::Slurp qw(write_file);
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 14;

use_ok( 'Socialtext::NTLM::Config' );

###############################################################################
### TEST DATA
###############################################################################
our $yaml = <<EOY;
domain: SOCIALTEXT
primary: PRIMARY_DC
backup:
  - BACKUP_DC_ONE
  - BACKUP_DC_TWO
EOY

my $more_yaml = <<EOY;
domain: EXAMPLE
primary: EX_PRIMARY_DC
backup:
  - EX_BACKUP_DC_ONE
  - EX_BACKUP_DC_TWO
EOY

###############################################################################
# Check for required fields on instantiation; domain, primary
check_required_fields: {
    foreach my $required (qw( domain primary )) {
        clear_log();

        my $data = YAML::Load($yaml);
        delete $data->{$required};

        my $config = Socialtext::NTLM::Config->new(%{$data});
        ok !defined $config, "instantiation, missing '$required' parameter";

        is logged_count(), 1, '... logged right number of entries';
        next_log_like 'error', qr/missing '$required'/, "... ... missing $required";
    }
}

###############################################################################
# Instantiation with full config; should be ok.
instantiation: {
    my $data = YAML::Load($yaml);
    my $config = Socialtext::NTLM::Config->new(%{$data});
    isa_ok $config, 'Socialtext::NTLM::Config', 'valid instantiation';
}

###############################################################################
# TEST: Get name of Default NTLM Domain, when *NO* NTLM config is present.
default_ntlm_domain_no_config: {
    my $filename = Socialtext::NTLM::Config->config_filename();
    unlink $filename;

    my $domain = Socialtext::NTLM::Config->DefaultDomain();
    ok !$domain, 'NTLM Default Domain; no NTLM configuration';
}

###############################################################################
# TEST: Get name of Default NTLM Domain, when only one DC is configured.
default_ntlm_domain_single_dc: {
    my $filename = Socialtext::NTLM::Config->config_filename();
    write_file($filename, $yaml);

    my $domain = Socialtext::NTLM::Config->DefaultDomain();
    is $domain, 'SOCIALTEXT', 'NTLM Default Domain; one DC';

    unlink $filename;
}

###############################################################################
# TEST: Get name of Default NTLM Domain, when multiple DCs are configured.
default_ntlm_domain_multiple_dcs: {
    my $filename = Socialtext::NTLM::Config->config_filename();
    write_file($filename, "---\n$yaml\n---\n$more_yaml");

    my $domain = Socialtext::NTLM::Config->DefaultDomain();
    is $domain, 'SOCIALTEXT', 'NTLM Default Domain; multiple DCs';

    unlink $filename;
}

###############################################################################
# TEST: Get name of Fallback NTLM Domain, when *NO* NTLM config is present.
fallback_ntlm_domain_no_config: {
    my $filename = Socialtext::NTLM::Config->config_filename();
    unlink $filename;

    my $domain = Socialtext::NTLM::Config->FallbackDomain();
    ok !$domain, 'NTLM Fallback Domain; no NTLM configuration';
}

###############################################################################
# TEST: Get name of Fallback NTLM Domain, when only one DC is configured.
fallback_ntlm_domain_single_dc: {
    my $filename = Socialtext::NTLM::Config->config_filename();
    write_file($filename, $yaml);

    my $domain = Socialtext::NTLM::Config->FallbackDomain();
    ok !$domain, 'NTLM Fallback Domain; one DC';

    unlink $filename;
}

###############################################################################
# TEST: Get name of Fallback NTLM Domain, when multiple DCs are configured.
fallback_ntlm_domain_multiple_dcs: {
    my $filename = Socialtext::NTLM::Config->config_filename();
    write_file($filename, "---\n$yaml\n---\n$more_yaml");

    my $domain = Socialtext::NTLM::Config->FallbackDomain();
    is $domain, 'EXAMPLE', 'NTLM Fallback Domain; multiple DCs';

    unlink $filename;
}
