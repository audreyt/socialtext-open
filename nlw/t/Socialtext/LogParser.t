#!perl
#@COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext;
use Socialtext::LogParser;

my %tests = (

    # There was a bug with single digit days in the past
    'Nov  9 06:41:14 www2 nlw[4785]: [33] DISPLAY_PAGE : corp : wiki_relevance_ranking : 606 '
        => {
        date           => 'Nov  9 06:41:14',
        action         => 'DISPLAY_PAGE',
        workspace_name => 'corp',
        page_id        => 'wiki_relevance_ranking',
        user_id        => 606,
        attachment_id  => undef,
        },
    'Nov  9 06:45:05 www2 nlw[31893]: [33] EDIT_PAGE : corp : adobe_apollo : 51 ',
    {
        date           => 'Nov  9 06:45:05',
        action         => 'EDIT_PAGE',
        workspace_name => 'corp',
        page_id        => 'adobe_apollo',
        user_id        => 51,
        attachment_id  => undef,
    },
    'Nov  9 06:46:58 www2 nlw[31948]: [33] DOWNLOAD_ATTACHMENT : corp : hds_asks_about_wiki_spam_in_his_account : 11 : Outlook.jpg ',
    {
        date           => 'Nov  9 06:46:58',
        action         => 'DOWNLOAD_ATTACHMENT',
        workspace_name => 'corp',
        page_id        => 'hds_asks_about_wiki_spam_in_his_account',
        user_id        => 11,
        attachment_id  => 'Outlook.jpg',
    },
    'Nov  9 07:13:38 www2 nlw[31882]: [33] UPLOAD_ATTACHMENT : publish-discuss : uidesignsketchesoriginal : 329 : KICX1923_2.jpg ',
    {
        date           => 'Nov  9 07:13:38',
        action         => 'UPLOAD_ATTACHMENT',
        workspace_name => 'publish-discuss',
        page_id        => 'uidesignsketchesoriginal',
        user_id        => 329,
        attachment_id  => 'KICX1923_2.jpg',
    },
);

plan tests => (keys %tests) * 6;

for my $line ( sort keys %tests ) {
    my %parsed = Socialtext::LogParser->parse_log_line($line);

    for my $k ( sort keys %{ $tests{$line} } ) {
        my $string_val = $tests{$line}{$k} ? $tests{$line}{$k} : 'undef';

        is( $parsed{$k}, $tests{$line}{$k}, "$k = $string_val" );
    }
}
