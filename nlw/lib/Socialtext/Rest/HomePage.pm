# @COPYRIGHT@
package Socialtext::Rest::HomePage;
use strict;
use warnings;

=head1 DESCRIPTION

Redirect the client to the homepage of the current workspace by accessing

   /data/workspaces/:ws/homepage

=cut

use base 'Socialtext::Rest';
use Socialtext::HTTP ':codes';

sub allowed_methods { 'GET, HEAD' }

sub GET {
    my ($self, $rest) =@_;

    $self->if_authorized(
        'GET',
        sub {
            my $page_name = $self->workspace->title;
            my $page_uri  = $self->hub->pages->new_from_name($page_name)->uri;
            my $url = $self->full_url();
            $url =~ s{homepage$}{pages/$page_uri};

            $self->rest->header(
                -status => HTTP_302_Found,
                -Location => $url,
            );
            return '';
        }
    );
}

1;

