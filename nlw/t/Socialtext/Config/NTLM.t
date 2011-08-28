#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use File::Slurp qw(write_file);
use Test::Socialtext tests => 2;
use Test::Differences;

fixtures(qw( base_config ));

BEGIN {
    use_ok 'Socialtext::NTLM::Config';
}

###############################################################################
# Test data
my $NTLM_YAML =<<'EOY';
---
domain: SOCIALTEXT
primary: PRIMARY_DC
backup:
  - BACKUP_DC_ONE
  - BACKUP_DC_TWO
---
domain: EXAMPLE
primary: EX_PRIMARY_DC
backup:
  - EX_BACKUP_DC_ONE
  - EX_BACKUP_DC_TWO
EOY

###############################################################################
# TEST: load config
ntlm_load_config: {
    # Save our NTLM configuration
    my $cfg_file = Socialtext::NTLM::Config->config_filename();
    write_file($cfg_file, $NTLM_YAML);

    my $o = {}; # no methods called on it, so no big deal.

    # Load up the config into the Authen handler
    Socialtext::NTLM::Config->ConfigureApacheAuthenNTLM($o);

    # VERIFY: our NTLM config got loaded into the right places
    my %expected = (
        splitdomainprefix => 1,
        smbpdc            => {
            socialtext => 'PRIMARY_DC',
            example    => 'EX_PRIMARY_DC',
        },
        smbbdc => {
            socialtext => 'BACKUP_DC_ONE BACKUP_DC_TWO',
            example    => 'EX_BACKUP_DC_ONE EX_BACKUP_DC_TWO',
        },
        defaultdomain  => 'SOCIALTEXT',
        fallbackdomain => 'EXAMPLE',
        handshake_timeout => 2,
    );

    eq_or_diff $o, \%expected, 'NTLM config loaded correctly';

    # CLEANUP
    unlink $cfg_file;
}
