package Socialtext::Job::PersonReIndex;
# @COPYRIGHT@
use Moose;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job::PersonIndex';
with 'Socialtext::ReIndexJob';

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::PersonReIndex - An alias for Socialtext::Job::PersonIndex

=head1 SYNOPSIS

    use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::PersonReIndex => { %args }
    );

=head1 DESCRIPTION

Similar to Socialtext::Job::PersonIndex. In the special case where we need to
know when we're RE-indexing, eg, when pushing an update to our DB/search
engine layout, PersonReIndex should be used.

=cut
