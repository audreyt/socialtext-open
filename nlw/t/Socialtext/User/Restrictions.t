#!perl

use strict;
use warnings;
use Guard qw(scope_guard);
use List::MoreUtils qw(any);
use Test::Socialtext tests => 45;
use Test::Socialtext::User;
use Socialtext::Date;
use Socialtext::User::Restrictions;

fixtures(qw( db ));

###############################################################################
# TEST: Create new restriction
create_new_restriction: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user       = create_test_user();
    my $user_id    = $user->user_id;
    my $type       = 'password_change';
    my $token      = 'abc123';
    my $expires_at = Socialtext::Date->now;

    my $restriction = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => $type,
        token            => $token,
        expires_at       => $expires_at,
    } );
    scope_guard { $restriction && $restriction->clear };

    isa_ok $restriction, 'Socialtext::User::Restrictions::password_change';
    is $restriction->user_id,          $user_id,    '... check user';
    is $restriction->restriction_type, $type,       '... check type';
    is $restriction->token,            $token,      '... check token';
    is $restriction->expires_at,       $expires_at, '... check expiration';
}

###############################################################################
# TEST: Create auto-fills "token" if not provided
create_autofill_token: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user       = create_test_user();
    my $user_id    = $user->user_id;
    my $type       = 'password_change';
    my $expires_at = Socialtext::Date->now;

    my $restriction = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => $type,
        expires_at       => $expires_at,
    } );
    scope_guard { $restriction && $restriction->clear };

    isa_ok $restriction, 'Socialtext::User::Restrictions::password_change';
    is $restriction->user_id,          $user_id,    '... check user';
    is $restriction->restriction_type, $type,       '... check type';
    is $restriction->expires_at,       $expires_at, '... check expiration';
    ok $restriction->token, '... token auto-filled during creation';
}

###############################################################################
# TEST: Auto-created "token"s are unique
tokens_are_unique: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user    = create_test_user();
    my $user_id = $user->user_id;

    my $one = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => 'password_change',
    } );
    scope_guard { $one && $one->clear };

    my $two = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => 'email_confirmation',
    } );
    scope_guard { $two && $two->clear };

    isnt $one->token, $two->token, 'Auto-created tokens are unique';
}

###############################################################################
# TEST: Create auto-fills "expires_at" if not provided
create_autofill_expiration: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user       = create_test_user();
    my $user_id    = $user->user_id;
    my $type       = 'password_change';
    my $token      = 'abc123';

    my $restriction = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => $type,
        token            => $token,
    } );
    scope_guard { $restriction && $restriction->clear };

    isa_ok $restriction, 'Socialtext::User::Restrictions::password_change';
    is $restriction->user_id,          $user_id,    '... check user';
    is $restriction->restriction_type, $type,       '... check type';
    is $restriction->token,            $token,      '... check token';
    ok $restriction->expires_at, '... expiration auto-filled during creation';
}

###############################################################################
# TEST: Can't create two restrictions of same type for same User
unique_by_user_plus_type: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user       = create_test_user();
    my $user_id    = $user->user_id;
    my $type       = 'password_change';

    my $restriction = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => $type,
    } );
    scope_guard { $restriction && $restriction->clear };
    isa_ok $restriction, 'Socialtext::User::Restrictions::password_change';

    eval {
        Socialtext::User::Restrictions->Create( {
            user_id          => $user_id,
            restriction_type => $type,
        } );
    };
    like $@, qr/can't create a duplicate/i, '... no duplicate restrictions';
}

###############################################################################
# TEST: Retrieve restriction, by primary key
get_restriction_from_db: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user       = create_test_user();
    my $user_id    = $user->user_id;
    my $type       = 'password_change';
    my $token      = 'abc123';
    my $expires_at = Socialtext::Date->now;

    my $restriction = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => $type,
        token            => $token,
        expires_at       => $expires_at,
    } );
    scope_guard { $restriction && $restriction->clear };

    my $retrieved = Socialtext::User::Restrictions->Get( {
        user_id          => $user_id,
        restriction_type => $type,
    } );
    ok $retrieved, 'Retrieved restriction by user+restriction type';
    is_deeply $retrieved, $restriction, '... the restriction we created';
}

###############################################################################
# TEST: Retrieve restriction by token
retrieve_by_token: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user = create_test_user();
    my $user_id    = $user->user_id;
    my $type       = 'password_change';
    my $token      = 'abc123';
    my $expires_at = Socialtext::Date->now;

    my $restriction = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => $type,
        token            => $token,
        expires_at       => $expires_at,
    } );
    scope_guard { $restriction && $restriction->clear };

    my $retrieved = Socialtext::User::Restrictions->Get( {
        token => $token,
    } );
    ok $retrieved, 'Retrieved restriction by token';
    is_deeply $retrieved, $restriction, '... the restriction we created';
}

###############################################################################
# TEST: Get all restrictions for a given User, by User object
all_for_user_by_object: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user    = create_test_user();
    my $user_id = $user->user_id;

    # Create some restrictions for the User.
    my $one = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => 'password_change',
    } );
    scope_guard { $one && $one->clear };

    my $two = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => 'email_confirmation',
    } );
    scope_guard { $two && $two->clear };

    # Get all of the restrictions we know about for the User
    my $cursor = Socialtext::User::Restrictions->AllForUser($user);
    isa_ok $cursor, 'Socialtext::MultiCursor';

    my @restrictions = $cursor->all;
    is @restrictions, 2, '... found restrictions for User';

    my @not_mine = grep { $_->user_id != $user_id } @restrictions;
    ok !@not_mine, '... all of which are for our User';
}

###############################################################################
# TEST: Get all restrictions for a given User, by User Id
all_for_user_by_user_id: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user    = create_test_user();
    my $user_id = $user->user_id;

    # Create some restrictions for the User.
    my $one = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => 'password_change',
    } );
    scope_guard { $one && $one->clear };

    my $two = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => 'email_confirmation',
    } );
    scope_guard { $two && $two->clear };

    # Get all of the restrictions we know about for the User
    my $cursor = Socialtext::User::Restrictions->AllForUser($user_id);
    isa_ok $cursor, 'Socialtext::MultiCursor';

    my @restrictions = $cursor->all;
    is @restrictions, 2, '... found restrictions for User';

    my @not_mine = grep { $_->user_id != $user_id } @restrictions;
    ok !@not_mine, '... all of which are for our User';
}

###############################################################################
# TEST: Update existing restriction
update_restriction: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user       = create_test_user();
    my $user_id    = $user->user_id;
    my $type       = 'password_change';
    my $token      = 'abc123';
    my $expires_at = Socialtext::Date->now;

    my $restriction = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => $type,
        token            => $token,
        expires_at       => $expires_at,
    } );
    scope_guard { $restriction && $restriction->clear };

    my $new_token   = 'updated token';
    my $new_expires = Socialtext::Date->now->add(days => 1);
    Socialtext::User::Restrictions->Update($restriction, {
        token      => $new_token,
        expires_at => $new_expires,
    } );

    is $restriction->token, $new_token, 'Token updated';
    is $restriction->expires_at, $new_expires, 'Expiration updated';
}

###############################################################################
# TEST: Cannot update "user_id"
cannot_update_user_id: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user       = create_test_user();
    my $user_id    = $user->user_id;
    my $type       = 'password_change';
    my $token      = 'abc123';
    my $expires_at = Socialtext::Date->now;

    my $restriction = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => $type,
        token            => $token,
        expires_at       => $expires_at,
    } );
    scope_guard { $restriction && $restriction->clear };

    my $new_user    = create_test_user();
    my $new_user_id = $new_user->user_id;
    Socialtext::User::Restrictions->Update($restriction, {
        user_id => $new_user_id,
    } );

    is $restriction->user_id, $user_id, 'User Id NOT updatable';
}

###############################################################################
# TEST: Cannot update "restriction_type"
cannot_update_user_restriction_type: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user       = create_test_user();
    my $user_id    = $user->user_id;
    my $type       = 'password_change';
    my $token      = 'abc123';
    my $expires_at = Socialtext::Date->now;

    my $restriction = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => $type,
        token            => $token,
        expires_at       => $expires_at,
    } );
    scope_guard { $restriction && $restriction->clear };

    my $new_type = 'email_confirmation';
    Socialtext::User::Restrictions->Update($restriction, {
        restriction_type => $new_type,
    } );

    is $restriction->restriction_type, $type, 'Restriction type NOT updatable';
}

###############################################################################
# TEST: Delete restriction
delete_restriction: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user    = create_test_user();
    my $user_id = $user->user_id;
    my $type    = 'password_change';

    my $restriction = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => $type,
    } );

    my $retrieved = Socialtext::User::Restrictions->Get( {
        user_id          => $user_id,
        restriction_type => $type,
    } );
    ok $retrieved, 'Found restriction in the DB';

    my $rc = Socialtext::User::Restrictions->Delete($restriction);
    ok $rc, '... which was then deleted';

    $retrieved = Socialtext::User::Restrictions->Get( {
        user_id          => $user_id,
        restriction_type => $type,
    } );
    ok !$retrieved, '... and which then cannot be found in the DB';
}

###############################################################################
# TEST: Delete *just one* restriction
delete_just_one_restriction: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user    = create_test_user();
    my $user_id = $user->user_id;

    my $one = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => 'password_change',
    } );
    scope_guard { $one && $one->clear };

    my $two = Socialtext::User::Restrictions->Create( {
        user_id          => $user_id,
        restriction_type => 'email_confirmation',
    } );
    scope_guard { $two && $two->clear };

    my $rc = Socialtext::User::Restrictions->Delete($one);
    ok $rc, 'Delete one of the restrictions on a User';

    my $cursor = Socialtext::User::Restrictions->AllForUser($user);
    isa_ok $cursor, 'Socialtext::MultiCursor';

    my @restrictions = $cursor->all;
    is @restrictions, 1, '... one restriction left';

    is $restrictions[0]->restriction_type, $two->restriction_type,
        '... the one we did not delete';
}

###############################################################################
# TEST: Create/Replace restriction
create_or_replace: {
    my $guard = Test::Socialtext::User->snapshot;

    my $user       = create_test_user();
    my $user_id    = $user->user_id;
    my $type       = 'password_change';
    my $expires_at = Socialtext::Date->now;

    # Create an initial restriction
    my $restriction = Socialtext::User::Restrictions->CreateOrReplace( {
        user_id          => $user_id,
        restriction_type => $type,
        expires_at       => $expires_at,
    } );
    scope_guard { $restriction && $restriction->clear };
    isa_ok $restriction, 'Socialtext::User::Restrictions::password_change';

    # Replace with a new restriction
    my $new_expires = Socialtext::Date->now->add(days => 1);
    my $updated = Socialtext::User::Restrictions->CreateOrReplace( {
        user_id          => $user_id,
        restriction_type => $type,
        expires_at       => $new_expires,
    } );
    scope_guard { $updated && $updated->clear };
    isa_ok $updated, 'Socialtext::User::Restrictions::password_change';

    # Once replaced, we're RE-USING the existing token.
    is $updated->user_id, $restriction->user_id, '... matching: user id';
    is $updated->restriction_type, $restriction->restriction_type,
        '... matching: type';
    is $updated->token, $restriction->token, '... matching: token';
    is $updated->expires_at, $new_expires, '... updated expiry';
}
