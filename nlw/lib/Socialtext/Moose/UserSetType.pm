package Socialtext::Moose::UserSetType;
# @COPYRIGHT@
use warnings;
use strict;
use Moose::Util::TypeConstraints;

# Q: why not use an "|" style type constraint here?
# A: those types of constraints force loading the named classes, which for our
# Pluggable modules can cause problems at BEGIN-time.
subtype 'UserSetObject'
    => as 'Object'
    => where {
        $_->isa('Socialtext::User') ||
        $_->isa('Socialtext::Group') ||
        $_->isa('Socialtext::Workspace') ||
        $_->isa('Socialtext::Account')
    }
    => message {
        "Object must be a user, group, workspace or account"
    };

# Duck-type a UserSet object
subtype 'UserSetIDer'
    => as 'Object'
    => where { $_->can('user_set_id') }
    => message {
        "Object must be able to return a user_set_id"
    };

no Moose::Util::TypeConstraints;
1;
__END__

=head1 NAME

Socialtext::Moose::UserSetType - Type constraints for UserSets

=head1 SYNOPSIS

  use Moose;
  use Socialtext::Moose::UserSetType;
  has 'owner' => (is => 'ro', isa => 'UserSetObject');

=head1 DESCRIPTION

Various user-set related type constraints.

=head1 TYPE CONSTRAINTS

=over 4

=item UserSetObject

A subtype of Object, one of the four user-set entities (user, group, workspace or account).

=item UserSetIDer

Any object that can do C<user_set_id>.

=back

=cut
