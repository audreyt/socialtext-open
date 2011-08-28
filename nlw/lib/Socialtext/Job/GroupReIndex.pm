package Socialtext::Job::GroupReIndex;
# @COPYRIGHT@
use Moose;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job::GroupIndex';
with 'Socialtext::ReIndexJob';

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::GroupReIndex - An alias for Socialtext::Job::GroupIndex

=head1 SYNOPSIS

    use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::GroupReIndex => { %args }
    );

=head1 DESCRIPTION

Similar to Socialtext::Job::GroupIndex. In the special case where we need to
know when we're RE-indexing, eg, when pushing an update to our DB/search
engine layout, GroupReIndex should be used.

=cut
