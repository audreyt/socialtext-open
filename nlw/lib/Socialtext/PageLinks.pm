package Socialtext::PageLinks;
# @COPYRIGHT@
use Moose;
use Socialtext::Paths;
use Socialtext::Pages;
use Socialtext::Timer;
use Socialtext::String qw/MAX_PAGE_ID_LEN/;
use Socialtext::SQL::Builder qw(sql_insert_many);
use Socialtext::SQL qw(sql_execute sql_txn);
use Digest::MD5 qw(md5_hex);
use namespace::clean -except => 'meta';

=head1 NAME

Socialtext::PageLinks

=head1 SYNOPSIS

    my $page_links = Socialtext::PageLinks->new(page => $page);
    my @forward_links = $page_links->links;
    my @backlinks = $page_links->backlinks;

=head1 DESCRIPTION

Represents all of a page's links and backlinks

=cut

has 'page' => (
    is => 'ro', isa => 'Socialtext::Page',
    required => 1,
);

has 'hub' => (
    is => 'ro', isa => 'Socialtext::Hub',
    required => 1,
);

has 'links' => (
    is => 'ro', isa => 'ArrayRef',
    lazy_build => 1, auto_deref => 1
);

sub _build_links {
    my $self    = shift;
    Socialtext::Timer->Continue('build_links');
    my $page_id = $self->page->id;
    my @links =
        map { $self->_create_page($_->{to_workspace_id}, $_->{to_page_id}) }
        grep { $_->{from_page_id} eq $page_id } $self->db_links;
    Socialtext::Timer->Pause('build_links');
    return \@links;
}

has 'backlinks' => (
    is => 'ro', isa => 'ArrayRef',
    lazy_build => 1, auto_deref => 1
);

sub _build_backlinks {
    my $self    = shift;
    my $page_id = $self->page->id;
    Socialtext::Timer->Continue('build_backlinks');
    my @backlinks =
        map { $self->_create_page($_->{from_workspace_id}, $_->{from_page_id}) }
        grep { $_->{to_page_id} eq $page_id }
        $self->db_links;
    Socialtext::Timer->Pause('build_backlinks');
    return \@backlinks;
}

sub update {
    my $self = shift;

    Socialtext::Timer->Continue('update_page_links');
    my $workspace_id = $self->hub->current_workspace->workspace_id;
    my $cur_workspace_name = $self->hub->current_workspace->name;
    my $page_id = $self->page->id;
    my $links = $self->page->get_units(
        'wiki' => sub {
            my $page_id = Socialtext::String::title_to_id($_[0]->title);
            return +{ page_id => $page_id, workspace_id => $workspace_id};
        },
        'wafl_phrase' => sub {
            my $unit = shift;
            if ($unit->method eq 'include') {
                $unit->arguments =~ $unit->wafl_reference_parse;
                my ( $workspace_name, $page_title, $qualifier ) = ( $1, $2, $3 );
                my $page_id = Socialtext::String::title_to_id($page_title);
                my $w = Socialtext::Workspace->new(name => $workspace_name);
                return +{
                    page_id => $page_id,
                    workspace_id => $w ? $w->workspace_id : $workspace_id,
                };
            } elsif ($unit->method eq 'link') {
                $unit->arguments =~ $unit->wafl_reference_parse;
                my ( $workspace_name, $page_title, $section ) = ( $1, $2, $3 );
                if ((! $workspace_name) || 
                    ($workspace_name eq $cur_workspace_name )) { #internal link 
                    my $page_id = Socialtext::String::title_to_id($page_title);
                    my $w = Socialtext::Workspace->new(name => $workspace_name);
                    return +{ 
                        page_id => $page_id, 
                        workspace_id => $w ? $w->workspace_id: $workspace_id,
                    };
                }
            }
            return;
        }
    );

    sql_txn {
        sql_execute('
            DELETE FROM page_link
             WHERE from_workspace_id = ?
               AND from_page_md5 = md5(?)
        ', $workspace_id, $page_id);

        my %seen;
        my @cols
            = qw(from_workspace_id from_page_id from_page_md5 to_workspace_id to_page_id to_page_md5);
        if (@$links) {
            my @values = map {
                    [ $workspace_id, $page_id, md5_hex($page_id), $_->{workspace_id}, $_->{page_id}, md5_hex($_->{page_id}) ]
                } 
                grep { length($_->{page_id}) <= MAX_PAGE_ID_LEN }
                grep { not $seen{ $_->{workspace_id} }{ $_->{page_id} }++ }
                @$links;
            sql_insert_many('page_link' => \@cols, \@values);
        }
    };
    Socialtext::Timer->Pause('update_page_links');
} 

sub _create_page {
    my ($self, $workspace_id, $page_id) = @_;
    my $page = Socialtext::Pages->By_id(
        hub => $self->hub,
        workspace_id => $workspace_id,
        no_die => 1,
        page_id => $page_id
    );
    unless ($page) {
        # Incipient page:
        my $old_workspace = $self->hub->current_workspace;
        $self->hub->current_workspace(
            Socialtext::Workspace->new(workspace_id => $workspace_id)
        );
        $page = Socialtext::Page->new(hub => $self->hub, id => $page_id);
        $self->hub->current_workspace($old_workspace);
    }
    return $page;
}

has 'db_links' => (
    is => 'ro', isa => 'ArrayRef[HashRef]',
    lazy_build => 1, auto_deref => 1,
);

sub _build_db_links {
    my $self         = shift;
    Socialtext::Timer->Continue('build_db_links');
    my $workspace_id = $self->hub->current_workspace->workspace_id;
    my $page_id      = $self->page->id;
    my $sth = sql_execute('
        SELECT from_workspace_id, from_page_id, to_workspace_id, to_page_id
          FROM page_link
         WHERE (
                 ( from_workspace_id = ? AND from_page_md5 = md5(?) )
              OR ( to_workspace_id   = ? AND to_page_md5   = md5(?) )
            )
           AND to_workspace_id = from_workspace_id -- disable interworkspace
         ORDER BY from_workspace_id, to_workspace_id, from_page_id, to_page_id
    ', ($workspace_id, $page_id) x 2 );
    my $rows = $sth->fetchall_arrayref({});
    Socialtext::Timer->Pause('build_db_links');
    return $rows;
}

__PACKAGE__->meta->make_immutable;
return 1;
