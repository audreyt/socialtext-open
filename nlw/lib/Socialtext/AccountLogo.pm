package Socialtext::AccountLogo;
# @COPYRIGHT@
use Moose;
use File::Temp;
use Socialtext::Account;
use Socialtext::Image;
use Socialtext::File;
use Socialtext::Upload;
use Socialtext::Theme;
use File::Basename qw(dirname basename);
use namespace::clean -except => 'meta';

has 'account' => (
    is => 'ro', isa => 'Socialtext::Account',
    required => 1,
    weak_ref => 1,
    handles => { account_id => 'account_id', id => 'account_id' },
);

has 'theme' => (is => 'rw', isa => 'HashRef', lazy_build => 1);
sub _build_theme {
    my $self = shift;

    my $prefs = $self->account->prefs->all_prefs();

    return $prefs->{theme};
}

has 'logo' => (is => 'ro', isa => 'ScalarRef', lazy_build => 1, clearer => '_clear_logo');
sub _build_logo {
    my $self = shift;

    my $theme = $self->theme;
    my $img = Socialtext::Upload->Get(
        attachment_id => $theme->{logo_image_id});


    my $blob;
    $img->_load_blob(\$blob);
    return \$blob;
}

sub set { # this is a little roundabout, but it's rarely used.
    my $self = shift;
    my $blob_ref = shift;
    my $user = shift || Socialtext::User->SystemUser();

    my $tmp_file = File::Temp->new(UNLINK => 1);
    Socialtext::File::set_contents($tmp_file, $blob_ref);

    my $theme = $self->theme;
    delete $theme->{logo_image_id};
    $theme->{logo_image} = basename($tmp_file);
    $theme->{creator} = $user;
    Socialtext::Theme->_CreateAttachmentsIfNeeded(
        dirname($tmp_file),
        $theme,
    );
    
    $self->account->prefs->save({theme => $theme});
    $self->theme($theme);
    $self->_clear_logo();
}

sub is_default {
    my $self = shift;
    
    my $account_theme = $self->theme;
    my $default_theme = Socialtext::Theme->Default();

    return $account_theme->{logo_image_id} == $default_theme->logo_image_id;
}

__PACKAGE__->meta->make_immutable;
1;
