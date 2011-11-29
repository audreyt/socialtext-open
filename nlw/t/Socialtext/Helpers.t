#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 6;

###############################################################################
# Fixtures: clean admin
# - some of our tests expect a "clean" slate to start with, and count up the
#   number of items in the DB.
fixtures(qw( clean admin ));

my $hub = new_hub('admin');

my $singapore = join '', map { chr($_) } 26032, 21152, 22369;
my $script_path = 'index.cgi';

workspaces_list_for_template: {
    Socialtext::Account->Clear_Default_Account_Cache();

    my $workspacelist   = $hub->helpers->user_info->{workspaces};
    my $acct_default    = Socialtext::Account->Default();
    my $acct_socialtext = Socialtext::Account->Socialtext();
     
    is scalar(@$workspacelist), 2, 'length of workspace list';
    is_deeply $workspacelist,
        [
            {
                label   => 'Admin Wiki',
                account => $acct_default->name(),
                name    => 'admin',
                id      => 2
            },
            {
                label   => 'Socialtext Documentation',
                account => $acct_socialtext->name(),
                name    => 'help-en',
                id      => 1
            },
        ],
        "expected workspace list returned";
}

# Display page
{
    is
        $hub->helpers->page_display_link('quick_start'),
        qq(<a href="$script_path?quick_start">Quick Start</a>),
        'page_display_link';
}

# script_link
is $hub->helpers->script_link('go', action => 'brownian', extra => 1),
    qq(<a href="$script_path?;action=brownian;extra=1">go</a>),
    'script_link';

# Check for Valid e-mail domain
valid_email_domain: {
    ok $hub->helpers->valid_email_domain( 'socialtext.net' ),
        'got a valid email domain';
    ok ! $hub->helpers->valid_email_domain( 'nosuchdom@in.com' ),
        'got an invalid domain';
}
