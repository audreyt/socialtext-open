# @COPYRIGHT@
package Socialtext::AttachmentsUIPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( const field );
use Socialtext::AppConfig;
use Socialtext::Helpers;
use Socialtext::TT2::Renderer;
use Socialtext::l10n qw(:all);
use Socialtext::String;
use Socialtext::Timer qw/time_scope/;
use Socialtext::Pageset;
use Socialtext::SQL qw/sql_txn/;
use Memoize;
use Try::Tiny;

const class_id => 'attachments_ui';
const class_title => __('class.attachments_ui');
const cgi_class   => 'Socialtext::AttachmentsUI::CGI';

field 'sortdir';
field 'display_limit_value';

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add( action => 'listall' );       # XXX "backwards compatibility"
    $registry->add( action => 'attachments' );   # XXX "backwards compatibility"
    $registry->add( action => 'attachments_upload' );
    $registry->add( action => 'attachments_download' );
    $registry->add( action => 'attachments_delete' );
    $registry->add( action => 'attachments_listall' );
    $registry->add( action => 'attachments_extract' );
}

# backwards compatibility for old links
sub listall {
    my $self = shift;
    $self->redirect('action=attachments_listall');
}

# more backwards comapt
sub attachments {
    my $self = shift;
    $self->redirect(
        '?page_name=' . $self->cgi->page_name . ';js=attachments_div_on' );
}

sub attachments_download {
    my $self = shift;
    my $id      = $self->cgi->id;

    return try {
        my $attachment = $self->hub->attachments->load(id => $id);
        # Hand this off to the REST API.
        $self->redirect($attachment->download_uri('original'));
    }
    catch {
        $self->failure_message(
            loc('error.no-attachment'),
            $_,
            $self->hub->pages->current
        );
    };
}

sub attachments_extract {
    my $self = shift;
    my $id = $self->cgi->attachment_id;
    my $page_id = $self->cgi->page_id;

    return try {
        my $attachment = $self->hub->attachments->load(
            id => $id, page_id => $page_id);
        $attachment->extract;
    }
    catch {
        $self->failure_message(
            loc('error.no-attachment'),
            $_,
            $self->hub->pages->current
        );
    };
}

sub attachments_upload {
    my $self = shift;
    my $t = time_scope 'upload_attachments';

    my $temp    = $self->cgi->editmode;
    my @files   = $self->cgi->file;
    my @embeds  = $self->cgi->embed;
    my @replace = $self->cgi->replace;

    my $count = grep { -s $_->{handle} } @files;
    my $page = $self->hub->pages->current;

    return loc('error.file-required')
        unless $count;

    return loc('error.file-upload-forbidden')
        unless ($self->hub->checker->check_permission('attachments')
            and $self->hub->checker->can_modify_locked($page));

    my $atts = $self->hub->attachments;
    my $errors = '';
    my @uploaded;

    # consume as we go to reduce resources
    while (my $file = shift @files) {
        my $replace = shift @replace;
        my $embed   = shift @embeds;

        next unless $file->{handle};
        my $len = -s $file->{handle};
        next unless $len;

        # this stringification is to remove tied weirdness:
        my $filename = "$file->{filename}";
        $embed = 0 if ($temp || $page->is_spreadsheet);

        sql_txn { 
            if ($replace) {
                my $with_name = $atts->all(filename => $filename);
                for my $att (@$with_name) {
                    $att->is_temporary ? $att->purge() : $att->delete();
                }
            }

            try {
                my $att = $atts->create(
                    fh             => $file->{handle},
                    filename       => $filename,
                    creator        => $self->hub->current_user,
                    embed          => $embed,
                    temporary      => $temp,
                    content_length => $len,
                    # TODO: extract mime-type hint?
                    # mime_type => $file->...->{'Content-Type'},
                );
                push @uploaded, $att->to_hash;
            }
            catch {
                s/\. at.*//s;
                chomp;
                $errors .= "$_\n";
            };
        };
    }

    my $renderer = Socialtext::TT2::Renderer->instance;
    return $renderer->render(
        paths    => $self->hub->skin->template_paths,
        template => 'view/attachmentresult',
        vars     => {
            error => $errors,
            files => \@uploaded,
        },
    );
}

sub attachments_listall {
    my $self = shift;

    $self->sortdir(
        {
            filename => 'asc',
            subject  => 'asc',
            user     => 'asc',
            size     => 'desc',
            date     => 'desc',
        }
    );

    my $sortby = $self->cgi->sortby || 'filename';
    my $direction = $self->cgi->direction || $self->sortdir->{$sortby};

    my $attachments = $self->hub->attachments->all_attachments_in_workspace();
    my $rows = $self->_table_rows($attachments);

    $self->screen_template('view/attachmentslist');
    $self->render_screen(
        rows => $rows,
        display_title => loc("file.all"),
        sortby => $sortby,
        sortdir => $self->sortdir,
        direction => $direction,
        predicate => 'action=attachments_listall',
        Socialtext::Pageset->new(
            cgi => {$self->cgi->all},
            total_entries => scalar(@$attachments),
        )->template_vars(),
    );
}

sub _table_rows {
    my $self        = shift;
    my $attachments = shift;

    my @rows;
    for my $att (@$attachments) {
        my $page = $att->page();

        push @rows, {
            link      => $att->download_link,
            id        => $att->id,
            filename  => $att->filename,
            subject   => $page->title,
            user      => $att->creator->username, # TODO: pass object
            date_str  => sub { $att->created_at_str },
            date      => sub { $att->created_at },
            user_date => sub { $self->hub->timezone->get_date_user($att->created_at) },
            page_uri  => $page->uri,
            page_link => sub {
                Socialtext::Helpers->page_display_link_from_page($page) },
            size                => $att->content_length,
            human_readable_size =>
                $self->_human_readable_size( $att->content_length ),
            page_is_locked => $page->locked,
            user_can_modify => sub { $self->hub->checker->can_modify_locked( $page ) },
        };
    }

    return $self->sorted_result_set( \@rows );
}

memoize('_human_readable_size', NORMALIZER => sub { $_[1] });
sub _human_readable_size {
    my ( $self, $size ) = @_;

    # calculate size in gb, mb, kb, or bytes, and present a useful-er string
    my $KB = 1024;
    my $MB = 1024 * $KB;
    my $GB = 1024 * $MB;

    my $unit;

    if ( $size / $GB > 1 ) {
        $unit = int($size / $GB) . "gb";
    }
    elsif ( $size / $MB > 1 ) {
        $unit = int($size / $MB) . "mb";
    }
    elsif ( $size / $KB > 1 ) {
        $unit = int($size / $KB) . "kb";
    }
    else {
        $unit = $size . "bytes";
    }

    return $unit;
}

sub sorted_result_set {
    my $self = shift;
    my $rows = shift;
    my $limit = shift;

    my $sortby = $self->cgi->sortby || 'filename';
    my $direction = $self->cgi->direction || $self->sortdir->{$sortby};

    my $sortsub = $self->_gen_sort_closure( $sortby, $direction );

    @{$rows} = sort $sortsub @{$rows};
    splice @{$rows}, $limit
        if defined($limit) and @{$rows} > $limit;
    return $rows;
}

sub _gen_sort_closure {
    my $self        = shift;
    my $sortby      = shift; # the attribute being sorted on
    my $direction   = shift; # the direction ('asc' or 'desc')

    if ( $sortby eq 'size' ) { # The only integral attribute, so use numeric sort
        if ( $direction eq 'asc' ) {
            return sub {
                $a->{size} <=> $b->{size}
                    or lcmp( $a->{subject}, $b->{subject} );
                }
        }
        else {
            return sub {
                $b->{size} <=> $a->{size}
                    or lcmp( $a->{subject}, $b->{subject} );
                }
        }
    }
    elsif ( $sortby eq 'user' ) { 
        # we want to sort by whatever the system knows these users as, which
        # may not be the same as the from header.
        if ( $direction eq 'asc' ) {
            return sub {
                my $ua = Socialtext::User->new(username => $a->{user});
                my $ub = Socialtext::User->new(username => $b->{user});
                my $bfn_a = $ua->best_full_name;
                my $bfn_b = $ub->best_full_name;
                return lcmp($bfn_a, $bfn_b) or lcmp($a->{subject}, $b->{subject});
            }
        }
        else {
            return sub {
                my $ua = Socialtext::User->new(username => $a->{user});
                my $ub = Socialtext::User->new(username => $b->{user});
                my $bfn_a = $ua->best_full_name;
                my $bfn_b = $ub->best_full_name;
                return lcmp($bfn_b, $bfn_a) or lcmp($b->{subject}, $a->{subject});
            }
        }
    }
    else { # anythinge else, most likely a string
        $sortby = 'date_str' if $sortby eq 'date';
        if ( $direction eq 'asc' ) {
            return sub {
                my ($af, $bf) = ($a->{$sortby}, $b->{$sortby});
                $af = &$af if ref $af eq 'CODE';
                $bf = &$bf if ref $bf eq 'CODE';
                (lcmp( $af, $bf ))
                    or lcmp( $a->{subject}, $b->{subject} );
            };
        }
        else {
            return sub {
                my ($af, $bf) = ($a->{$sortby}, $b->{$sortby});
                $af = &$af if ref $af eq 'CODE';
                $bf = &$bf if ref $bf eq 'CODE';
                (lcmp( $bf, $af ))
                    or lcmp( $a->{subject}, $b->{subject} );
            };
        }
    }
}


sub attachments_delete {
    my $self    = shift;
    my $checker = $self->hub->checker;

    return unless $checker->check_permission('delete');
    my $user = $self->hub->current_user;

    for my $attachment_junk ( $self->cgi->selected ) {
        my ( $page_id, $id, undef ) = map { split ',' } $attachment_junk;

        next unless $checker->can_modify_locked(
            $self->hub->pages->new_page( $page_id ) );

        my $att = $self->hub->attachments->load(
            id => $id, page_id => $page_id, deleted_ok => 1);
        $att->delete(user => $user) unless $att->is_deleted;
    }

    if ( $self->cgi->caller_action eq 'attachments_listall' ) {
        return $self->redirect('action=attachments_listall');
    }

    # If called via AJAX we have nothing to return
    return;
}

#------------------------------------------------------------------------------#
package Socialtext::AttachmentsUI::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'direction';
cgi 'file' => '-upload';  #XXX Looks like the string is already encoded. hmmm???
cgi 'id' => '-clean_path';
cgi 'sortby';
cgi 'redirected';
cgi 'caller_action';
cgi 'button';
cgi 'checkbox';
cgi 'selected';
cgi 'filename';
cgi 'caller_action';
cgi 'page_name';
cgi 'embed';
cgi 'editmode';
cgi 'as_page';
cgi 'attachment_id';
cgi 'page_id';
cgi 'size';
cgi 'offset';
cgi 'replace';

1;
