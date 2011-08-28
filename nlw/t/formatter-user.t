#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 4;
use Test::Socialtext::User;

fixtures(qw( empty ));

###############################################################################
### TEST DATA
###############################################################################
my $bogus_email = 'humpty@dance.org';
my $legit_email = Test::Socialtext::User->test_email_address();

###############################################################################
# Email addresses of non-users should still format in to _something_.
emails_always_format_even_if_nonuser: {
    formatted_like "{user: $bogus_email}", qr(>\s*\Q$bogus_email\E\s*</span>);
}

###############################################################################
# Make sure we get a suitable full name for a normal user, and don't just
# reveal his email address.
real_users_show_full_name: {
    my $user       = Socialtext::User->new( email_address => $legit_email );
    isa_ok $user, 'Socialtext::User';

    # hold onto the User's first/last name; we'll want to reset it when we're
    # done.
    my $orig_first_name = $user->first_name();
    my $orig_last_name = $user->last_name();

    # make sure the User has a suitable first/last name
    my $first_name = 'Devin';
    my $last_name  = 'Nullington';
    $user->update_store( first_name => $first_name, last_name => $last_name );

    formatted_like "{user: $legit_email}", qr(>\Q$first_name $last_name\E</a>);

    TODO: {
        local $TODO = <<'';
We actually _do_ reveal the email address in a source comment, for wikiwyg.

        formatted_unlike "{user: $legit_email}", qr/\Q$legit_email\E/;
    }

    # reset the User's first/last name to what they were before; don't pollute
    # other unit tests
    $user->update_store( first_name => $orig_first_name, last_name => $orig_last_name );
}
