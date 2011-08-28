package Socialtext::Rest::Comments;
# @COPYRIGHT@

use strict;
use warnings;

use base 'Socialtext::Rest';
use Socialtext::JSON;
use Socialtext::HTTP ':codes';

sub allowed_methods {'POST'}
sub permission      { +{ POST => 'comment' } }

sub POST_wikitext {
    my ( $self, $rest ) = @_;
    $self->_post($rest, {content => $rest->getContent});
}

sub POST_json {
    my ( $self, $rest ) = @_;

    my $content = $rest->getContent();
    $self->_post($rest, decode_json( $content ));
}

sub _post {
    my ( $self, $rest, $object ) = @_;

    my $lock_check_fail = $self->page_lock_permission_fail();
    return $lock_check_fail if ($lock_check_fail);

    $self->if_authorized(
        POST => sub {
            if ( $self->page->content eq '' ) {
                $rest->header(
                    -status => HTTP_404_Not_Found,
                    -type   => 'text/plain'
                );
                return "There is no page called '" . $self->pname . "'";
            }
            else {
                $self->page->add_comment(
                    $object->{content},
                    $object->{signal_comment_to_network}
                );
                $rest->header( -status => HTTP_204_No_Content );
                return '';
            }
        }
    );
}

1;
