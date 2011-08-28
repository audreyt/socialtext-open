package Socialtext::GroupInvitation;
# @COPYRIGHT@
use Moose;
use Socialtext::URI;
use Socialtext::l10n qw(system_locale loc);
use namespace::clean -except => 'meta';

extends 'Socialtext::Invitation';

our $VERSION = '0.01';

has 'group' => (
    is       => 'ro', isa => 'Socialtext::Group',
    required => 1,
);

sub object { shift->group }
sub id_hash { return (group_id => shift->group->group_id) }

sub _name {
    my $self = shift;
    return $self->group->driver_group_name;
}

sub _subject {
    my $self = shift;
    my $name = $self->group->driver_group_name;
    loc("invite.group=name", $name);
}

sub _template_type { 'group' }

sub _template_args {
    my $self = shift;
    return (
        group_name => $self->group->driver_group_name,
        group_uri  => Socialtext::URI::uri(path => '/st/group/'.$self->group->group_id),
        profile_uri_base => Socialtext::URI::uri(path => '/st/profile/'),
    );
}

__PACKAGE__->meta->make_immutable;
1;

=head1 NAME

Socialtext::GroupInvitation - Send and invitation email when a user is added
to a group

=head1 DESCRIPTION

C<Socialtext::GroupInvitation> provides methods for sending a User an
invitationemail when he or she is added to a group.

=head1 SYNOPSIS

    use Socialtext::GroupInvitation;
    my $invitation = Socialtext::GroupInvitation->new(
        group      => $group,
        from_user  => $inviting_user,
        extra_text => 'Some extra text included in the email',
    );
    $invitation->invite_notify( $invited_user );

=head1 AUTHOR

Socialtext, Inc.,  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc.,  All Rights Reserved.

=cut
