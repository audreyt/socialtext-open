package Socialtext::Rest::Themes;
use Moose;
use Socialtext::Theme;
use Socialtext::JSON qw(encode_json);
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Collection';

has 'obj' => (is => 'ro', isa => 'Maybe[Socialtext::Theme]', lazy_build => 1);
has 'upload' => (is=>'ro', isa=>'Maybe[Socialtext::Upload]', lazy_build=>1);

sub _build_obj {
    my $self = shift;

    my $theme;
    $theme = Socialtext::Theme->Load(theme_id => $self->theme)
        if $self->theme =~ /^\d+$/;

    $theme ||= Socialtext::Theme->Load(name => $self->theme);

    return $theme;
}

sub _build_upload {
    my $self = shift;

    return unless $self->filename;

    my $img_name = $self->filename .'_image_id';
    my $id = eval { $self->obj->$img_name };
    return unless $id;

    return Socialtext::Upload->Get(attachment_id=>$id);
}

sub GET_all {
    my $self = shift;
    my $rest = shift;

    return $self->not_authorized() if $self->rest->user->is_guest;

    my $hashes = [ map { $_->as_hash } @{Socialtext::Theme->All()} ];

    $rest->header(-type => 'application/json');
    return encode_json($hashes);
}

sub GET_json {
    my $self = shift;
    my $rest = shift;

    return $self->not_authorized() if $self->rest->user->is_guest;
    my $theme = $self->obj;

    if ($theme) {
        $rest->header(-type => 'application/json');
        return encode_json($theme->as_hash);
    }
    else {
        return $self->no_resource('theme');
    }
}

sub GET_image {
    my $self = shift;
    my $rest = shift;

    return $self->not_authorized() if $self->rest->user->is_guest;

    my $image = $self->upload;
    return $self->no_resource('image') unless $image;

    $image->ensure_stored();

    $self->serve_file(
        $rest, $image, $image->uncached_protected_uri, $image->content_length
    );
    return;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::Themes - Handler for viewing installed Themes

=head1 SYNOPSIS

    GET /data/theme
    GET /data/theme/images/:filename

=head1 DESCRIPTION

View installed themes.

=cut
