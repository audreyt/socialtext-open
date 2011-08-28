# @COPYRIGHT@
package Socialtext::WeblogUpdates;
use strict;
use warnings;

use base 'Socialtext::Base';

use LWP::UserAgent;
use Socialtext::AppConfig;

=head1 NAME

Socialtext::WeblogUpdates - A utility class that provides an interface for sending webloUpdates.ping

=head1 SYNOPSIS

    # cause a weblog ping to be scheduled for later via Socialtext::Postprocess
    Socialtext::WeblogUpdates->new(hub => $hub)->initiate_ping($page);

    # cause a weblog ping to happen right now
    Socialtext::WeblogUpdates->new(hub => $hub)->send_ping($page);

=head1 DESCRIPTION

Socialtext::WeblogUpdates is a system for sending the xml-rpc weblogUpdates.ping
described at L<http://www.xmlrpc.com/weblogsCom>. The weblogUpdates.ping
is a system for notifying weblog spiders and notification systems 
(such as technorati) that the sending weblog has been udpated.

In NLW, the ping can be used to notify services that a particular page
in a particular workspace has been updated.

By default, pings are never sent. If a workspace has one or more URIs
in the "WorkspacePingURI" table, a properly formatted xml-rpc
weblogUpdates.ping will be sent to each URL when a page is
stored. Because pings are performed asynchronously from user action
little error handling is done. If things go awry in the HTTP
transaction a warning is written to STDERR (usually the apache error
log).

See L<https://www.socialtext.net/ops/index.cgi?how_to_use_technorati_tags_and_weblog_pings_in_eventspace>
for system configuration information.

=head1 METHODS

=head2 send_ping($page)

Formats and sends a weblogUpdates.ping for the L<Socialtext::Page> represented
as C<$page>. Do not send a ping if the workspace is not configured to
send pings or if the page has not changed recently.

=cut

sub send_ping {
    my $self = shift;
    my $page = shift;

    return unless $self->hub->current_workspace->ping_uris;
    return unless $page->is_recently_modified;

    # XXX what sort of escaping do we need on this
    my $full_url = $self->hub->current_workspace->uri
        . Socialtext::AppConfig->script_name . '?'
        . $page->uri;
    my $title = $self->hub->current_workspace->title . ' - ' . $page->title;
    my $ping_text =<<"EOF";
<?xml version="1.0"?>
<methodCall>
    <methodName>weblogUpdates.ping</methodName>
    <params>
        <param>
            <value>$title</value>
        </param>
        <param>
            <value>$full_url</value>
        </param>
    </params>
</methodCall>
EOF

    my @ping_sites = $self->hub->current_workspace->ping_uris;
    foreach my $url (@ping_sites) {
        $self->hub->log->info( 'sending ping for '
                . $page->id
                . ' from '
                . $self->hub->current_workspace->name . ' to '
                . $url );

        $self->_do_ping($url, $full_url, $ping_text);
    }
}

sub _do_ping {
    my $self = shift;
    my ($url, $full_url, $ping_text) = @_;

    my $ua  = LWP::UserAgent->new();
    $ua->agent('Socialtext Workspace v' . $self->hub->main->product_version);
    my $req = HTTP::Request->new('POST', $url);
    $req->header('Content-Type' => 'text/xml');
    $req->content($ping_text);

    my $res = $ua->request($req);
    unless ($res->is_success) {
        warn $res->status_line;
    }
}

1;

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

