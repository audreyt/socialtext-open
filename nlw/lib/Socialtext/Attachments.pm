package Socialtext::Attachments;
# @COPYRIGHT@
use 5.12.0;
use Moose;
use MooseX::StrictConstructor;
use List::MoreUtils qw/uniq/;
use Guard;
use Carp;

use Socialtext::Timer qw/time_scope/;
use Socialtext::SQL qw/:exec :txn/;
use Socialtext::Attachment;
use Socialtext::Permission 'ST_READ_PERM';
use Socialtext::Client::Wiki qw( wiki2html );

use namespace::clean -except => 'meta';

has 'hub' => (is => 'rw', isa => 'Socialtext::Hub',
    weak_ref => 1, required => 1);

use constant class_id => 'attachments';

use constant COLUMNS =>
    uniq(Socialtext::Attachment->COLUMNS, Socialtext::Upload->COLUMNS);
use constant COLUMNS_STR => join ', ', COLUMNS;

my @att_cols = qw(id workspace_id page_id deleted);

sub _new_from_row {
    my ($self, $upload_args) = @_;
    my %att_args;
    @att_args{@att_cols} = delete @$upload_args{@att_cols};
    $upload_args->{created_at} = delete $upload_args->{created_at_utc}
        if $upload_args->{created_at_utc};
    $att_args{upload} = Socialtext::Upload->new($upload_args);
    $att_args{hub} = $self->hub;
    return Socialtext::Attachment->new(\%att_args);
}

sub load {
    my ($self, %args) = @_;
    my $t = time_scope 'get_attach';
    my $ws_id   = $self->hub->current_workspace->workspace_id;
    my $page_id = $args{page_id} || $self->hub->pages->current->id;
    my $ident = $args{id} or croak "must supply an attachment id";
    my $deleted = $args{deleted_ok}
        ? '' : "\n AND NOT pa.deleted";
    my $sql = q{
        SELECT }.COLUMNS_STR.q{,
               created_at AT TIME ZONE 'UTC' || '+0000' AS created_at_utc
          FROM page_attachment pa
          JOIN attachment a USING (attachment_id)
         WHERE workspace_id = $1 AND page_id = $2 AND pa.id = $3 }.
         $deleted;
    my $sth = sql_execute($sql, $ws_id, $page_id, $ident);
    if ($sth->rows == 0) {
        croak $args{deleted_ok}
            ? "Attachment not found."
            : "This attachment has been deleted.";
    }
    return $self->_new_from_row($sth->fetchrow_hashref);
}

sub all {
    my $self = shift;
    my $t = time_scope 'all_attach';
    my $p = ref $_[0] ? $_[0] : {@_};
    my $page_id  = $p->{page_id} || $self->hub->pages->current->id;
    my $page = $p->{page};
    my $ws_id    = $self->hub->current_workspace->workspace_id;
    my $not_deleted = $p->{deleted_ok} ? '' : 'AND NOT deleted';

    my $sql = q{
        SELECT }.COLUMNS_STR.qq{,
               created_at AT TIME ZONE 'UTC' || '+0000' AS created_at_utc
          FROM page_attachment pa
          JOIN attachment a USING (attachment_id)
         WHERE workspace_id = ? AND page_id = ? $not_deleted
    };
    my @args = ($ws_id, $page_id);

    if ($p->{filename}) {
        $sql .= q{ AND lower(a.filename) = lower(?) };
        push @args, $p->{filename};
    }

    given ($p->{order}) {
        $sql .= ' ORDER BY lower(a.filename) ASC, a.created_at ASC' when "alpha_date";
        $sql .= ' ORDER BY a.filename ASC' when "alpha";
        $sql .= ' ORDER BY a.content_length DESC, a.created_at ASC' when "size";
        $sql .= ' ORDER BY a.created_at ASC' when "date";
        $sql .= ' ORDER BY a.created_at ASC';
    }

    if ($p->{limit}) {
        $sql .= ' LIMIT ?';
        push @args, $p->{limit};
    }
    if ($p->{offset}) {
        $sql .= ' OFFSET ?';
        push @args, $p->{offset};
    }
    my $sth = sql_execute($sql, @args);

    my @attachments;
    while (my $att_args = $sth->fetchrow_hashref) {
        my $att = $self->_new_from_row($att_args);
        $att->_page($page) if $page;
        push @attachments, $att;
    }
    return \@attachments;
}

sub count {
    my $self = shift;
    my $t = time_scope 'count_attach';
    my $p = ref $_[0] ? $_[0] : {@_};
    my $page_id  = $p->{page_id} || $self->hub->pages->current->id;
    my $ws_id    = $self->hub->current_workspace->workspace_id;
    my $not_deleted = $p->{deleted_ok} ? '' : 'AND NOT deleted';

    my $sql = qq{
        SELECT COUNT(1) FROM page_attachment pa
          JOIN attachment a USING (attachment_id)
         WHERE workspace_id = ? AND page_id = ? $not_deleted
    };
    my @args = ($ws_id, $page_id);

    if ($p->{filename}) {
        $sql .= q{ AND lower(a.filename) = lower(?) };
        push @args, $p->{filename};
    }

    return sql_singlevalue($sql,@args);
}

sub latest_with_filename {
    my $self = shift;
    my $t = time_scope 'latest_attach';
    my $p = ref $_[0] ? $_[0] : {@_};
    my $page_id  = $p->{page_id} || $self->hub->pages->current->id;
    my $ws_id    = $self->hub->current_workspace->workspace_id;
    my $filename = $p->{filename};

    my $sth = sql_execute(q{
        SELECT }.COLUMNS_STR.q{,
               created_at AT TIME ZONE 'UTC' || '+0000' AS created_at_utc
          FROM page_attachment pa
          JOIN attachment a USING (attachment_id)
         WHERE workspace_id = $1 AND page_id = $2
           AND lower(filename) = lower($3)
           AND NOT pa.deleted
         ORDER BY a.created_at DESC
         LIMIT 1
    }, $ws_id, $page_id, $filename);
    return if $sth->rows == 0;
    return $self->_new_from_row($sth->fetchrow_hashref);
}

sub attachment_exists {
    my ($self, $workspace, $page_id, $filename, $attach_id) = @_;
    my $t = time_scope 'attach_exists';

    my $ws = Socialtext::Workspace->new(name => $workspace)
        or return 0;
    return 0 unless $self->hub->authz->user_has_permission_for_workspace(
        user       => $self->hub->current_user,
        permission => ST_READ_PERM,
        workspace  => $ws,
    );

    my @bind = ($ws->workspace_id, $page_id, $filename);
    my $where = 'workspace_id = $1 AND page_id = $2';
    if ($attach_id) {
        push @bind, $attach_id;
        $where .= ' AND pa.id = $4'
    }

    my $n = sql_singlevalue(qq{
        SELECT count(1) FROM page_attachment pa
          JOIN attachment a USING (attachment_id)
         WHERE $where
           AND NOT pa.deleted
           AND lower(a.filename) = lower(\$3)
         LIMIT 1
    }, @bind);
    return $n ? 1 : 0;
}

sub create {
    my ($self, %args) = @_;
    my $t = time_scope 'attach_create';
    my $hub = $self->hub;
    $args{creator} ||= $hub->current_user;

    confess "just specify a page or a page_id, not both, to create an attachment"
        if ($args{page} && $args{page_id});
    
    my $page;
    if ($args{page}) {
        $page = $args{page};
    }
    elsif ($args{page_id}) {
        $page = $hub->pages->new_page($args{page_id});
    }
    else {
        $page = $hub->pages->current;
    }

    my $cur_guard = $hub->pages->ensure_current($page);

    return sql_txn {
        my $upload;
        if ($args{attachment_uuid}) {
            $upload = Socialtext::Upload->Get(
                attachment_uuid => $args{attachment_uuid});
        }
        else {
            my $ct = $args{mime_type} ||
                     $args{content_type} ||
                     $args{'Content_type'} ||
                     $args{'content-type'};
            $upload = Socialtext::Upload->Create(
                creator        => $args{creator},
                filename       => $args{filename},
                temp_filename  => $args{fh},
                mime_type      => $ct,
            );
        }

        my $att = Socialtext::Attachment->new(
            upload  => $upload,
            hub     => $hub,
            page_id => $page->page_id,
            page    => $page,
        );
        $att->store(user => $args{creator}, temporary => $args{temporary});
        $att->inline($args{creator}) if $args{embed};
        return $att;
    };
}

sub inline_all {
    my ($self, $user, $page, $attachments) = @_;
    croak "User is mandatory!" unless $user;

    my $guard = $self->hub->pages->ensure_current($page);
    $page->edit_rev();

    my $body_ref = $page->body_ref;
    my $body_new = '';
    for my $att (@$attachments) {
        $body_new .= $att->image_or_file_wafl();
    }
    $body_new = wiki2html($body_new) if $page->page_type eq 'xhtml';
    $body_new .= $$body_ref;
    $body_ref = \$body_new;
    $page->body_ref(\$body_new);

    $page->store(user => $user);
}


sub all_attachments_in_workspace {
    my $self = shift;
    my @attachments;
    my $t = time_scope 'all_attach';
    my $sth = sql_execute(q{
        SELECT }.COLUMNS_STR.q{,
               created_at AT TIME ZONE 'UTC' || '+0000' AS created_at_utc
          FROM page_attachment pa
          JOIN attachment a USING (attachment_id)
         WHERE pa.workspace_id = $1
           AND NOT pa.deleted
           AND EXISTS (
              SELECT 1 FROM page p
              WHERE p.workspace_id = pa.workspace_id
                AND p.page_id = pa.page_id
                AND NOT p.deleted
           )
         ORDER BY created_at
    }, $self->hub->current_workspace->workspace_id);
    while (my $row = $sth->fetchrow_hashref) {
        push @attachments, $self->_new_from_row($row);
    }
    return \@attachments;
}

*IDForFilename = *id_for_filename;
sub id_for_filename {
    my ($class_or_self, %p) = @_;

    my $filename = $p{filename} or croak "must supply filename";
    my $ws_id = blessed($p{workspace_id})
        ? $p{workspace_id}->workspace_id : $p{workspace_id};
    my $page_id = blessed($p{page_id}) ? $p{page_id}->id : $p{page_id};
    if (blessed($class_or_self)) {
        $ws_id //= $class_or_self->hub->current_workspace->workspace_id;
        $page_id //= $class_or_self->hub->pages->current->id;
    }

    my $sth = sql_execute(q{
        SELECT pa.id FROM page_attachment pa
          JOIN attachment a USING (attachment_id)
         WHERE pa.workspace_id = $1
           AND pa.page_id = $2
           AND NOT pa.deleted
           AND EXISTS (
              SELECT 1 FROM page p
              WHERE p.workspace_id = pa.workspace_id
                AND p.page_id = pa.page_id
                AND NOT p.deleted
           )
           AND lower(a.filename) = lower($3)
         ORDER BY a.created_at DESC
         LIMIT 1
    }, $ws_id, $page_id, $filename);
    return unless $sth->rows == 1;
    my $id = $sth->fetchrow_arrayref;
    return $id->[0];
}

__PACKAGE__->meta->make_immutable;
1;
