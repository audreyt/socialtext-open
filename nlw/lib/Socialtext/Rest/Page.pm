package Socialtext::Rest::Page;
# @COPYRIGHT@

use strict;
use warnings;

# REVIEW: Can this be made into a Socialtext::Entity?
use base 'Socialtext::Rest';
use HTML::WikiConverter;
use Socialtext::JSON;
use Readonly;
use Socialtext::HTTP ':codes';
use Socialtext::Events;
use Socialtext::Date;
use Socialtext::Timer qw/time_scope/;

Readonly my $DEFAULT_LINK_DICTIONARY => 'REST';
Readonly my $S2_LINK_DICTIONARY      => 'S2';

# REVIEW: When we get html, we're not getting <html><body> etc
# Is this good or bad?
sub make_GETter {
    my ( $content_type ) = @_;
    return sub {
        my ( $self, $rest ) = @_;

        $self->if_authorized(
            'GET',
            sub {
                my $page = $self->page;
                if ( $page->content eq '' ) {
                    $rest->header(
                        -status => HTTP_404_Not_Found,
                        -type   => 'text/plain'
                    );
                    return $self->pname . ' not found';
                }
                elsif ( !$self->_page_type_is_valid ) {
                    $rest->header(
                        -status => HTTP_409_Conflict,
                        -type   => 'text/plain'
                    );
                    return $self->pname . ' is not the correct type';
                }
                else {
                    my $t = time_scope "get_page__$content_type";
                    $self->hub->pages->current($page);
                    my @etag = ();

                    if ( $content_type eq 'text/x.socialtext-wiki' ) {
                        my $etag = $page->revision_id();
                        @etag = ( -Etag => $etag );

                        my $match_header
                            = $self->rest->request->header_in('If-None-Match');
                        if ($match_header && $match_header eq $etag ) {
                            $rest->header(
                                -status => HTTP_304_Not_Modified,
                                @etag,
                            );
                            return '';
                        }
                    }

                    my $content_to_return = $page->content_as_type(
                        type => $content_type,

                        # FIXME: this should be a CGI paramter in some cases
                        link_dictionary => $self->_link_dictionary($rest),
                    );
                    $rest->header(
                        -status        => HTTP_200_OK,
                        -type          => $content_type . '; charset=UTF-8',
                        -Last_Modified => $self->make_http_date(
                            $page->modified_time()
                        ),
                        @etag,
                        -X_Socialtext_Cache => ($page->{__cache_hit} ? 'hit' : 'miss'),
                    );
                    $self->_record_view($page);

                    if ($content_type eq 'text/html' and $content_to_return =~ /container\.renderGadget/) {
                        # TODO: Refactor this to properly reuse [% FILTER decorate "head" %].
                        my $app_version = Socialtext->product_version;
                        $content_to_return = << ".";
<script>
function nlw_make_s2_path(rest) {
      return "/static/$app_version/skin/s2" + rest;
}
function nlw_make_skin_path(rest) {
      return "/static/$app_version/skin/s3" + rest;
}
function nlw_make_static_path(rest) {
      return "/static/$app_version" + rest;
}
function nlw_make_s3_path(rest) {
      return "/static/$app_version/skin/s3" + rest;
}
function nlw_make_plugin_path(rest) {
      return "/static/$app_version".replace(/static/, 'nlw/plugin') + rest;
}
</script>
<script type="text/javascript" charset="utf-8" src="/static/$app_version/skin/s3/javascript/socialtext-s3.js.gz"></script>
<script src="/nlw/plugin/$app_version/widgets/javascript/socialtext-container.js.gz"></script>
<script>
if (gadgets && gadgets.config) {
    gadgets.config.init({
        "core.io" : {
            "jsonProxyUrl" : "/nlw/$app_version/json-proxy"
        },
        "rpc" : {
            "parentRelayUrl" : "/nlw/plugin/widgets/rpc_relay.html",
            "useLegacyProtocol" : false
        },
        "opensocial-0.8": {
            // Path to fetch opensocial data from
            // Must be on the same domain as the gadget rendering server
            "path" : "/nlw",

            // Path to issue invalidate calls
            "invalidatePath" : "/what_is_this",
            "domain" : "shindig",
            "enableCaja" : false,
            "supportedFields" : {
               "person" : []
            }
        }
    }, true);
}
</script>
<link rel="stylesheet" type="text/css" href="/nlw/plugin/$app_version/widgets/css/inline.css" media="screen" />
$content_to_return
.
                    }

                    return $content_to_return;
                }
            }
        );
    };
}


sub _page_type_is_valid { 1 }

{
    no warnings 'once';
    *GET_wikitext = make_GETter( 'text/x.socialtext-wiki' );
    *GET_html = make_GETter( 'text/html' );
}

# look in the link_dictionary query parameter to figure out
# how to format links
sub _link_dictionary {
    my $self = shift;
    my $rest = shift;

    # we want the default link dictionary in the REST to be REST, but in the
    # LinkDictionary system it is the one used by S2, but it has no name, so
    # do a little dance to make it work as you might want.
    my $link_dictionary = $rest->query->param('link_dictionary')
        || $DEFAULT_LINK_DICTIONARY;
    $link_dictionary = undef
        if lc($link_dictionary) eq lc($S2_LINK_DICTIONARY);

    if ($link_dictionary && $link_dictionary eq $DEFAULT_LINK_DICTIONARY) {
        my $url_prefix = $self->hub->current_workspace->uri;
        $url_prefix =~ s{/[^/]+/?$}{};
        $self->hub->viewer->url_prefix($url_prefix);
    }

    return $link_dictionary;
}

# REVIEW: Can probably use similar Etag stuff in here
# not using the make_GETtter since we are getting different stuff here
sub GET_json {
    my $self = shift;
    my $rest = shift;

    $self->if_authorized(
        'GET',
        sub {
            my $verbose = $rest->query->param('verbose');
            my $wikitext = $rest->query->param('wikitext');
            my $metadata = $rest->query->param('metadata');
            my $html     = $rest->query->param('html');

            my $link_dictionary = $self->_link_dictionary($rest);
            my $page = $self->page;

            if ( !$self->_page_type_is_valid ) {
                $rest->header(
                    -status => HTTP_409_Conflict,
                    -type   => 'text/plain'
                );
                return $self->pname . ' is not the correct type';
            }

            if ($page->active) {
                my $t = time_scope 'get_page_json';
                $rest->header(
                    -status => HTTP_200_OK,
                    -type   => 'application/json; charset=UTF-8',
                );
                $self->hub->pages->current($page);
                my $page_hash = $page->hash_representation();

                my $addtional_content = sub {
                    $page->content_as_type( type => $_[0],
                        link_dictionary => $_[1] );
                };

                $page_hash->{editable} =
                    $self->hub->checker->check_permission('edit');

                my $to_html = sub {
                    $addtional_content->('text/html', $link_dictionary);
                };
                my $to_wikitext = sub {
                    $addtional_content->('text/x.socialtext-wiki');
                };
                if ($verbose) {
                    $page_hash->{wikitext} = $to_wikitext->();
                    $page_hash->{html} = $to_html->();
                    $page_hash->{last_editor_html} = 
                        $self->hub->viewer->text_to_html(
                            "\n{user: $page_hash->{last_editor}}\n"
                        );
                    $page_hash->{last_edit_time_html} = 
                        $self->hub->viewer->text_to_html(
                            "\n{date: $page_hash->{last_edit_time}}\n"
                        );
                    $page_hash->{workspace} =
                        $self->hub->current_workspace->to_hash(minimal => 1);
                }
                elsif ($wikitext) {
                    $page_hash->{wikitext} = $to_wikitext->();
                }
                elsif ($html) {
                    $page_hash->{html} = $to_html->();
                }

                $page_hash->{metadata} =
                    $page->legacy_metadata_hash($page_hash);

                # Backwards compat
                $page_hash->{workspace}{title} = $page_hash->{workspace_title};

                $self->_record_view($page);
                return encode_json($page_hash);
            }
            else {
                $rest->header(
                    -status => HTTP_404_Not_Found,
                    -type   => 'text/plain',
                );
                return $self->pname . ' not found';
            }
        }
    );
}

sub _record_view {
    my ($self, $page) = @_;
    unless ($page->is_untitled) {
        Socialtext::Events->Record({
            event_class => 'page',
            action => 'view',
            page => $page,
        });
    }
}

sub DELETE {
    my ( $self, $rest ) = @_;

    return $self->no_workspace()   unless $self->workspace;
    my $lock_check_failed = $self->page_lock_permission_fail();
    return $lock_check_failed if ($lock_check_failed);
    if ($self->page->deleted) {
        $rest->header( -status => HTTP_409_Conflict );
        return 'Page is already deleted.';
    }

    $self->if_authorized(
        DELETE => sub {
            $self->page->delete( user => $rest->user );
            $rest->header( -status => HTTP_204_No_Content );
            return '';
        }
    );
}

sub PUT_wikitext {
    my ( $self, $rest ) = @_;

    my $unable_to_edit = $self->page_locked_or_unauthorized();
    return $unable_to_edit if ($unable_to_edit);

    my $page = $self->page;
    my $existed_p = $page->content ne '';

    my $match_header = $self->rest->request->header_in('If-Match');
    if (   $existed_p
        && $match_header
        && ( $match_header ne $page->revision_id() ) ) {
        $rest->header(
            -status => HTTP_412_Precondition_Failed,
        );
        return '';
    }

    $page->update_from_remote(
        content => $rest->getContent(),
    );

    $rest->header(
        -status => $existed_p ? HTTP_204_No_Content: HTTP_201_Created,
        -Location => $self->full_url
    );
    return '';
}

sub PUT_html {
    my ( $self, $rest ) = @_;

    my $unable_to_edit = $self->page_locked_or_unauthorized();
    return $unable_to_edit if ($unable_to_edit);

    my $page = $self->page;
    my $existed_p = $page->content ne '';

    my $match_header = $self->rest->request->header_in('If-Match');
    if (   $existed_p
        && $match_header
        && ( $match_header ne $page->revision_id() ) ) {
        $rest->header(
            -status => HTTP_412_Precondition_Failed,
        );
        return '';
    }

    my $html = $rest->getContent(),

    my $wc = new HTML::WikiConverter( dialect => 'Socialtext');
    my $wikitext = $wc->html2wiki( html => $html );

    $page->update_from_remote(
        content => $wikitext,
    );

    $rest->header(
        -status => $existed_p ? HTTP_204_No_Content: HTTP_201_Created,
        -Location => $self->full_url
    );
    return '';
}

sub _default_page_type { 'wiki' }
sub _acceptable_page_types {
    my $self = shift;
    my $type = shift;
    return $type =~ m/^wiki|spreadsheet$/;
}

sub PUT_json {
    my ( $self, $rest ) = @_;

    my $unable_to_edit = $self->page_locked_or_unauthorized();
    return $unable_to_edit if ($unable_to_edit);

    my $page = $self->page;
    my $existed_p = $page->content ne '';

    my $match_header = $self->rest->request->header_in('If-Match');
    if (   $existed_p
        && $match_header
        && ( $match_header ne $page->revision_id() ) ) {
        $rest->header(
            -status => HTTP_412_Precondition_Failed,
        );
        return '';
    }

    my $content = $rest->getContent();
    my $object = decode_json( $content );
    if (my $d = $object->{date}) {
        $object->{date} = $self->make_date_time_date($d);
    }
    else {
        $object->{date} = Socialtext::Date->now(hires => 1);
    }

    if (my $t = $object->{type}) {
        $object->{type} = undef unless $self->_acceptable_page_types($t);
    }
    $object->{type} ||= $self->_default_page_type;

    # If the user is trying to lock the page, make sure that 1) they can
    # and 2) the workspace allows page locking.
    # In the case of an unauthorized user trying to _unlock_ a page, 
    # the page_locked_or_unauthorized check above will catch 'em.
    if ( $object->{locked} ) {
        return $self->not_authorized()
            unless $self->workspace->allows_page_locking
                && $self->hub->checker->check_permission('lock');
    }
    my $edit_summary = $object->{edit_summary} || '';
    my $signal_edit_summary = $object->{signal_edit_summary} || '';
    my $signal_edit_to_network = $object->{signal_edit_to_network} || '';

    $page->update_from_remote(
        content => $object->{content},
        from    => $object->{from},
        date    => $object->{date},
        edit_summary => $edit_summary,
        signal_edit_summary => $signal_edit_summary,
        signal_edit_to_network => $signal_edit_to_network,
        $object->{tags} ? (tags => $object->{tags}) : (),
        $object->{type} ? (type => $object->{type}) : (),
        $object->{locked} ? (locked => $object->{locked}) : (),
    );

    $rest->header(
        -status => $existed_p ? HTTP_204_No_Content: HTTP_201_Created,
        -Location => $self->full_url
    );
    return '';
}


sub allowed_methods { 'GET, HEAD, PUT, DELETE' }
