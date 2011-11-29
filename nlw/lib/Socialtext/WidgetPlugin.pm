package Socialtext::WidgetPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';
use Class::Field qw(const);
use Socialtext::l10n qw(loc __);
use Socialtext::Formatter::Phrase ();
use Socialtext::String ();
use Socialtext::Paths ();
use Socialtext::JSON qw( encode_json decode_json_utf8 );
use Encode ();

const class_id    => 'widget';
const class_title => __('class.widget');
const cgi_class   => 'Socialtext::WidgetPlugin::CGI';

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add(action => 'widget_setup_screen');
    $registry->add(wafl => widget => 'Socialtext::WidgetPlugin::Wafl');
}

sub gadget_vars {
    my ($self, $src, $encoded_prefs) = @_;
    $src = "local:widgets:$src" unless $src =~ /:/;

    # Setup overrides and override preferences
    my %overrides = (
        instance_id => ((2 ** 30) + int(rand(2 ** 30))),
    );
    for my $encoded_pref (split /\s+/, $encoded_prefs) {
        $encoded_pref =~ /^([^\s=]+)=(\S*)/ or next;
        my ($key, $val) = ($1, $2);
        use bytes;
        $val =~ s/%([0-9A-Fa-f]{2})/chr hex($1)/eg;
        Encode::_utf8_off($val);
        $val = Encode::decode_utf8($val);
        $key =~ s/^up_/UP_/;
        $overrides{$key} = $val;
    }

    my $gadget = Socialtext::Gadgets::Gadget->Fetch(src => $src);
    my $preferences = $gadget->preferences;
    for my $pref (@$preferences) {
        my $name = $pref->{name};

        # Backwards compat
        $overrides{"UP_$name"} = $overrides{$name} if defined $overrides{$name};

        if ($pref->{datatype} eq 'workspace') {
            $overrides{"UP_$name"} = $self->cgi->workspace_name
                || $self->hub->current_workspace->name;
        }

        my $overridden = $overrides{"UP_$name"} // next;
        $pref->{value} = $overridden; # This affects $gadget->requires_preferences
    }

    my $workspace = Socialtext::Workspace->new(
        name => $self->cgi->workspace_name || $self->hub->current_workspace->name,
    );
    my $account = $workspace->account;
    $overrides{"ENV_primary_account"} = $account->name;
    $overrides{"ENV_primary_account_id"} = $account->account_id;

    my $renderer = Socialtext::Gadget::Renderer->new(
        gadget => $gadget,
        view => 'page',
        overrides => \%overrides,
    );

    my $width = $overrides{__width__} // 600;
    $width .= "px" if $width =~ /^\d+$/;

    my $content_type = $renderer->content_type || 'html';

    return {
        # Render the preferences so __('') in options localizes correctly.
        %{ $renderer->render($gadget->template_vars) || {} },
        instance_id => $overrides{instance_id},
        content_type => $content_type,
        title => $overrides{__title__} || $renderer->render($gadget->title),
        width => $width,
        $content_type eq 'inline'
            ? (content => $renderer->content)
            : (href => $renderer->href),
    };
}

sub widget_setup_screen {
    my $self = shift;

    my $workspace = Socialtext::Workspace->new(
        name => $self->cgi->workspace_name || $self->hub->current_workspace->name,
    );
    my $account = $workspace->account;

    return $self->hub->template->process("view/container.setup",
        $self->hub->helpers->global_template_vars,
        current_workspace => {
            label => $workspace->title,
            name => $workspace->name,
            account => $account->name,
            id => $workspace->workspace_id,
        },
        current_account => {
            name => $account->name,
            account_id => $account->account_id,
            plugins => [$account->plugins_enabled],
        },
        container => { id => -1 },
        pluggable => $self->hub->pluggable,
        gadget => $self->gadget_vars(
            $self->cgi->widget, $self->cgi->encoded_prefs,
        ),
    );
}

################################################################################
package Socialtext::WidgetPlugin::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'workspace_name';
cgi 'page_id';
cgi 'widget';
cgi 'serial';
cgi 'encoded_prefs';
cgi 'do_delete_container';

################################################################################
package Socialtext::WidgetPlugin::Wafl;

use base 'Socialtext::Formatter::WaflPhraseDiv';
use Class::Field qw( const );
use Socialtext::l10n 'loc';
use Socialtext::Formatter::Phrase ();
use Socialtext::Gadget::Renderer;
use Socialtext::Gadgets::Gadget;

const wafl_id => 'widget';
const wafl_reference_parse => qr/^\s*([^\s#]+)(?:\s*#(\d+))?((?:\s+[^\s=]+=\S*)*)\s*$/;

sub html {
    my $self = shift;
    my ($src, $serial, $encoded_prefs) = $self->arguments =~ $self->wafl_reference_parse;

    $serial ||= 1;
    $encoded_prefs ||= '';

    my $gadget_vars = $self->hub->widget->gadget_vars($src, $encoded_prefs);
    return $self->hub->template->process('view/container.wafl',
        $self->hub->helpers->global_template_vars,
        pluggable => $self->hub->pluggable,
        gadget    => $gadget_vars,
    );
}

1;
__END__

=head1 NAME

Socialtext::WidgetPlugin - Plugin for embedding OpenSocial widgets in wiki pages.

=head1 SYNOPSIS

{widget: tag_cloud}

=head1 DESCRIPTION

Embed OpenSocial widgets into wiki pages.

=cut
