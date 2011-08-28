#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 12;

###############################################################################
# Fixtures: clean admin
# - some of our tests expect a "clean" slate to start with, and count up the
#   number of items in the DB.
fixtures(qw( clean admin ));

my $hub = new_hub('admin');

my $singapore = join '', map { chr($_) } 26032, 21152, 22369;
my $script_path = 'index.cgi';

_get_workspace_list_for_template: {
    Socialtext::Account->Clear_Default_Account_Cache();

    my $workspacelist   = $hub->helpers->_get_workspace_list_for_template;
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

# Edit page
{
    my $simple_page_name = 'a page';
    my $simple_params    = 'action=display;page_name=a%20page;js=show_edit_div';
    my $simple_path      = "$script_path?$simple_params";

    is $hub->helpers->page_edit_params($simple_page_name), $simple_params,
      'page_edit_params - simple input';

    is $hub->helpers->page_edit_path($simple_page_name), $simple_path,
      'page_edit_path - simple';

    is $hub->helpers->page_edit_link(
        $simple_page_name,
        'Edit simple page',
        'extra' => 1,
        'more'  => 2
      ),
      '<a href="' . $simple_path . ';extra=1;more=2">Edit simple page</a>',
      'page_edit_link - simple case';

    my $mangy      = qq[$singapore \\"hello&;];
    my $mangy_path =
        'index.cgi?action=display;page_name=%E6%96%B0%E5%8A%A0%E5%9D%A1%20%5C%22hello%26%3B;js=show_edit_div';

    is $hub->helpers->page_edit_path($mangy), $mangy_path,
      'page_edit_path - with gnarly input';

    is $hub->helpers->page_edit_link( $mangy, $mangy ),
       '<a href="'
       . $mangy_path
       . qq[">$singapore \\&quot;hello&amp;;</a>],
       'page_edit_link - gnarly input';
}

# script_link
is $hub->helpers->script_link('go', action => 'brownian', extra => 1),
    qq(<a href="$script_path?;action=brownian;extra=1">go</a>),
    'script_link';

# Preference
is $hub->helpers->preference_path('flavors', 'layout' => 'ugly'),
    "$script_path?action=preferences_settings;"
      . 'preferences_class_id=flavors;layout=ugly',
    'preferences_link';

# Check for Valid e-mail domain
valid_email_domain: {
    ok $hub->helpers->valid_email_domain( 'socialtext.net' ),
        'got a valid email domain';
    ok ! $hub->helpers->valid_email_domain( 'nosuchdom@in.com' ),
        'got an invalid domain';
}
