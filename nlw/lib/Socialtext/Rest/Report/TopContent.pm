package Socialtext::Rest::Report::TopContent;
# @COPYRIGHT@
use Moose;
use Socialtext::JSON qw/encode_json/;
use Socialtext::String;
use Socialtext::Timer qw/time_scope/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::ReportAdapter';

=head1 NAME

Socialtext::Rest::Report::TopContent - top content

=head1 SYNOPSIS

  GET /data/reports/top_content/now/-1week

=head1 DESCRIPTION

Shows the top viewed/edited/watched/emailed pages
in a workspace or account.

=cut

override 'GET_json' => sub {
    my $self = shift;
    my $user = $self->rest->user;

    my $report = eval { $self->adapter->_build_report(
        'TopContentByPage', {
            start_time => $self->start,
            duration   => $self->duration,
            top        => 20,
            type       => 'raw',
        }, $user,
    ) };
    return $self->error(400, 'Bad request', $@) if $@;
    my $authorized = eval { $report->is_viewable_by($user) };
    warn $@ if $@;
    return $self->not_authorized unless $authorized;

    my @page_data;
    eval { @page_data = $self->_combine_page_data( $report ); };
    return $self->error(400, 'Bad request', $@) if $@;

    my @sorted_pages = sort { $b->{count} <=> $a->{count} } @page_data;

    $self->rest->header(-type => 'application/json');
    my $json;
    eval {
        $json = encode_json({
            rows => \@sorted_pages,
            meta  => {
                account   => $self->_account_data( $report ),
                workspace => $self->_workspace_data( $report ),
            },
        });
    };
    return $self->error(400, 'Bad request', $@) if $@;
    return $json;
};

# There was a bug in the reporting code where the central page of a
# workspace could generate two distinct entries, one with an actual page_id
# and the other an empty string, we can get two hits for the same page. Let's
# combine those here. We'll grab 2X the results we need and sift through 'em.
#
# NOTE: this may result in some slightly inaccurate popularity.
sub _combine_page_data {
    my $self      = shift;
    my $report    = shift;
    my %page_data = ();
    my $data      = $report->_data;
    my $t = time_scope 'combine_page_data';

    # Clean up the data
    for my $row (@$data) {
        my ($ws_name, $page_id, $count) = @$row;

        my $wksp = Socialtext::Workspace->new( name => $ws_name );
        $page_id ||= Socialtext::String::title_to_id( $wksp->title );

        if ( my $content = $page_data{$page_id} ) {
            $content->{count} += $count;
            next;
        }

        $self->hub->current_workspace($wksp);
        my $page  = eval { $self->hub->pages->new_from_uri($page_id) };
        if ($@) { warn $@; next }

        $page_data{$page_id} = {
            title          => $page->title,
            uri            => $page->full_uri,
            is_spreadsheet => $page->is_spreadsheet,
            context_title  => $wksp->title,
            context_uri    => $wksp->uri,
            count          => $count,
        };

        if ( (keys %page_data) == 10 ) {
            return values %page_data;
        }
    }

    return values %page_data;
}

sub _account_data {
    my $self    = shift;
    my $report  = shift;

    # it is required that we either have a valid workspace or a valid
    # account.
    my $account = $report->account;
    if ($report->workspace) {
        $account ||= $report->workspace->account();
    }
    die "Could not find an account!" unless $account;

    return { name => $account->name };
}

sub _workspace_data {
    my $self      = shift;
    my $report    = shift;
    my $workspace = $report->workspace;

    return undef unless $workspace;

    return {
        title => $workspace->title,
        uri   => $workspace->uri,
    }
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
