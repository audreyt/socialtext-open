#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::User;
use Socialtext::JobCreator;
use Socialtext::SQL qw/sql_execute/;
use Socialtext::Migration::Utils qw/ensure_socialtext_schema/;
use Socialtext::Account;

my $deleted_account = Socialtext::Account->Deleted;

my $sth = sql_execute(<<EOT, $deleted_account->account_id);
SELECT user_id
FROM users
JOIN "UserMetadata" USING (user_id)
WHERE is_profile_hidden = 'false'
  AND primary_account_id <> ?;
EOT

my $i = 0;
while (my $row = $sth->fetchrow_arrayref) {
    my $user = Socialtext::User->new(user_id => $row->[0]);
    Socialtext::JobCreator->index_person($user, priority => 60);
    $i++;
}

print "Added $i PersonIndex jobs\n";
exit 0;

