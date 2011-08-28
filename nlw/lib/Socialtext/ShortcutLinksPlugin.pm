# @COPYRIGHT@
package Socialtext::ShortcutLinksPlugin;
use strict;
use warnings;
use Socialtext::l10n '__';

use base 'Socialtext::Plugin';

use Class::Field qw( const );
use Socialtext::AppConfig;
use YAML;

const class_title => __('class.shortcut_links');
const class_id => 'shortcut_links';


sub register {
    my $self = shift;
    my $registry = shift;
    my $config = $self->_get_config;
    foreach my $key (keys %{$config}) {
        $registry->add(wafl => $key => 'Socialtext::ShortcutLinks::Wafl');
        $registry->add(shortcut_links => $key => $config->{$key});
    }
    return;
}

sub _get_config {
    my $self = shift;
    my $config = {};

    my $file = Socialtext::AppConfig->shortcuts_file;
    if ( $file and -f $file ) {
        $config = YAML::LoadFile($file);
    }

    return $config;
}

package Socialtext::ShortcutLinks::Wafl;

use base 'Socialtext::Formatter::WaflPhrase';

sub html {
    my $self = shift;
    my $args = $self->arguments;
    my $key = $self->method;

    my $shortcuts = $self->hub->registry->lookup->{shortcut_links};
    my $shortcut = $shortcuts->{$key}[1];
    my ($url_template, $link_prefix) = split( ' ', $shortcut, 2 );

    my $url = $url_template;
    if ($url =~ /%s/) {
        $url =~ s/%s/$args/g;
    }
    elsif ( $url =~ /%\d/ ) {
        # Numbered args start at 1
        my @args = ( undef, split( ' ', $args ) );
        $url =~ s/%(\d)/$args[$1]/g;
    }
    else {
        $url .= $self->uri_escape($args);
    }

    $url = $self->html_escape($url);

    $link_prefix ||= '';
    $link_prefix .= ' ' if $link_prefix;

    return qq{<a href="$url">$link_prefix}
        . $self->html_escape($args) . '</a>';
}

1;

__END__

=head1 NAME

Socialtext::ShortcutLinksPlugin - WAFL-phrase shortcuts for arbitrary web links

=head1 DESCRIPTION

This plugin allows the NLW site maintainer to define a series of
shortcut wafl phrases via a simple config file. By default, that file is
F</etc/Socialtext/shortcuts.yaml>. This may be overridden per workspace
by setting C<shortcuts_file> in F<config.yaml>. Overriding does not add
to the list of shortcuts, it replaces.

Shortcuts take the form of C<keyword:url>. In the I<url> part, C<%s>
is replaced by the arguments given to the wafl phrase. For example:

  google:   http://www.google.com/search?q=%s

adds support for the wafl phrase C<{google:...}>, for example:

  Search Google for: {google: Kwiki}

will render as:

  Search Google for: <a href="http://www.google.com/search?q=Kwiki">Kwiki</a>

If the short-cut definition contains extra words, these will be
prepended to the rendered link.  For example:

  rt:       http://ticket-serv/Ticket/Display.html?id= RT Ticket

will render C<{rt:1234}> as:

  <a href="http://ticket-serv/Ticket/Display.html?id=1234">RT Ticket 1234</a>

You can also have up to nine positional parameters, so that:

  devlist:  http://list-archive/dev/%1/%2.html Mailing list message

will render C<{devlist: 2006-March 004434}> as:

  <a href="http://list-archive/dev/2006-March/004434.html">Mailing list message March-2006 004434</a>

If you use positional parameters, they must be whitespace separated.
Parameters may not have embedded spaces.

Entire-string C<%s> parameters override any C<%1>, C<%2>, ... positional
parameters.

=head1 AUTHORS

Socialtext::ShortcutLinksPlugin is derived from Kwiki::ShortcutLinks by 
Michael Gray <mjg17@eng.cam.ac.uk>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Michael Gray
Copyright (C) 2006 by Socialtext, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

