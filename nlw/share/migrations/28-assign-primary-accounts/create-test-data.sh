#!/bin/bash

# This is a script to help with testing this migration.  It is not run by the
# migration process.


# use 'check' to dump out the current user/account mapping 
if [ "$1" = "check" ]; then
    psql -c '
SELECT username, name 
    FROM "User" u JOIN "UserMetadata" um ON (u.user_id = um.user_id)
         LEFT JOIN "Account" a ON (um.primary_account_id = a.account_id)
    '
    exit;
fi


# use 'quick' to avoid creating all the users and to just un-assign the
# primary_account_id
if [ "$1" != "quick" ]; then
    # foo is only a member of a private workspace
    # foo@example.com should end up in an account called 'Foo'
    st-admin delete-workspace --no-export --workspace foo 2> /dev/null
    st-admin create-workspace --name foo --title Foo --account Unknown
    st-admin set-permissions -w foo -p member-only
    st-admin create-user --email foo@example.com --password password 2> /dev/null
    st-admin add-member --email foo@example.com -w foo 2> /dev/null 


    # bar is only a member of a public workspace
    # bar@example.com should end up in an account called 'Public'
    st-admin delete-workspace --no-export --workspace bar 2> /dev/null
    st-admin create-workspace --name bar --title bar --account Unknown
    st-admin set-permissions -w bar -p public
    st-admin create-user --email bar@example.com --password password 2> /dev/null
    st-admin add-member --email bar@example.com -w bar 2> /dev/null 

    # quux is a member of a private workspace (foo), and a system workspace (admin)
    # quux@example.com should end up in an account called 'Foo'
    st-admin create-user --email quux@example.com --password password 2> /dev/null
    st-admin add-member --email quux@example.com -w foo 2> /dev/null 
    st-admin add-member --email quux@example.com -w admin 2> /dev/null 

    # dill is a member of a private workspace, and a non-default system workspace
    # dill@example.com should end up in an account called 'Burning Man'
    st-admin create-account --name 'Dirty Hippies'
    st-admin create-account --name 'Burning Man'
    st-admin create-user --email dill@example.com --password password 2> /dev/null
    st-admin delete-workspace --no-export --workspace hippy 2> /dev/null
    st-admin create-workspace --name hippy --title hippy -a 'Dirty Hippies'
    st-admin delete-workspace --no-export --workspace burn 2> /dev/null
    st-admin create-workspace --name burn --title burn -a 'Burning Man'
    st-admin add-member --email dill@example.com -w hippy 2> /dev/null 
    st-admin add-member --email dill@example.com -w burn 2> /dev/null 


    # confused is a member of 2 accounts, 1 of which is a paying account
    # confused@example.com should end up in an account called 'Republicans'
    st-admin create-account --name 'Republicans'
    st-admin create-user --email confused@example.com --password password 2> /dev/null
    st-admin delete-workspace --no-export --workspace money 2> /dev/null
    st-admin create-workspace --name money --title money --account 'Republicans'
    st-admin add-member --email confused@example.com -w money 2> /dev/null 
    st-admin add-member --email confused@example.com -w burn 2> /dev/null 

    # social is a member of many accounts, none of them paying
    # social should end up in 'General'
    st-admin create-account --name 'Jugglers'
    st-admin delete-workspace --no-export --workspace balls 2> /dev/null
    st-admin create-workspace --name balls --title balls --account 'Jugglers'
    st-admin create-user --email social@example.com --password password 2> /dev/null
    st-admin add-member --email social@example.com -w burn 2> /dev/null 
    st-admin add-member --email social@example.com -w hippy 2> /dev/null 
    st-admin add-member --email social@example.com -w balls 2> /dev/null 

    # other is a member of 2 paying accounts
    # other should end up in the 'Ambiguous' account
    st-admin create-account --name 'Othercrats'
    st-admin create-user -e other@example.com -p password 2> /dev/null

    st-admin delete-workspace --no-export -w other 2> /dev/null
    st-admin create-workspace -n other -t other -a 'Othercrats'

    st-admin add-member -e other@example.com -w other 2> /dev/null
    st-admin add-member -e other@example.com -w money 2> /dev/null

    # Set up the migration config file
    cat <<EOT > ~/.nlw/etc/socialtext/account-migration.yaml
---
email_to_account_mapping:
  Socialtext:
   - %@socialtext.com
system_accounts:
  - Dirty Hippies
paying_accounts:
  - Republicans
  - Othercrats
EOT
fi

# Clear all existing primary accounts
psql -c 'UPDATE "UserMetadata" SET primary_account_id = NULL'

