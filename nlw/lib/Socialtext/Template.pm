# @COPYRIGHT@
package Socialtext::Template;
use strict;
use warnings;

use base 'Socialtext::Base';

use Socialtext::BrowserDetect ();
use Socialtext::AppConfig;
use Socialtext::Helpers;
use Socialtext::TT2::Renderer;
use Socialtext::l10n qw(loc system_locale);

sub class_id { 'template' }

sub process {
    my $self = shift;
    my $template = shift;

    my @vars = (
        loc             => \&loc,
        loc_lang        => $self->hub->best_locale(),
        loc_system_lang => system_locale(),
        detected_ie     => Socialtext::BrowserDetect::ie(),
        detected_safari => Socialtext::BrowserDetect::safari(),
        hub             => $self->hub,
        static_path     => Socialtext::Helpers->static_path,
        skin_path       => $self->hub->skin->skin_path,
        appconfig       => Socialtext::AppConfig->instance(),
        script_name     => Socialtext::AppConfig->script_name,
        round           => sub { int($_[0] + 0.5) },
        @_,
    );
    $self->hub->preferences->init;

    my @templates = (ref $template eq 'ARRAY')
      ? @$template
      : $template;

    return join '', map {
        $self->render($_, @vars)
    } @templates;
}

sub template_paths {
    my $self = shift;
    $self->{_template_paths} ||= [
        @{$self->hub->skin->template_paths},
        glob(Socialtext::AppConfig->code_base . "/plugin/*/template"),
    ];
    return $self->{_template_paths};
}

sub render {
    my $self = shift;
    my $template = shift;
    my %vars = @_;

    my $renderer = Socialtext::TT2::Renderer->instance;

    return $renderer->render(
        template => $template,
        vars     => \%vars,
        paths    => $self->template_paths,
    );
}

1;

