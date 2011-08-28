package Socialtext::Rest::PageRevision;
# @COPYRIGHT@

use strict;
use warnings;

use base 'Socialtext::Rest::Page';
use Socialtext::HTTP ':codes';

sub page {
    my $self = shift;
    return $self->{page} if $self->{page};
    my $page = $self->hub->pages->new_from_name($self->pname);
    $page->revision_id($self->revision_id);
    $self->{page} = $page;
    return $page;
}

# REVIEW: We can probably merge this with Socialtext::Rest::Page::make_GETter
# This version handles cases where the revision_id is bad, and also makes
# sure we don't user the formatter cache.
sub make_GETter {
    my ( $content_type, $link_dictionary ) = @_;
    return sub {
        my ( $self, $rest ) = @_;

        $self->if_authorized(
            'GET',
            sub {
                my $content = eval { $self->page->content() };
                if ($@) {
                    if ( $@ =~ /^No such file/ ) {
                        $rest->header(
                            -status => HTTP_404_Not_Found,
                            -type   => 'text/plain'
                        );
                        return $self->pname
                            . ' version '
                            . $self->revision_id
                            . ' not found';
                    }
                    else {
                        die $@;    # rethrow
                    }
                }

                if ( $content eq '' ) {
                    $rest->header(
                        -status => HTTP_404_Not_Found,
                        -type   => 'text/plain'
                    );
                    return $self->pname . ' not found';
                }
                else {
                    $rest->header(
                        -status        => HTTP_200_OK,
                        -type => $content_type . '; charset=UTF-8',
                        -Last_Modified => $self->make_http_date(
                            $self->page->modified_time()
                        ),
                    );
                    return $self->page->content_as_type(
                        type => $content_type,

                        # FIXME: this should be a CGI paramter in some cases
                        link_dictionary => $link_dictionary,
                        no_cache        => 1,
                    );
                }
            }
        );

    };
}

{
    no warnings 'once';
    *GET_wikitext = make_GETter( 'text/x.socialtext-wiki' );
    *GET_html = make_GETter( 'text/html', 'REST' );
}

sub allowed_methods { 'GET, HEAD' }

1;
