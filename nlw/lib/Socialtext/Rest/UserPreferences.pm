package Socialtext::Rest::UserPreferences;
use Moose;
use Socialtext::JSON qw/encode_json decode_json/;
use Socialtext::HTTP qw/:codes/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Entity';

has 'user' => (is => 'ro', isa => 'Maybe[Socialtext::User]', lazy_build => 1);
sub _build_user {
    my $self = shift;
    my $user = eval { Socialtext::User->Resolve($self->username) };
    return $user;
}

has 'prefs' => (is => 'ro', isa => 'HashRef', lazy_build => 1);
sub _build_prefs {
    my $self = shift;
    return $self->hub->preferences->Global_user_prefs($self->user) || {};
}

sub if_authorized {
    my $self = shift;
    my $viewer = shift;
    my $code = shift;

    return $self->no_resource('User') unless $self->user;

    my $is_me = $viewer->user_id == $self->user->user_id;
    return $self->not_authorized() unless $is_me || $viewer->is_business_admin;

    return $code->();
}

sub GET_json {
    my ($self,$rest) = @_;
    my $viewer = $rest->user;
    my $user = $self->user;

    return $self->if_authorized($viewer => sub {
        $rest->header(-type=>'application/json');
        return encode_json($self->prefs);
    });
}

sub POST_json {
    my ($self,$rest) = @_;
    my $viewer = $rest->user;
    my $user = $self->user;

    return $self->if_authorized($viewer => sub {
        my $stored_prefs = $self->prefs;

        my $new_prefs = eval { decode_json($self->rest->getContent()) };
        if (!$new_prefs or ref($new_prefs) ne 'HASH') {
            $rest->header( -status => HTTP_400_Bad_Request );
            return 'Content should be a JSON hash.';
        }

        map { $stored_prefs->{$_} = $new_prefs->{$_} } keys %$new_prefs;
        $self->hub->preferences->Store_global_user_prefs(
            $self->user => $stored_prefs);

        $rest->header(-status=>HTTP_201_Created);
        return '';
    });
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::UserPreferences - Handler for Global User Preferences

=head1 SYNOPSIS

    GET /data/users/:username/preferences
    POST /data/users/:username/preferences

=head1 DESCRIPTION

View and alter Global User Preferences

=cut
