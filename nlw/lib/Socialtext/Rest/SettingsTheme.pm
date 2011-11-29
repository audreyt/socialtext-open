package Socialtext::Rest::SettingsTheme;
use Moose;
use Socialtext::Theme;
use Socialtext::HTTP qw(:codes);
use Socialtext::Prefs::System;
use Socialtext::Upload;
use Socialtext::JSON qw(encode_json decode_json);
use Socialtext::Image;
use namespace::clean -except => 'meta';

use constant AccountLogoSpec => Socialtext::Image::spec_resize_get('account');

extends 'Socialtext::Rest::Entity';

has 'upload' => (is=>'ro', isa=>'Maybe[Socialtext::Upload]', lazy_build=>1);
has 'prefs' => (is=>'ro', isa=>'Object', lazy_build=>1);

sub _build_upload {
    my $self = shift;

    return unless $self->filename;

    my $img_name = $self->filename .'_image_id';
    my $prefs = $self->prefs->all_prefs;

    my $id = $prefs->{theme}{$img_name};
    return unless $id;

    return Socialtext::Upload->Get(attachment_id=>$id);
}

sub _build_prefs {
    my $self = shift;
    return Socialtext::Prefs::System->new();
}

sub if_valid_request {
    my $self = shift;
    my $rest = shift;
    my $coderef = shift;

    return $self->not_authorized()
        unless $self->rest->user->is_technical_admin();

    return $coderef->();
}

sub GET_json {
    my $self = shift;
    my $rest = shift;

    return $self->if_valid_request($rest => sub {
        my $prefs = $self->prefs->all_prefs;

        $rest->header(-type=>'application/json');
        return encode_json($prefs->{theme});
    });
}

sub PUT_theme {
    my $self = shift;
    my $rest = shift;

    return $self->if_valid_request($rest => sub {
        my $user = $self->rest->user;
        my $prefs = $self->prefs;
        my $current = $prefs->all_prefs->{theme};

        my $updates = eval { decode_json($rest->getContent()) };
        unless ($updates && Socialtext::Theme->ValidSettings($updates)) {
            $rest->header(-status => HTTP_400_Bad_Request);
            return;
        }

        for my $key (@Socialtext::Theme::UPLOADS) {
            $key = $key . "_id";
            my $value = $updates->{$key};
            next unless $value;

            my $upload = Socialtext::Upload->Get(attachment_id=>$value);
            $upload->make_permanent(actor=>$user)
                if $upload->is_temporary();
        }
        
        my $settings = {%$current, %$updates};
        $prefs->save({theme=>$settings});

        $rest->header(-type => 'text/plain', -status => HTTP_204_No_Content);
    });
}

sub GET_image {
    my $self = shift;
    my $rest = shift;

    return $self->if_valid_request($rest => sub {
        my $image = $self->upload;
        return $self->no_resource('image') unless $image;

        my $image_uri = $image->uncached_protected_uri; 
        my $content_length;
        if ($self->filename eq 'logo' and not $rest->query->param('size')) {
            $image->ensure_scaled(spec => AccountLogoSpec);
            $image_uri .= "." . AccountLogoSpec;
        }
        else {
            $image->ensure_stored();
            $content_length = $image->content_length;
        }

        return $self->serve_file(
            $rest, $image, $image_uri, $content_length);
    });
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::SettingsTheme - Handler for Global Theme ReST calls

=head1 SYNOPSIS

    GET /data/settings/theme
    PUT /data/settings/theme
    GET /data/settings/theme/images/:filename

=head1 DESCRIPTION

View and manipulate Global Theme settings.

=cut
