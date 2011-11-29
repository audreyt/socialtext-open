package Socialtext::Rest::AccountTheme;
use Moose;
use methods-invoker;
use Socialtext::Account;
use Socialtext::Theme;
use Socialtext::SASSy;
use Socialtext::HTTP qw(:codes);
use Socialtext::Permission qw(ST_ADMIN_PERM ST_READ_PERM);
use Socialtext::Upload;
use Socialtext::JSON qw(encode_json decode_json);
use File::Path qw(mkpath);
use Socialtext::Paths;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::SettingsTheme';

use constant static_path => Socialtext::Helpers->static_path;

has 'account' => (is=>'ro', isa=>'Maybe[Socialtext::Account]', lazy_build=>1);
sub _build_account {
    my $self = shift;
    return Socialtext::Account->Resolve($self->acct)
}

# /data/accounts/<account_id>/theme/<filename>
sub GET_css {
    my $self = shift;
    my $rest = shift;

    return $self->if_valid_request($rest => sub {
        my ($filename, $ext) = $self->filename =~ m{^([-\w]+)\.(sass|css|html)$};
        die 'Only sass, css, and html are acceptable file extensions' unless $ext;

        my $params = $self->account->prefs->all_prefs->{theme};
        $params->{static} = '"' . $self->static_path . '"';
        $params->{foreground_color} = $self->_fg_helper($params);

        if ($filename eq 'style') {
            $params->{body_background}
                = $self->_bg_helper(background => $params);
            $params->{header_background} = $self->_bg_helper(header => $params);
        }

        my $sass = Socialtext::SASSy->Fetch(
            dir_name => $self->account->name,
            filename => $filename,
            params => $params,
        );
        $sass->render if $sass->needs_update;

        my $file_sub = $ext . '_file';
        my $size = $sass->$file_sub();

        $rest->header(
            -status               => HTTP_200_OK,
            '-content-length'     => $size || 0,
            -type                 => $ext eq 'sass' ? 'text/plain' : "text/$ext",
            -pragma               => undef,
            '-cache-control'      => undef,
            'Content-Disposition' => qq{filename="$filename.$ext.txt"},
            '-X-Accel-Redirect'   => $sass->protected_uri("$filename.out.$ext"),
        );
    });
}

method _fg_helper($theme) {
    my $shade = $theme->{foreground_shade};

    my $foreground = {
        light => '#CCCCCC',
        dark => '#111111',
    }->{$shade};
    die "no fg_helper for $shade" unless $foreground;

    return $foreground;
}

method _bg_helper($which, $theme) {
    my $acct_id = $self->account->account_id;

    my $attrs;
    if (defined $theme->{$which."_image_id"}) {
        $attrs =
            $theme->{$which."_color"} ." ".
            "url(/data/accounts/$acct_id/theme/images/$which) ".
            $theme->{$which."_image_tiling"} ." ".
            $theme->{$which."_image_position"};
    }
    else {
        $attrs = $theme->{$which."_color"};
    }

    return $attrs;
}


override '_build_prefs' => sub {
    my $self = shift;

    return $self->account->prefs;
};

override 'if_valid_request' => sub {
    my $self = shift;
    my $rest = shift;
    my $coderef = shift;

    return $self->no_resource('account') unless $self->account;

    my $method = $rest->getRequestMethod;
    my $user = $self->rest->user;

    my $permission = $method eq 'GET'
        ? ST_READ_PERM
        : ST_ADMIN_PERM;

    # guest user is allowed to GET for their primary account.
    if ($user->is_guest) {
        return $self->not_authorized()
            if $user->primary_account_id != $self->account->account_id
                or $method ne 'GET';
    }
    else {
        return $self->not_authorized()
            unless $user->is_business_admin or $self->account->user_can(
                user=>$user,
                permission=>$permission,
            );
    }

    return $coderef->();
};

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::AccountTheme - Handler for Account Themes ReST calls

=head1 SYNOPSIS

    GET /data/accounts/:acct/theme
    PUT /data/accounts/:acct/theme
    GET /data/accounts/:acct/theme/images/:filename

=head1 DESCRIPTION

View and manipulate Account Theme settings.

=cut
