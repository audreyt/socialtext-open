package Socialtext::GoogleSearchPlugin;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::Plugin';
use Socialtext::l10n qw(__);

use Class::Field qw( const );
use Socialtext::URI;
use REST::Google::Search;
use Socialtext::Encode;
use Socialtext::String qw( uri_unescape );

const limit => 8;
const class_title => __('class.google_search');

const class_id => 'google_search';

sub register {
    my $self     = shift;
    my $registry = shift;
    $registry->add(wafl => $_ => 'Socialtext::GoogleSearchPlugin::Wafl')
        for qw( googlesearch googlesoap );    # Keep "googlesoap" compat
}

sub get_result {
    my $self  = shift;
    my $query = shift;

    REST::Google::Search->http_referer(
        Socialtext::URI::uri(path => '/')
    );

    my @results;

    # The "rsz=large" below returns 8 results, which coincides
    # with our expected limit of 8; nevertheless, use a while
    # loop so we can adjust the limit later.
    while (@results < $self->limit) {
        my $res = REST::Google::Search->new(
            q     => Socialtext::Encode::ensure_is_utf8($query),
            rsz   => 'large',
            start => 0 + @results,
        );

        if ($res->responseStatus !~ /^2/) {
            last if @results;
            return { error => $res->responseStatus };
        }

        my @more = $res->responseData->results;
        last unless @more;
        push @results, @more;
    }

    # trim the result list to max "limit" items
    splice @results, $self->limit if (@results > $self->limit);

    return {
        resultElements => [
            map { +{
                title   => $_->title,
                URL     => uri_unescape($_->url),
                snippet => $_->content
            } } @results
        ]
    };
}

package Socialtext::GoogleSearchPlugin::Wafl;
use Socialtext::l10n qw(loc __);

use Socialtext::Formatter::WaflPhrase;
use base 'Socialtext::Formatter::WaflPhraseDiv';

sub html {
    my $self  = shift;
    my $query = $self->arguments;

    return $self->syntax_error unless defined $query and $query =~ /\S/;

    return $self->pretty(
        $query,
        $self->hub->google_search->get_result($query)
    );
}

sub pretty {
    my $self   = shift;
    my $query  = shift;
    my $result = shift;
    $self->hub->template->process('wafl_box.html',
        query      => $query,
        wafl_title => loc('google.for=query', $query),
        wafl_link  => "http://www.google.com/search?q=$query",
        items      => $result->{resultElements},
        error      => $result->{error},
    );
}

1;
__END__

=head1 NAME

Socialtext::GoogleSearchPlugin - Search google via its ReST API

=head1 SYNOPSIS

  {googlesearch: some terms to search for}

=head1 DESCRIPTION

Insert google search results into a page using the C<{googlesearch: }> WAFL.

The old "googlesoap" WAFL is supported for backwards-compatibility.

No callable-from-Perl API at the moment.

=cut
