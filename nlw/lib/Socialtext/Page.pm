package Socialtext::Page;
# @COPYRIGHT@
use 5.12.0;
use Moose;

use Moose::Util::TypeConstraints;
use Socialtext::Moose::UserAttribute;
use Socialtext::MooseX::Types::Pg;
use Socialtext::MooseX::Types::UniStr;

use Socialtext::AppConfig;
use Socialtext::EmailSender::Factory;
use Socialtext::Encode qw/ensure_is_utf8 ensure_ref_is_utf8/;
use Socialtext::Events;
use Socialtext::File;
use Socialtext::Formatter::AbsoluteLinkDictionary;
use Socialtext::Formatter::Parser;
use Socialtext::Formatter::Viewer;
use Socialtext::JobCreator;
use Socialtext::Log qw/st_log/;
use Socialtext::PageRevision;
use Socialtext::Paths;
use Socialtext::Permission qw/ST_READ_PERM ST_EDIT_PERM ST_ATTACHMENTS_PERM/;
use Socialtext::SQL qw/:exec :txn :time/;
use Socialtext::SQL::Builder qw/sql_insert sql_update/;
use Socialtext::Search::AbstractFactory;
use Socialtext::String qw/:uri :html :id word_truncate/;
use Socialtext::URI;
use Socialtext::Timer qw/time_scope/;
use Socialtext::Validate qw(validate :types SCALAR SCALARREF ARRAYREF UNDEF BOOLEAN);
use Socialtext::WikiText::Emitter::SearchSnippets;
use Socialtext::WikiText::Parser;
use Socialtext::l10n qw(loc system_locale);
use Socialtext::Client::Wiki qw( html2wiki wiki2html );

use Digest::SHA1 'sha1_hex';
use Carp;
use Cwd ();
use DateTime;
use DateTime::Duration;
use DateTime::Format::Strptime;
use Date::Parse qw/str2time/;
use Email::Valid;
use File::Path;
use Readonly;
use Text::Autoformat;
use Time::Duration::Object;
use List::MoreUtils qw/any/;
use Try::Tiny;

sub class_id { 'page' }

Readonly my $SYSTEM_EMAIL_ADDRESS       => 'noreply@socialtext.com';
Readonly my $WIKITEXT_TYPE              => 'text/x.socialtext-wiki'; # Source (wiki)
Readonly my $XHTML_TYPE                 => 'application/xhtml+xml'; # Source (xhtml)
Readonly my $HTML_TYPE                  => 'text/html'; # Rendered

our $CACHING_DEBUG = 0;
our $DISABLE_CACHING = 0;

has 'hub' => (
    is => 'rw', isa => 'Socialtext::Hub',
    weak_ref => 1,
);

has 'workspace_id' => (is => 'rw', isa => 'Int', required => 1);
has 'page_id' => (is => 'rw', isa => 'Str', required => 1);
*id = *page_id; # legacy alias
has 'revision_id' => (is => 'rw', isa => 'Num',
    trigger => sub { $_[0]->_revision_id_changed($_[1],$_[2]) },
);
*current_revision_id = *revision_id;

has 'revision_count' => (is => 'rw', isa => 'Int');
has 'views' => (is => 'rw', isa => 'Int');

has_user 'creator' => (is => 'rw');
has 'create_time'  => (
    is => 'rw', isa => 'Pg.DateTime',
    coerce => 1,
    lazy => 1, # so the default doesn't fire right away
    default => sub { Socialtext::Date->now(hires=>1) },
);

has 'restored' => (is => 'rw', isa => 'Bool', writer => '_restored');
has 'full_uri' => (is => 'rw', isa => 'Str', lazy_build => 1);

has 'like_count' => (is => 'rw', isa => 'Int', default => 0);

has 'rev' => (
    is => 'rw', isa => 'Socialtext::PageRevision',
    lazy_build => 1,
    handles => {
        last_editor => 'editor',
        last_editor_id => 'editor_id',
        has_last_editor => 'has_editor',
        has_last_editor_id => 'has_editor_id',
        last_edit_time => 'edit_time',
        prev_rev => 'prev',
        has_prev_rev => 'has_prev',
        clear_prev_rev => 'clear_prev',
        # as-is mappings:
        (map {$_=>$_} qw(
            name revision_num modified_time page_type deleted summary
            edit_summary locked tags tag_set body_length body_ref 
            body_modified mutable is_spreadsheet is_wiki is_untitled
            has_tag tags_sorted is_recently_modified age_in_minutes
            age_in_seconds age_in_english datetime_for_user datetime_utc
            annotations annotation_triplets anno_blob
            is_xhtml
        )),
    },
);
*type = *page_type;
*last_edited_by = *last_editor;
*title = *name;
*is_in_category = *has_tag;
*time_for_user = *datetime_for_user;
*categories_sorted = *tags_sorted;

has 'workspace' => (is => 'rw', isa => 'Socialtext::Workspace', lazy_build => 1);
# SQL will select these out of the database, so we should use them if present:
has 'workspace_name' => (is => 'rw', isa => 'Str', lazy_build => 1);
has 'workspace_title' => (is => 'rw', isa => 'Str', lazy_build => 1);

has 'exists' => (is => 'rw', isa => 'Bool', lazy_build => 1, writer => '_exists');

sub BUILDARGS {
    my $class = shift;
    my $p = ref($_[0]) ? $_[0] : {@_};
    if (my $hub = $p->{hub}) {
        my $ws = $hub->current_workspace;
        $p->{workspace_id} = $ws->workspace_id;
    }
    $p->{page_id} = delete $p->{id} if $p->{id};
    $p->{page_id} ||= ($p->{page_type} && $p->{page_type} eq 'spreadsheet')
        ? 'untitled_spreadsheet' : 'untitled_page';
    $p->{create_time} = delete $p->{create_time_utc} if $p->{create_time_utc};
    return $p;
}

use constant SELECT_COLUMNS_STR => q{
    "Workspace".name AS workspace_name, 
    "Workspace".title AS workspace_title, 
    page.workspace_id, 
    page.page_id, 
    page.name, 
    page.last_editor_id AS last_editor_id, 
    -- _utc suffix is to prevent performance-impacing naming collisions:
    page.last_edit_time AT TIME ZONE 'UTC' AS last_edit_time_utc,
    page.creator_id,
    -- _utc suffix is to prevent performance-impacing naming collisions:
    page.create_time AT TIME ZONE 'UTC' AS create_time_utc,
    page.current_revision_id, 
    page.current_revision_num, 
    page.revision_count, 
    page.page_type, 
    page.deleted, 
    page.summary,
    page.edit_summary,
    page.views,
    page.locked,
    page.tags, -- ordered array
    page.like_count
};

# This should be the order they show up in on the actual table:
use constant COLUMNS => qw(
    workspace_id page_id name last_editor_id last_edit_time creator_id
    create_time current_revision_id current_revision_num revision_count
    page_type deleted summary edit_summary locked tags views 
);

# use 'user' and 'date' instead of 'creator/editor', 'create_time/edit_time'
sub Blank {
    my ($class, %p) = @_;
    die "no hub" unless $p{hub};
    $p{editor} = delete $p{user} || $p{hub}->current_user;
    $p{edit_time} = delete $p{date} if $p{date};
    my $rev = Socialtext::PageRevision->Blank(\%p);
    my $page = Socialtext::Page->new(
        hub => $rev->hub,
        page_id => $rev->page_id,
        rev => $rev,
        creator => $rev->editor,
        create_time => $rev->edit_time,
    );
    return $page;
}

# This should only get called as a result of somebody creating a page object
# that didn't go through _new_from_row() or when a revision_id isn't given to
# the constructor.  This means *you*, Socialtext::Pages->new_page()
sub _find_current {
    my $self = shift;

    my $sth = sql_execute(q{
        SELECT }.SELECT_COLUMNS_STR.q{
          FROM page JOIN "Workspace" USING (workspace_id)
         WHERE workspace_id = ? AND page_id = ?
    }, $self->workspace_id, $self->page_id);
    return unless $sth->rows == 1;

    my $db_row = $sth->fetchrow_hashref;
    my ($page_args, $rev_args) = _map_row($db_row);
    $rev_args->{hub} = $self->hub;

    my $rev = Socialtext::PageRevision->new($rev_args);

    # update the creator if it's changing
    my $creator_id = delete $page_args->{creator_id};
    if (($self->has_creator_id || $self->has_creator) &&
        $self->creator->user_id != $creator_id)
    {
        $self->clear_creator; # so that creator gets rebuilt from creator_id
    }
    # the writer for creator_id is _creator_id:
    $self->_creator_id($creator_id);

    $self->$_($page_args->{$_}) for keys %$page_args;
    $self->rev($rev); # should assign this last

    return $rev;
}

sub _build_rev {
    my $self = shift;
    if ($self->revision_id) {
        my $rev = Socialtext::PageRevision->Get(
            hub => $self->hub,
            page_id => $self->page_id,
            revision_id => $self->revision_id,
        );
        $self->_exists(1);
        return $rev;
    }
    elsif (my $rev = $self->_find_current) {
        $self->_exists(1);
        return $rev;
    }
    else {
        # must be creating the page
        $self->_exists(0);
        my $name = uri_unescape($self->page_id);
        return Socialtext::PageRevision->Blank(
            hub => $self->hub,
            name => $name,
            page_id => $self->page_id,
        );
    }
}

my %PAGE_ROW_MAP = (
    workspace_id => 'workspace_id',
    page_id => 'page_id',
    revision_id => 'current_revision_id',
    create_time => 'create_time_utc',
    creator_id => 'creator_id',
    revision_count => 'revision_count',
    views => 'views',
    workspace_name => 'workspace_name',
    workspace_title => 'workspace_title',
    like_count => 'like_count',
);
my %PAGE_ROW_SKIP = (
    workspace_name  => 1,
    workspace_title => 1,
    create_time => 1,
    creator_id => 1,
    views => 1, # updated independently
);

my %REV_ROW_MAP = (
    workspace_id => 'workspace_id',
    page_id => 'page_id',
    revision_id => 'current_revision_id',
    revision_num => 'current_revision_num',
    name => 'name',
    edit_time => 'last_edit_time_utc',
    editor_id => 'last_editor_id',
    page_type => 'page_type',
    deleted => 'deleted',
    summary => 'summary',
    edit_summary => 'edit_summary',
    locked => 'locked',
    tags => 'tags',
);

sub _map_row {
    my $db_row = shift;
    my %page_args;
    my %rev_args;
    @page_args{keys %PAGE_ROW_MAP} = @$db_row{values %PAGE_ROW_MAP};
    @rev_args{keys %REV_ROW_MAP} = @$db_row{values %REV_ROW_MAP};
    return \%page_args, \%rev_args;
}

# Do not call this unless the page exists already (or clear exists so it'll
# get lazy-built afterwards).
sub _new_from_row {
    my ($class, $db_row) = @_;
    my $hub = delete $db_row->{hub};
    my ($page_args, $rev_args) = _map_row($db_row);
    $rev_args->{hub} = $page_args->{hub} = $hub;
    my $rev = Socialtext::PageRevision->new($rev_args);
    $page_args->{rev} = $rev;
    $page_args->{exists} = 1; # it's in the database, so must exist
    return $class->new($page_args);
}

sub _build_exists {
    my $self = shift;
    return 1 if $self->has_rev && !$self->rev->mutable;
    my $rev = $self->_find_current();
    return $rev ? 1 : 0;
}

sub active { ($_[0]->exists && !$_[0]->deleted) ? 1 : 0 }

sub _build_full_uri {
    my $self = shift;
    my $ws_uri = Socialtext::URI::uri(path => $self->workspace_name);
    return $ws_uri.'/'.$self->uri;
}

sub _build_workspace{
    my $self = shift;
    return $self->hub->current_workspace;
}

sub _build_workspace_name {
    my $self = shift;
    return $self->workspace->name;
}

sub _build_workspace_title {
    my $self = shift;
    return $self->workspace->title;
}


sub edit_rev {
    my $self = shift;
    my %p = @_;
    return $self->rev if ($self->has_rev && $self->mutable);
    my $user = delete $p{user} || delete $p{editor} || $self->hub->current_user;
    my $edit = $self->rev->mutable_clone(%p, editor => $user);
    $self->rev($edit);
    return $edit;
}

*load_revision = *switch_rev; # grep: sub load_revision
sub switch_rev {
    my ($self, $rev_id) = @_;
    croak "page is being created, can't switch_rev()"
        if ($self->has_rev && $self->mutable && !$self->exists);
    $self->revision_id($rev_id); # calls the _revision_id_changed trigger
    $self->rev; # runs _build_rev as needed
    return $self;
}

sub _revision_id_changed {
    my ($self, $new, $old) = @_;

    # No change, no big deal
    return if (defined($old) && $old == $new);

    # Something set it to what the rev already has, so just leave it loaded.
    return if ($self->has_rev && $new == $self->rev->revision_id);

    # otherwise, this is probably a revision_id()/load() pair, so clear out
    # the rev slot so it can be lazy-loaded
    $self->clear_rev;
    return;
}

sub load { Carp::cluck "load() is now a no-op for Pages"; return shift }
sub load_content { Carp::cluck "load_content() is now a no-op for Pages"; }


sub createtime_for_user {
    my $self = shift;
    return $self->hub->timezone->get_date_user($self->create_time);
}
sub createtime_utc {
    my $self = shift;
    return $self->create_time->strftime('%Y-%m-%d %H:%M:%S GMT');
}

Readonly my $SignalCommentLength => 250;
Readonly my $SignalEditLength => 140;
sub _signal_edit_summary {
    my ($self, $user, $edit_summary, $to_network, $is_comment) = @_;
    $user //= $self->hub->current_user;
    my $signals = $self->hub->pluggable->plugin_class('signals');
    return unless $signals;
    return unless $user->can_use_plugin('signals');

    my $workspace = $self->hub->current_workspace;

    # Trim trailing whitespaces first
    $edit_summary =~ s/\s+$//;

    # If edit summary starts with a symbol (e.g. #tag or {wafl}), prepend a space
    # so the syntax won't be blocked by the leading double-quote.
    $edit_summary =~ s/^([^\s\w])/ $1/;

    $edit_summary = word_truncate($edit_summary,
        ($is_comment ? $SignalCommentLength : $SignalEditLength));
    my $page_link = sprintf "{link: %s [%s]}", $workspace->name, $self->name;
    my $body = $edit_summary
        ? ($is_comment
            ? loc('page.commented=summary,page,wiki', $edit_summary, $page_link, $workspace->title)
            : loc('page.edited=summary,page,wiki', $edit_summary, $page_link, $workspace->title))
        : loc('page.default-summary=page,wiki', $page_link, $workspace->title);

    my %params = (
        user  => $user,
        body  => $body,
        topic => {
            page_id      => $self->page_id,
            workspace_id => $workspace->workspace_id,
        },
        annotations => [
            { icon => { title => ($is_comment ? 'comment' : 'edit') } }
        ],
    );

    if ($to_network and $to_network =~ /^(group|account)-(\d+)$/) {
        $params{"$1_ids"} = [ $2 ];
    }
    else {
        $params{account_ids} = [ $workspace->account_id ];
    }

    my $signal = $signals->Send(\%params);
    if ($signal->is_edit_summary) {
        return $signal;
    }
    return;
}

sub update_from_remote {
    my $self = shift;
    my %p = @_;
    my $user = $self->hub->current_user;

    my $revision_id = $p{revision_id} || $self->revision_id || '';
    if (($self->revision_id || '') ne $revision_id) {
        Socialtext::Events->Record({
            event_class => 'page',
            action => 'edit_contention',
            page => $self,
        });
        $self->log_page_and_user('EDIT_CONTENTION,PAGE,edit_contention');
        Socialtext::Exception::Conflict->throw(
            error => "Contention: page has been updated since retrieved\n");
    }

    if (!$self->hub->checker->can_modify_locked($self)) {
        $self->log_page_and_user('LOCK_EDIT,PAGE,lock_edit');
        die "Page is locked and cannot be edited\n";
    }

    my $editor;
    if ($self->hub->checker->check_permission('admin_workspace')) {
        if ($p{from}) {
            $editor = Socialtext::User->Resolve($p{from});
            $editor ||= Socialtext::User->create(
                email_address => $p{from},
                username      => $p{from}
            );
        }
        else {
            $editor = $user;
        }
    }
    else {
        delete @p{qw(date from)};
        $editor = $user;
    }

    die "A valid user is required to update a page\n" unless $editor;

    my $rev = $self->edit_rev(editor => $editor);
    my $was_locked = $rev->locked;
    $rev->locked($p{locked}) if defined $p{locked};
    $rev->body_ref(\$p{content}) if exists $p{content};

    my $signal = $self->update(
        user         => $editor,
        revision     => $p{revision},
        categories   => $p{tags},
        edit_summary => $p{edit_summary} || '',
        type         => $p{type},
        subject      => $p{subject},
        $p{date} ? (date => $p{date}) : (),
        signal_edit_summary => $p{signal_edit_summary} || '',
        signal_edit_to_network => $p{signal_edit_to_network},
    );

    $self->update_lock_status($rev->locked, 'skip')
        if ($was_locked xor $rev->locked);

    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_save',
        page => $self,
        ($p{signal_edit_summary} ? (signal => $signal) : ()),
    });
    return; 
}

sub update_lock_status {
    my ($self, $status, $skip_edit) = @_;

    unless ($skip_edit) {
        my $summary = $status ? loc('page.locking') : loc('page.unlocking');
        my $rev = $self->edit_rev();
        $rev->locked($status);
        $rev->edit_summary($summary);
        $self->update();
    }

    Socialtext::Events->Record({
        event_class => 'page',
        action => $status ? 'lock_page' : 'unlock_page',
        page => $self,
    });
}

*to_hash = *hash_representation;
sub hash_representation {
    my $self = shift;

    my $hash = {
        create_time     => $self->createtime_utc,
        edit_summary    => $self->edit_summary,
        last_edit_time  => $self->datetime_utc,
        locked          => $self->locked ? 1 : 0,
        modified_time   => $self->modified_time,
        name            => $self->name,
        page_id         => $self->page_id,
        page_uri        => $self->full_uri,
        revision_count  => $self->revision_count,
        revision_id     => $self->revision_id,
        revision_num    => $self->revision_num,
        summary         => $self->summary,
        tags            => $self->tags,
        type            => $self->page_type,
        uri             => $self->uri,
        workspace_name  => $self->workspace_name,
        workspace_title => $self->workspace_title,
        creator_id      => $self->creator->user_id,
        last_editor_id  => $self->last_editor->user_id,
        annotations     => $self->annotations,

        ($self->deleted ? (deleted => 1) : ()),
    };

    for my $field (qw(creator last_editor)) {
        my $field_id = $field . '_id';
        my $has_field = "has_$field";
        my $has_field_id = "has_$field_id";
        if ($self->$has_field_id or $self->$has_field) {
            $hash->{$field_id} = $self->$field->user_id;
            $hash->{$field} = $self->$field->masked_email_address(
                user => $self->hub->current_user,
                workspace => $self->hub->current_workspace,
            );
        }
    }

    return $hash;
}

sub legacy_metadata_hash {
    my $self = shift;
    my $hash = shift || $self->to_hash;
    # use dashes instead of camel-case, e.g.
    # s/^([A-Z][a-z]+)([A-Z].*)$/$1-$2/;
    return +{
        ($hash->{deleted} ? ('Control' => 'Deleted') : ()),
        Subject => $hash->{name},
        From => $hash->{last_editor},
        Date => $hash->{last_edit_time},
        Revision => $hash->{revision_num},
        Type => $hash->{type},
        Summary => $hash->{summary},
        Category => $hash->{tags},
        Encoding => 'utf8',
        'Revision-Summary' => $hash->{edit_summary},
        'Locked' => $hash->{locked} ? 1 : 0,
    };
}

# This is called by Socialtext::Query::Plugin::push_result
# to create a row suitable for display in a listview.
our $No_result_times = 0;
sub to_result {
    my $self = shift;
    my $t = time_scope 'model_to_result';

    my $editor = $self->last_editor;
    my $creator = $self->creator;
    my $result = {
        annotations     => $self->annotations,
        Date            => $self->datetime_utc,
        Deleted         => $self->deleted ? 1 : 0,
        From            => $editor->email_address,
        Locked          => $self->locked ? 1 : 0,
        Revision        => $self->revision_num,
        Subject         => $self->name,
        Summary         => $self->summary,
        Type            => $self->page_type,
        create_time     => $self->createtime_utc,
        creator         => $creator->username,
        edit_summary    => $self->edit_summary,
        is_spreadsheet  => $self->is_spreadsheet,
        is_xhtml        => $self->is_xhtml,
        page_id         => $self->page_id,
        page_uri        => $self->uri,
        revision_count  => $self->revision_count,
        username        => $editor->username,
        workspace_name  => $self->workspace_name,
        workspace_title => $self->workspace_title,
    };

    if ($No_result_times) {
        $result->{page} = $self;
    }
    else {
        $result->{create_time_local} = $self->createtime_for_user;
        $result->{DateLocal} = $self->datetime_for_user;
    }

    return $result;
}

sub get_headers {
    my $self = shift;
    return $self->get_units(
        'hx' => sub {
            return +{text => $_[0]->get_text, level => $_[0]->level}
        },
    );
}

sub get_sections {
    my $self = shift;
    return $self->get_units(
        'hx' => sub {
            return +{text => $_[0]->get_text};
        },
        'wafl_phrase' => sub {
            return unless $_[0]->method eq 'section';
            return +{text => $_[0]->arguments};
        },
    )
}

sub prepend {
    my $self = $_[0];
    croak "page isn't mutable" unless $self->mutable;
    my $new = ref($_[1]) ? $_[1] : \$_[1];
    my $body_ref = $self->body_ref;
    if ($body_ref && length($$body_ref)) {
        my $body = "$$new\n---\n$$body_ref"; # deliberate copy
        $body_ref = \$body;
    } else {
        $body_ref = $new;
    }
    $self->body_ref($body_ref);
}

sub append {
    my $self = $_[0];
    croak "page isn't mutable" unless $self->mutable;
    my $new = ref($_[1]) ? $_[1] : \$_[1];
    my $body_ref = $self->body_ref;
    my $hr = "\n---\n";

    if ($self->is_xhtml) {
        # Run wiki2html before we get append_html implemented
        $hr = '<hr />';
        $new = \(scalar wiki2html($$new));
    }

    if ($body_ref && length($$body_ref)) {
        my $body = $$body_ref . $hr . $$new; # deliberate copy
        $body_ref = \$body;
    } else {
        $body_ref = $new;
    }
    $self->body_ref($body_ref);
}

sub uri {
    my $self = shift;
    return $self->exists ? $self->page_id : title_to_display_id($self->name);
}

sub _add_delete_tags {
    my ($self, $tags, $is_add) = @_;
    return unless scalar(@$tags);
    return unless $self->hub->checker->check_permission('edit');

    my $was_mutable = $self->mutable;
    my $rev = $self->edit_rev();
    my $changed = $is_add ? $rev->add_tags($tags) : $rev->delete_tags($tags);
    unless ($was_mutable) {
        $self->edit_summary('');
        $self->store();
    }

    foreach my $tag (@$changed) {
        Socialtext::Events->Record({
            event_class => 'page',
            action => $is_add ? 'tag_add' : 'tag_delete',
            page => $self,
            tag_name => $tag,
        });
    }
}

*add_tag = *add_tags;
sub add_tags {
    my $self = shift;
    my @tags  = grep { length } @_;
    return $self->_add_delete_tags(\@tags, 1);
}

*delete_tag = *delete_tags;
sub delete_tags {
    my $self = shift;
    my @tags  = grep { length } @_;
    return $self->_add_delete_tags(\@tags, 0);
}

sub add_comment {
    my $self     = shift;
    my $wikitext = shift;
    my $signal_edit_to_network = shift;
    my $user = $self->hub->current_user;

    my $t = time_scope 'add_comment';

    if (!$self->hub->checker->can_modify_locked($self)) {
        $self->log_page_and_user('LOCK_EDIT,PAGE,lock_edit');
        die "Page is locked and cannot be edited\n";
    }

    my $rev = $self->edit_rev();

    # Clean it up.
    $wikitext =~ s/\s*\z/\n/;
    ensure_ref_is_utf8(\$wikitext);
    # TODO: change this to encode a user_id instead? Would have import/export
    # and potentially backup/restore side-effects.
    my $utc_date = $rev->edit_time->strftime('%Y-%m-%d %H:%M:%S GMT');
    my $comment = "$wikitext\n_".loc("page.contributed-by=user,date", $rev->editor->email_address, $utc_date)."_\n";

    $self->append($comment); # pass-by-value is OK; will use $_[1]

    # Truncate the comment to $SignalCommentLength chars if we're sending this
    # comment as a signal.  Otherwise use the normal 350-char excerpt.
    my $summary = $signal_edit_to_network
        ? word_truncate($wikitext, $SignalCommentLength)
        : $self->preview_text($wikitext);
    $rev->edit_summary($summary);
    $rev->summary($summary);

    my $signal = $self->store(
        $signal_edit_to_network ? (
            signal_edit_summary_from_comment => 1,
            signal_edit_to_network => $signal_edit_to_network,
        ) : ()
    );

    Socialtext::Events->Record({
        event_class => 'page',
        action => 'comment',
        page => $self,
        summary => $summary,
        ($signal ? (signal => $signal) : ()),
    });
    return;
}

sub _fixup_body {
    my $self = shift;
    my $rev = $self->rev;
    my $body_ref = $rev->body_ref;
    if ($body_ref && length($$body_ref)) {
        if ($$body_ref =~ /(?:\r|\{now\}|\n*\z)/) {
            my $nowdate = $self->formatted_date;
            my $body = $$body_ref; # copy
            $body =~ s/\r//g;
            $body =~ s/\{now\}/$nowdate/egi;
            $body =~ s/\n*\z/\n/;
            $rev->body_ref(\$body);
        }
    }
    else {
        $rev->deleted(1);
    }
}

sub update {
    my ($self, %p) = @_;

    die "can't update; page is not mutable" unless $self->mutable;
    my $rev = $self->rev;

    if ($p{content_ref}) {
        $rev->body_ref($p{content_ref});
    }
    elsif (length $p{content}) {
        carp "caller should be using content_ref";
        $rev->body_ref(\$p{content});
    }

    if (my $tags = $p{categories}) {
        $tags = [map { ensure_is_utf8($_) } @$tags];
        $rev->add_tags($tags);
    }

    $rev->revision_num($p{revision}) if $p{revision};
    $rev->page_type($p{type}) if $p{type};
    $rev->name($p{subject}) if defined $p{subject};
    $rev->edit_summary($p{edit_summary}) if $p{edit_summary};
    $rev->editor($p{user}) if $p{user};
    $rev->edit_time($p{date}) if $p{date};

    $self->store(user => $p{user});

    return $self->_signal_edit_summary(
        $p{user}, $p{edit_summary}, $p{signal_edit_to_network}
    ) if $p{signal_edit_summary};

    return;
}

{
    my $spec = {  
        title      => SCALAR_TYPE,
        content    => SCALAR_TYPE,
        date       => { can => [qw(strftime)], default => undef },
        categories => { type => ARRAYREF, default => []  },
        creator    => { isa => 'Socialtext::User', default => undef },
        hub        => { isa => 'Socialtext::Hub', default => undef },
    };
    # Use this method by doing Socialtext::Page->new(hub => $hub)->create(...)
    sub create {
        my $class_or_self = shift;
        my %args = validate(@_,$spec);

        my $hub = blessed($class_or_self) ? $class_or_self->hub : $args{hub};
        croak "A hub is required to create() a page" unless $hub;

        $args{date} ||= Socialtext::Date->now(hires=>1);
        $args{creator} ||= $hub->current_user;
        
        my $page = $class_or_self->Blank(
            hub => $hub,
            name      => $args{title},
            editor    => $args{creator},
            edit_time => $args{date},
            tags      => $args{categories},
            body_ref  => \$args{content},
        );
        $page->store( user => $args{creator} );
        return $page;
    }
}

sub store {
    my $self = shift;
    my %p = @_;
    # who's doing the edit can be different from the actor (actor is always
    # current)
    my $user = $p{user} || $self->hub->current_user;

    confess "page isn't mutable; call edit_rev() first!" unless $self->mutable;

    my $rev = $self->rev;
    $rev->editor($p{user}) if $p{user};

    if ($rev->body_modified) {
        $self->_fixup_body();
    }

    my ($ws_id, $page_id) = map { $self->$_ } qw(workspace_id page_id);

    my %args = (
        workspace_id => $ws_id,
        page_id => $page_id,
    );

    # set the creator and time so that preview_text() works
    my $existed = $self->exists;
    unless ($existed) {
        $self->creator($rev->editor);
        $self->create_time($rev->edit_time);
    }

    $rev->summary($self->preview_text()) if $self->body_modified;

    my ($cur_rev_id, $was_deleted);
    sql_txn {

        if ($existed) {
            # check that the page is actually there.  For the create
            # (!$existed) case, the sql_insert below will fail instead.
            my $sth = sql_execute(q{
                SELECT current_revision_id, deleted FROM page
                 WHERE workspace_id = ? AND page_id = ?
                FOR UPDATE
            }, $self->workspace_id, $self->page_id);
            ($cur_rev_id,$was_deleted) = $sth->fetchrow_array;
            Socialtext::Exception::Conflict->throw(
                error => loc('error.page-conflict')) if (!$p{skip_rev_check} && $cur_rev_id && $cur_rev_id != $self->revision_id);
        }
        else {
            $rev->revision_num(1);
            $self->revision_count(0);
        }

        if ($was_deleted and $self->body_modified) {
            $rev->deleted(0);
        }

        $rev->store();

        $self->revision_id($rev->revision_id); # rev-store can change this
        $self->revision_count($self->revision_count+1);

        while (my ($page_attr,$db_col) = each %PAGE_ROW_MAP) {
            next if $PAGE_ROW_SKIP{$page_attr};
            $args{$db_col} = $self->$page_attr;
        }
        while (my ($rev_attr,$db_col) = each %REV_ROW_MAP) {
            $args{$db_col} = $rev->$rev_attr;
        }

        $args{last_edit_time} = sql_format_timestamptz(
            delete $args{last_edit_time_utc});
        $args{$_} //= 0 for qw(locked deleted);

        if (!$existed) {
            $args{create_time} = $args{last_edit_time};
            $args{creator_id} = $args{last_editor_id};
        }

        if (!$existed) {
            # this or committing the transaction will fail if the page already
            # exists:
            my $sth = sql_insert(page => \%args);
            die "Page creation failed. Maybe it already exists?"
                unless $sth->rows == 1;
        }
        else {
            my $sth = sql_update(page => \%args, [qw(workspace_id page_id)]);
            die "Page update failed. ".
                "Maybe it's missing or was wrongly assumed to have existed?"
                unless $sth->rows == 1;
        }

        my $tags = $rev->tags;
        if ($existed) {
            # Nothing refers to the page_tag table so these should be safe to
            # delete.
            sql_execute(qq{
                DELETE FROM page_tag WHERE workspace_id = ? AND page_id = ?
            }, $ws_id, $page_id);
        }
        sql_execute_array(q{
            INSERT INTO page_tag (workspace_id, page_id, tag) VALUES (?,?,?)
        }, {}, $ws_id, $page_id, $tags) if @$tags;
    };

    $self->_exists(1);
    $self->_restored(1) if ($was_deleted and !$self->deleted);

    $self->hub->backlinks->update($self);
    Socialtext::JobCreator->index_page($self);
    Socialtext::JobCreator->send_page_notifications($self);
    $self->_ensure_page_assets();
    $self->_log_page_action();
    $self->_cache_html();

    $self->hub->pluggable->hook( 'nlw.page.update',
        [$self, workspace => $self->hub->current_workspace],
    );

    $self->log_page_and_user('CREATE,EDIT_SUMMARY,edit_summary', $user)
        if $self->edit_summary;

    # need to return the Signal object if we're signalling-this-edit
    my @sigargs = ($user, $self->edit_summary, $p{signal_edit_to_network});
    if ($p{signal_edit_summary_from_comment}) {
        return $self->_signal_edit_summary(@sigargs, 'comment');
    }
    elsif ($p{signal_edit_summary}) {
        return $self->_signal_edit_summary(@sigargs);
    }

    return;
}

sub log_page_and_user {
    my ($self, $message, $user) = @_;
    $user //= $self->hub->current_user;
    st_log->info(
        $message.','
        . 'workspace:'.$self->workspace_name.'('.$self->workspace_id.'),'
        . 'user:'.$user->email_address.'('.$user->user_id.'),'
        . 'page:'.$self->page_id
    );
}

sub _ensure_page_assets {
    my $self = shift;
    return unless $self->exists;
    require Socialtext::Signal::Topic;
    Socialtext::Signal::Topic::Page->EnsureAssetsFor(
        page_id => $self->page_id,
        workspace_id => $self->workspace_id,
    );
}

sub is_system_page {
    my $self = shift;
    return (($self->creator_id || 0) == Socialtext::User->SystemUser->user_id
        or $self->creator->email_address eq $SYSTEM_EMAIL_ADDRESS);
}

sub is_bad_page_title {
    my $class_or_self = shift;
    if (blessed($class_or_self)) {
        return $class_or_self->rev->is_bad_page_title(@_);
    }
    else {
        return Socialtext::PageRevision->is_bad_page_title(@_);
    }
}

# This sub isn't horribly inefficient if you've just got a
# scalar and not a scalar-ref on-hand.  You really should be using body_ref()
# instead.
# XXX: returning content into a scalar will make a copy of that data, which
# wastes RAM.
sub content {
    my $self = $_[0];
    $self->body_ref(ref $_[1] ? $_[1] : \$_[1]) if (@_==2);
    return unless defined wantarray; # void context
    return ${$self->body_ref};
}

sub to_wikitext {
    my $self = shift;
    $self->content_as_type(@_, type => $WIKITEXT_TYPE)
}

sub to_xhtml {
    my $self = shift;
    $self->content_as_type(@_, type => $XHTML_TYPE)
}

sub content_as_type {
    my $self = shift;
    my %p    = @_;
    my $type = $p{type} || $WIKITEXT_TYPE;
    if ($type eq $HTML_TYPE) {
        return $self->_content_as_html($p{link_dictionary}, $p{no_cache});
    }
    elsif ($type eq $XHTML_TYPE and $self->page_type eq 'xhtml') {
        return '<div xmlns="http://www.w3.org/1999/xhtml" class="wiki xhtml">'
             . ${ $self->body_ref }
             . '</div>';
    }
    elsif ($type eq $XHTML_TYPE and $self->page_type eq 'wiki') {
        return '<div xmlns="http://www.w3.org/1999/xhtml" class="wiki">'
             . wiki2html(${ $self->body_ref })
             . '</div>';

    }
    elsif ($type eq $WIKITEXT_TYPE and $self->page_type eq 'xhtml') {
        return html2wiki(${ $self->body_ref });
    }
    elsif ($type eq $WIKITEXT_TYPE) {
        return ${ $self->body_ref };
    }
    else {
        Socialtext::Exception->throw("unknown content type");
    }
}

sub _content_as_html {
    my $self            = shift;
    my $link_dictionary = shift;
    my $no_cache        = shift;

    if ( defined $link_dictionary ) {
        my $link_dictionary_name = 'Socialtext::Formatter::'
            . $link_dictionary
            . 'LinkDictionary';
        my $link_dictionary;
        eval {
            eval "require $link_dictionary_name";
            $link_dictionary = $link_dictionary_name->new();
        };
        if ($@) {
            my $message
                = "Unable to create link dictionary $link_dictionary_name: $@";
            Socialtext::Exception->throw($message);
        }
        $self->hub->viewer->link_dictionary($link_dictionary);
    }

    # REVIEW: the args to to_html are to help make caching work
    if ($no_cache) {
        return $self->to_html;
    }
    else {
        return $self->to_html( $self->body_ref, $self );
    }
}

sub doctor_links_with_prefix {
    my $self = shift;
    my $prefix = shift;
    die "page isn't mutable" unless $self->mutable;
    my $new_content = ${$self->body_ref};
    my $link_class = 'Socialtext::Formatter::FreeLink';
    my $start = $link_class->pattern_start;
    my $end = $link_class->pattern_end;
    $new_content =~ s/{ (link:\s+\S+\s) \[ ([^\]]+) \] }/{$1\{$2}}/xg;
    # $start contains grouping syntax so we must skip $2
    $new_content =~ s/($start)((?!$prefix).+?)($end)/$1$prefix$3$4/g;
    $new_content =~ s/{ (link:\s+\S+\s) { ([^}]+) }}/{$1\[$2]}/xg;
    $self->body_ref(\$new_content);
    return;
}

sub size {
    my $self = shift;
    return $self->body_length;
}

sub all {
    my $self = shift;
    return (
        page_uri => $self->uri,
        page_title => $self->name,
        # Note:uri-escaped title wasn't always == page_id
        page_title_uri_escaped => $self->page_id,
        revision_id => $self->revision_id,
    );
}

sub to_html_or_default {
    my $self = shift;
    $self->to_html(
        $self->body_length ? $self->body_ref : \$self->default_content,
        $self);
}

# DO NOT use this internally; use:
#
#  $self->body_length ? $self->body_ref : \$self->default_content
#
sub content_or_default {
    my $self = shift;
    return ${$self->body_ref} if $self->body_length;
    return $self->default_content;
}

sub default_content {
    my $self = shift;
    return ((
        $self->is_spreadsheet ? loc('sheet.creating')
      : $self->is_xhtml ? loc('xhtml.creating')
      : loc('edit.default-text')
    ).'   ')
}

sub get_units {
    my $self    = shift;
    my %matches = @_;
    my @units;

    my $chunker = sub {
        my $content_ref = shift;
        _chunk_it_up( $content_ref, sub {
            my $chunk_ref = shift;
            $self->_get_units_for_chunk(\%matches, $chunk_ref, \@units);
        });
    };

    my $body_ref = $self->body_ref;
    if ($self->is_spreadsheet) {
        require Socialtext::Sheet;
        my $sheet = Socialtext::Sheet->new(sheet_source => $body_ref);
        my $valueformats = $sheet->_sheet->{valueformats};
        for my $cell_name (@{ $sheet->cells }) {
            my $cell = $sheet->cell($cell_name);

            my $valuesubtype = substr($cell->valuetype || ' ', 1);
            if ($valuesubtype eq "w" or $valuesubtype eq "r") {
                # This is a wikitext/richtext cell - proceed
            }
            else {
                my $tvf_num = $cell->textvalueformat
                    || $sheet->{defaulttextvalueformat};
                next unless defined $tvf_num;
                my $format = $valueformats->[$tvf_num];
                next unless defined $format;
                next unless $format =~ m/^text-wiki/;
            }

            # The Socialtext::Formatter::Parser expects this content
            # to end in a newline.  Without it no links will be found for
            # simple pages.
            my $dval = $cell->datavalue . "\n";
            $chunker->(\$dval);
        }
    }
    elsif ($self->is_xhtml) {
        my $wikitext = html2wiki($$body_ref);
        $chunker->(\$wikitext);
    }
    else {
        $chunker->($body_ref);
    }

    return \@units;
}

sub _get_units_for_chunk {
    my $self = shift;
    my $matches = shift;
    my $content_ref = shift;
    my $units = shift;

    my $parser = Socialtext::Formatter::Parser->new(
        table      => $self->hub->formatter->table,
        wafl_table => $self->hub->formatter->wafl_table
    );
    my $parsed_unit = $parser->text_to_parsed($content_ref);
    {
        no warnings 'once';
        # When we use get_text to unwind the parse tree and give
        # us the content of a unit that contains units, we need to
        # make sure that we get the right stuff as get_text is
        # called recursively. This insures we do.
        local *Socialtext::Formatter::WaflPhrase::get_text = sub {
            my $self = shift;
            return $self->arguments;
        };
        my $sub = sub {
            my $unit         = shift;
            my $formatter_id = $unit->formatter_id;
            if ( $matches->{$formatter_id} ) {
                push @$units, $matches->{$formatter_id}($unit);
            }
        };
        $self->traverse_page_units($parsed_unit->units, $sub);
    }
}

sub traverse_page_units {
    my $self  = shift;
    my $units = shift;
    my $sub   = shift;

    foreach my $unit (@$units) {
        if (ref $unit) {
            $sub->($unit);
            if ($unit->units) {
                $self->traverse_page_units($unit->units, $sub);
            }
        }
    }
}

# The WikiText::Parser doesn't yet handle really large chunks, so we
# should chunk this up ourself.  That being said, 100kiB should be plenty.
# (The old Formatter code has a constant set at 500,000 bytes, FWIW).
use constant CHUNK_IT_UP_SIZE => 100 * 1024;
sub _chunk_it_up {
    my $content_ref = shift;
    my $callback    = shift;

    if (length($$content_ref) < CHUNK_IT_UP_SIZE) {
        $callback->($content_ref);
        return;
    }

    my $chunk_start = 0;
    my $chunk = ''; # re-use the buffer (space & speed)
    while (1) {
        $chunk = substr($$content_ref, $chunk_start, CHUNK_IT_UP_SIZE);
        last unless length $chunk;
        $chunk_start += length $chunk;
        $callback->(\$chunk);
    }
    return;
}


sub to_absolute_html {
    my $self = $_[0];
    my $content = ref($_[1]) ? $_[1] : \$_[1]; # don't default this to body_ref

    my %p = @_[2..$#_];
    $p{link_dictionary}
        ||= Socialtext::Formatter::AbsoluteLinkDictionary->new();

    my $url_prefix = $self->hub->current_workspace->uri;
    $url_prefix =~ s{/[^/]+/?$}{};

    $self->hub->viewer->url_prefix($url_prefix);
    $self->hub->viewer->link_dictionary($p{link_dictionary});
    # REVIEW: Too many paths to setting of page_id and too little
    # clearness about what it is for. appears to only be used
    # in WaflPhrase::parse_wafl_reference
    $self->hub->viewer->page_id($self->page_id);

    # Don't assign these results to anything before returning. It will slow
    # down the program significantly.
    return $self->to_html($content) if defined($_[1]);
    return $self->to_html($self->body_ref, $self);
}

sub to_html {
    my ($self, $content_ref, $page) = @_;

    if (@_ == 1) {
        $content_ref = $self->body_length
            ? $self->body_ref : \$self->default_content;
        $page = $self;
    }
    elsif (!($content_ref || $$content_ref)) {
        $content_ref = \$self->default_content;
    }

    return $self->hub->pluggable->hook('render.sheet.html',
        [$content_ref, $self]
    ) if $self->is_spreadsheet;

    return $self->hub->pluggable->hook('render.xhtml.html',
        [$content_ref, $self]
    ) if $self->is_xhtml;

    return $self->hub->viewer->process($content_ref, $page)
        if $DISABLE_CACHING;

    # Look for cached HTML
    my $q_file = $self->_question_file;
    if ($q_file and -e $q_file) {
        my $q_str = Socialtext::File::get_contents($q_file);
        warn "QUESTION: $q_str\n" if $CACHING_DEBUG;
        my $a_str = $self->_questions_to_answers($q_str);
        my $cache_file = $self->_answer_file($a_str);
        my $cache_file_exists = $cache_file && -e $cache_file;
        my $users_changed = 0;
        if ($cache_file_exists) {
            my $cached_at = (stat($cache_file))[9];
            $users_changed = $self->_users_modified_since($q_str, $cached_at)
        }
        warn "MISS - Users changed!" if $CACHING_DEBUG and $users_changed;
        if ($cache_file_exists and !$users_changed) {
            my $t = time_scope('wikitext_HIT');
            $self->{__cache_hit}++;
            warn "HIT: $cache_file" if $CACHING_DEBUG;
            return scalar Socialtext::File::get_contents_utf8($cache_file);
        }

        my $t = time_scope('wikitext_MISS');
        warn "MISS on content ($a_str)" if $CACHING_DEBUG;
        my $html = $self->hub->viewer->process($content_ref, $page);

        # Check if we are the "current" page, and do not cache if we are not.
        # This is to avoid crazy errors where we may be rendering other page's
        # content for TOC wafls and such.
        my $is_current = $self->hub->pages->current->page_id eq $self->page_id;
        if (defined $a_str and $is_current) {
            # cache_file may be undef if the answer string was too long.
            # XXX if long answers get hashed we can still save it here
            Socialtext::File::set_contents_utf8_atomic($cache_file, $html)
                if $cache_file;
            warn "MISSED: $cache_file" if $CACHING_DEBUG;
            return $html;
        }
        else {
            warn "MISSED but not caching" if $CACHING_DEBUG;
        }
        # Our answer string was invalid, so we'll need to re-generate the Q file
        # We will pass in the rendered html to save work
        return ${ $self->_cache_html(\$html) };
    }

    return ${$self->_cache_html};
}

sub _cache_html {
    my $self = shift;
    my $html_ref = shift;
    return if $self->is_spreadsheet or $self->is_xhtml;

    my $t = time_scope('cache_wt');

    my %cacheable_wafls = map { $_ => 1 } qw/
        Socialtext::Formatter::TradeMark 
        Socialtext::Formatter::Preformatted 
        Socialtext::PageAnchorsWafl
        Socialtext::Wikiwyg::FormattingTestRunAll
        Socialtext::Wikiwyg::FormattingTest
        Socialtext::ShortcutLinks::Wafl
    /;
    require Socialtext::CodeSyntaxPlugin;
    for my $brush (keys %Socialtext::CodeSyntaxPlugin::Brushes) {
        $cacheable_wafls{"Socialtext::CodeSyntaxPlugin::Wafl::$brush"} = 1;
    }
    my %not_cacheable_wafls = map { $_ => 1 } qw/
        Socialtext::Formatter::SpreadsheetInclusion
        Socialtext::Formatter::PageInclusion
        Socialtext::RecentChanges::Wafl
        Socialtext::Category::Wafl
        Socialtext::Search::Wafl
        Socialtext::WidgetPlugin::Wafl
    /;
    my @cache_questions;
    my %interwiki;
    my %allows_html;
    my %users;
    my %attachments;
    my $expires_at;

    {
        no warnings 'redefine';
        # Maybe in the future un-weaken the hub so this hack isn't needed. 
        local *Socialtext::Formatter::WaflPhrase::hub = sub {
            my $wafl = shift;
            return $wafl->{hub} || $self->hub;
        };
        $self->get_units(
            wafl_phrase => sub {
                my $wafl = shift;

                my $wafl_expiry = 0;
                my $wafl_class = ref $wafl;

                # Some short-circuts based on the wafl class
                return if $cacheable_wafls{ $wafl_class };
                if ($not_cacheable_wafls{$wafl_class}) {
                    $expires_at = -1;
                    return;
                }

                my $unknown = 0;
                if ($wafl_class =~ m/(?:Image|File|InterWikiLink|HtmlPage|Toc|CSS)$/) {
                    my @args = $wafl->arguments =~ $wafl->wafl_reference_parse;
                    $args[0] ||= $self->workspace_name;
                    $args[1] ||= $self->page_id;
                    my ($ws_name, $page_id, $file_name) = @args;
                    $interwiki{$ws_name}++;
                    if ($file_name) {
                        my $attach_id = $wafl->get_file_id($ws_name, $page_id,
                            $file_name);
                        $attachments{
                            join ' ', $ws_name, $page_id, $file_name, $attach_id
                        }++;
                    }
                }
                elsif ($wafl_class =~ m/(?:TagLink|CategoryLink|WeblogLink|BlogLink)$/) {
                    my ($ws_name) = $wafl->parse_wafl_category;
                    $interwiki{$ws_name}++ if $ws_name;
                }
                elsif ($wafl_class eq 'Socialtext::FetchRSS::Wafl'
                    or $wafl_class eq 'Socialtext::VideoPlugin::Wafl'
                ) {
                    # Feeds and videos are cached for 1 hour, so we can cache this render for 1h
                    # There may be an edge case initially where a feed
                    # ends up getting cached for at most 2 hours if the Question
                    # had not yet been generated.
                    $wafl_expiry = 3600;
                }
                elsif ($wafl_class eq 'Socialtext::GoogleSearchPlugin::Wafl') {
                    # Cache google searches for 5 minutes
                    $wafl_expiry = 300;
                }
                elsif ($wafl_class eq 'Socialtext::Pluggable::WaflPhrase') {
                    if ($wafl->{method} eq 'user') {
                        $users{$wafl->{arguments}}++ if $wafl->{arguments};
                    }
                    elsif ($wafl->{method} eq 'hashtag') {
                        # Hashtags are just links, so they are cacheable.
                        return;
                    }
                    elsif ($wafl->{method} =~ m/^st_/) {
                        # All the agile plugin st_* wafls are not cacheable
                        $expires_at = -1;
                    }
                    else {
                        $unknown = 1;
                    }
                }
                elsif ($wafl_class eq 'Socialtext::Date::Wafl') {
                    # Must cache on date prefs
                    my $prefs = $self->hub->preferences_object;

                    # XXX We really only need to do this once per page.
                    push @cache_questions, {
                        date => join ',',
                            $prefs->date_display_format->value,
                            $prefs->time_display_12_24->value,
                            $prefs->time_display_seconds->value,
                            $prefs->timezone->value
                    };
                }
                elsif ($wafl_class eq 'Socialtext::Category::Wafl') {
                    if ($wafl->{method} =~ m/^(?:tag|category)_list$/) {
                        # We do not cache tag list views
                        $expires_at = -1;
                    }
                    else {
                        $unknown = 1;
                    }
                }
                else {
                    $unknown = 1;
                }

                if ($unknown) {
                    # For unknown wafls, set expiry to be a second ago so 
                    # the page is never cached.
                    warn "Unknown wafl phrase: " . ref($wafl) . ' - ' . $wafl->{method};
                    $expires_at = -1;
                }

                if ($wafl_expiry) {
                    # Keep track of the lowest expiry time.
                    if (!$expires_at or $expires_at > $wafl_expiry) {
                        $expires_at = $wafl_expiry;
                    }
                }
            },
            wafl_block => sub {
                my $wafl = shift;
                my $wafl_class = ref($wafl);
                return if $cacheable_wafls{ $wafl_class };
                if ($wafl->can('wafl_id') and $wafl->wafl_id eq 'html') {
                    $allows_html{$self->workspace_id}++;
                }
                else {
                    # Do not cache pages with unknown blocks present
                    $expires_at = -1;
                    warn "Unknown wafl block: " . ref($wafl);
                }
            },
        );
    }

    delete $interwiki{ $self->workspace_name };
    for my $ws_name (keys %interwiki) {
        my $ws = Socialtext::Workspace->new(name => $ws_name);
        push @cache_questions, { workspace => $ws } if $ws;
    }
    for my $ws_id (keys %allows_html) {
        my $ws = Socialtext::Workspace->new(workspace_id => $ws_id);
        push @cache_questions, { allows_html_wafl => $ws } if $ws;
    }
    for my $user_id (keys %users) {
        push @cache_questions, { user_id => $user_id };
    }
    for my $attachment (keys %attachments) {
        push @cache_questions, { attachment => $attachment };
    }
    if (defined $expires_at) {
        $expires_at += time();
        push @cache_questions, { expires_at => $expires_at };
    }
    
    eval {
        $html_ref = $self->_cache_using_questions( \@cache_questions, $html_ref );
    }; die "Failed to cache using questions: $@" if $@;

    return $html_ref;
}

sub _cache_using_questions {
    my $self = shift;
    my $questions = shift;
    my $html_ref = shift;

    my @short_q;
    my @answers;

    # Do one pass looking for expiry Q's, as they are cheap to early-out
    for my $q (@$questions) {
        if (my $t = $q->{expires_at}) {
            push @short_q, 'E' . $t;
            # We just made it, so it's not expired yet
            push @answers, 1;
        }
    }

    my $page_attachments;
    for my $q (@$questions) {
        my $ws;
        if ($ws = $q->{workspace}) {
            push @short_q, 'w' . $ws->workspace_id;
            push @answers, $self->hub->authz->user_has_permission_for_workspace(
                user => $self->hub->current_user,
                permission => ST_READ_PERM,
                workspace => $ws
            ) ? 1 : 0;
        }
        elsif (my $user_id = $q->{user_id}) {
            my $user = eval { Socialtext::User->Resolve($user_id) } or next;
            push @short_q, 'u' . $user->user_id;
            push @answers, 1; # All users are linkable.
        }
        elsif ($ws = $q->{allows_html_wafl}) {
            push @short_q, 'h' . $ws->workspace_id;
            push @answers, $ws->allows_html_wafl ? 1 : 0;
        }
        elsif (my $t = $q->{expires_at}) {
            # Skip, it's handled above.
        }
        elsif (my $d = $q->{date}) {
            push @short_q, 'd' . $d;
            push @answers, 1;
        }
        elsif (my $a = $q->{attachment}) {
            push @short_q, 'a' . $a;
            $a =~ m/^(\S+) (\S+) (.+) (\S+)$/;
            push @answers, $self->hub->attachments->attachment_exists(
                $1, $2, $3, $4);
        }
        else {
            require Data::Dumper;
            die "Unknown question: " . Data::Dumper::Dumper($q);
        }
    }

    my $q_str = join "\n", @short_q;
    $q_str ||= 'null';

    my $q_file = $self->_question_file or return;
    Socialtext::File::set_contents_utf8_atomic($q_file, \$q_str) if $q_file;

    $html_ref ||= \$self->to_html;

    # Check if we are the "current" page, and do not cache if we are not.
    # This is to avoid crazy errors where we may be rendering other page's
    # content for TOC wafls and such.
    my $cur_id = $self->hub->pages->current->page_id;
    return $html_ref unless (defined($cur_id) && $cur_id eq $self->page_id);

    my $answer_str = join '-', $self->_stock_answers(),
        map { $_ . '_' . shift(@answers) } @short_q;
    my $cache_file = $self->_answer_file($answer_str);
    Socialtext::File::set_contents_utf8_atomic($cache_file, $html_ref)
        if $cache_file;

    return $html_ref;
}

sub _users_modified_since {
    my $self = shift;
    my $q_str = shift;
    my $cached_at = shift;

    my @found_users;
    my @user_ids;
    while ($q_str =~ m/(?:^|-)u(\d+)(?:-|$)/gm) {
        push @user_ids, $1;
    }
    return 0 unless @user_ids;

    my $user_placeholders = '?,' x @user_ids; chop $user_placeholders;
    return sql_singlevalue(qq{
        SELECT count(user_id) FROM users
         WHERE user_id IN ($user_placeholders)
           AND last_profile_update >
                'epoch'::timestamptz + ?::interval
        }, @user_ids, $cached_at) || 0;
}

sub _stock_answers {
    my $self = shift;
    my @answers;

    # Which link dictionary is always the first question
    my $ld = ref($self->hub->viewer->link_dictionary);
    push @answers, $ld;

    # Which formatter is always the second question
    push @answers, ref($self->hub->formatter);

    # Which URI scheme is always the third question
    require Socialtext::URI;
    my %uri = Socialtext::URI::_scheme();
    push @answers, $uri{scheme};
    
    return @answers;
};

sub _questions_to_answers {
    my $self = shift;
    my $q_str = shift;

    my $t = time_scope('QtoA');
    my $cur_user = $self->hub->current_user;
    my $authz = $self->hub->authz;

    my @answers = $self->_stock_answers;

    for my $q (split "\n", $q_str) {
        if ($q =~ m/^w(\d+)$/) {
            my $ws = Socialtext::Workspace->new(workspace_id => $1);
            my $ok = $ws && $self->hub->authz->user_has_permission_for_workspace(
                user => $cur_user,
                permission => ST_READ_PERM,
                workspace => $ws,
            ) ? 1 : 0;
            push @answers, "${q}_$ok";
        }
        elsif ($q =~ m/^u(\d+)$/) {
            my $user = Socialtext::User->new(user_id => $1);
            push @answers, "${q}_1"; # All users are linkable
        }
        elsif ($q =~ m/^h(\d+)$/) {
            my $ws = Socialtext::Workspace->new(workspace_id => $1);
            my $ok = $ws && $ws->allows_html_wafl() ? 1 : 0;
            push @answers, "${q}_$ok";
        }
        elsif ($q =~ m/^E(\d+)$/) {
            my ($expires_at, $now) = ($1, time());
            my $ok = $now < $expires_at ? 1 : 0;
            warn "Checking Expiry ($now < $expires_at) = $ok" if $CACHING_DEBUG;
            return undef unless $ok;
            push @answers, "${q}_1";
        }
        elsif ($q =~ m/^d(.+)$/) {
            my $pref_str = $1;
            my $prefs = $self->hub->preferences_object;
            my $my_prefs = join ',',
                $prefs->date_display_format->value,
                $prefs->time_display_12_24->value,
                $prefs->time_display_seconds->value,
                $prefs->timezone->value;
            my $ok = $pref_str eq $my_prefs;
            push @answers, "${q}_$ok";
        }
        elsif ($q =~ m/^a(\S+) (\S+) (.+) (\S+)$/) {
            my $e = $self->hub->attachments->attachment_exists($1, $2, $3, $4);
            if ($e and !$4) {
                warn "Attachment $1/$2/$3 exists, but attachment_id is 0"
                    . " so we will re-generate the question" if $CACHING_DEBUG;
                return undef;
            }
            push @answers, "${q}_$e";
        }
        elsif ($q eq 'null') {
            next;
        }
        else {
            my $ws_name = $self->workspace_name;
            st_log->info("Unknown wikitext cache question '$q' for $ws_name/"
                    . $self->page_id);
            return undef;
        }
    }
    my $str = join '-', @answers;
    warn "Caching Answers: '$str'" if $CACHING_DEBUG;
    return $str;
}

sub _page_cache_basename {
    my $self = shift;
    my $cache_dir = $self->_cache_dir or return;
    return "$cache_dir/" . $self->page_id . '-' . ($self->revision_id || '0');
}

sub delete_cached_html {
    my $self = shift;
    unlink glob($self->_page_cache_basename . '-*');
}

sub _question_file {
    my $self = shift;
    my $base = $self->_page_cache_basename or return;
    return "$base-Q";
}

sub _answer_file {
    my $self = shift;

    # {bz: 4129}: Don't cache temporary pages during new_page creation.
    # XXX: this may be a little touchy with pages-in-the-db
    unless ($self->exists) {
        warn "Not caching new page" if $CACHING_DEBUG;
        return;
    }

    my $answer_str = shift || '';
    my $base = $self->_page_cache_basename;
    unless ($base) {
        warn "No _page_cache_basename, not caching";
        return;
    }

    # Turn SvUTF8 off before hashing the answer string. {bz: 4474}
    my $filename = "$base-".sha1_hex(Encode::encode_utf8($answer_str));
    (my $basename = $filename) =~ s#.+/##;
    warn "Answer file: $answer_str => $basename" if $CACHING_DEBUG;
    if (length($basename) > 254) {
        warn "Answer file basename is too long! - $basename";
        return undef;
    }
    return $filename;
}

sub _cache_dir {
    my $self = shift;
    return unless $self->hub;
    return $self->hub->viewer->parser->cache_dir(
        $self->workspace_id);
}

sub unindex {
    my ($self, $skip_atts) = @_;
    my @indexers = Socialtext::Search::AbstractFactory->GetIndexers(
        $self->workspace_name);
    my @atts = $self->attachments(deleted_ok => 1) unless $skip_atts;
    for my $indexer (@indexers) {
        $indexer->delete_page( $self->uri);
        next if $skip_atts;
        foreach my $attachment (@atts) {
            $indexer->delete_attachment($self->uri, $attachment->id);
        }
    }
}

sub delete {
    my $self = shift;
    my %p = @_;
    my $t = time_scope('page_delete');
    my $user = $p{user} || $self->hub->current_user;

    my $rev = $self->edit_rev(editor => $user);
    $rev->summary('');
    $rev->edit_summary('');
    $rev->body_ref(\'');
    $rev->deleted(1);
    $rev->tags([]);
    $self->store();

    $self->unindex();

    Socialtext::Events->Record({
        event_class => 'page',
        action => 'delete',
        page => $self,
    });
    return;
}

sub purge {
    my $self = shift;
    my $ws_id = $self->workspace_id;
    my $page_id = $self->page_id;

    my @atts = $self->attachments(deleted_ok => 1);
    $self->unindex('skip_atts'); # will get unindexed during $att->purge

    sql_txn {
        # these won't cascade when we delete the page row:
        for my $tbl (qw(page_tag page_revision)) {
            sql_execute(qq{
                DELETE FROM $tbl WHERE workspace_id = ? and page_id = ?
            }, $ws_id, $page_id);
        }

        # page_attachment won't cascade either, plus it further won't cascade
        # to the attachment row. purge it directly so the Upload also gets
        # cleaned up and logged
        $_->purge() for @atts;

        # if anything else references the page, this should cascade:
        sql_execute(qq{
            DELETE FROM page WHERE workspace_id = ? and page_id = ?
        }, $ws_id, $page_id);
    };
}

Readonly my $ExcerptLength => 350;
Readonly my $ExcerptLengthInput => 2 * $ExcerptLength;
sub preview_text {
    my $self = $_[0];
    my $content_ref;
    if (@_ == 2) {
        $content_ref = ref($_[1]) ? $_[1] : \$_[1];
    }
    $content_ref //= $self->body_ref;
    return '' unless $content_ref && length($$content_ref);

    return $self->preview_text_spreadsheet($content_ref)
        if $self->is_spreadsheet;

    # Gigantic pages caused Perl segfaults. Only need the beginning of the
    # content.
    if (length($$content_ref) > $ExcerptLengthInput) {
        my $content = substr($$content_ref, 0, $ExcerptLengthInput);
        $content =~ s/(.*\n).*/$1/s;
        $content_ref = \$content;
    }

    # Turn all newlines and tabs into plain spaces
    my $excerpt = $self->_to_plain_text($content_ref);
    $excerpt =~ s/^\s+//g;
    $excerpt =~ s/\s\s*/ /g;
    $excerpt =~ s/\s+\z//;

    $excerpt = substr($excerpt, 0, $ExcerptLength) . '...'
        if length $excerpt > $ExcerptLength;
    return html_escape($excerpt);
}

sub preview_text_spreadsheet {
    my $self = $_[0];
    my $content_ref = ref($_[1]) ? $_[1] : \$_[1];
    $content_ref //= $self->body_ref;

    my $excerpt = $self->_to_spreadsheet_plain_text($content_ref);
    $excerpt = substr($excerpt, 0, $ExcerptLength) . '...'
        if length $excerpt > $ExcerptLength;
    return html_escape($excerpt);
}

# also called by the Solr indexer
sub _to_plain_text {
    my $self = shift;
    my $content_ref = shift || $self->body_ref;

    if ($self->is_spreadsheet) {
        return $self->_to_spreadsheet_plain_text($content_ref);
    }

    if ($self->is_xhtml) {
        return $self->_to_xhtml_plain_text($content_ref);
    }

    # Why not go through the chunker? it's slower than returning when you use
    # a 'my' variable in-between.
    if (length $$content_ref < CHUNK_IT_UP_SIZE) {
        my $parser = Socialtext::WikiText::Parser->new(
           receiver => Socialtext::WikiText::Emitter::SearchSnippets->new,
        );
        return $parser->parse($$content_ref);
    }

    # It's too big! Take the hit and process it piecemeal
    my $plain_text = '';
    _chunk_it_up( $content_ref, sub {
        my $chunk_ref = shift;
        my $parser = Socialtext::WikiText::Parser->new(
           receiver => Socialtext::WikiText::Emitter::SearchSnippets->new,
        );
        eval { $plain_text .= $parser->parse($$chunk_ref) };
        warn $@ if $@;
    });
    return $plain_text;
}

sub _to_spreadsheet_plain_text {
    my $self = shift;
    my $content_ref = shift;
    require Socialtext::Sheet;
    require Socialtext::Sheet::Renderer;
    return Socialtext::Sheet::Renderer->new(
        sheet => Socialtext::Sheet->new(sheet_source => $content_ref),
        hub   => $self->hub,
    )->sheet_to_text();
}

sub _to_xhtml_plain_text {
    my $self = shift;
    my $content_ref = shift;
    require Socialtext::XHTML;
    require Socialtext::XHTML::Renderer;
    return Socialtext::XHTML::Renderer->new(
        xhtml => Socialtext::XHTML->new(xhtml_source => $content_ref),
        hub   => $self->hub,
    )->xhtml_to_text();
}

# REVIEW: We should consider throwing exceptions here rather than return codes.
sub duplicate {
    my $self = shift;
    my $dest_ws = shift;
    my $target_title = shift;
    my $keep_categories = shift;
    my $keep_attachments = shift;
    my $clobber = shift || '';
    my $is_rename = shift || 0;

    my $cur_ws = $self->hub->current_workspace;
    my $user = $self->hub->current_user;

    my ($dest_main, $dest_hub);
    if ($cur_ws->workspace_id != $dest_ws->workspace_id) {
        ($dest_main, $dest_hub) =
            $dest_ws->_main_and_hub($self->hub->current_user); 
    }
    else {
        $dest_hub = $self->hub;
    }

    my $target = $dest_hub->pages->new_from_name($target_title);
    my $rev = $target->edit_rev();
    my $body_ref = $self->body_ref;
    $rev->body_ref($body_ref);
    my $target_id = $target->page_id;

    # XXX need exception handling of better kind
    # Don't clobber an existing page if we aren't clobbering
    if ($target->active and $clobber ne $target_title) {
        return 0
    }

    # If the target page is the same as the source page, just rename
    if ($cur_ws->workspace_id == $dest_ws->workspace_id and $target_id eq $self->page_id) {
        return $self->rename(
            $target_title,
            $keep_categories,
            $keep_attachments,
            $clobber,
        );
    }

    return try { sql_txn {
        my $rev = $self->mutable
            ? $self->rev : $self->rev->mutable_clone(editor => $user);

        # Attach the mutable revision to the target page. Since most of the
        # properties will carry-over, we just need to modify the identity
        # fields.
        $rev->hub($dest_hub);
        $rev->workspace_id($dest_ws->workspace_id);
        $rev->page_id($target_id);
        $rev->name($target_title);

        # Make this the first revision_num unless we're clobbering.
        $rev->revision_num($target->exists ? $target->revision_num+1 : 0);
        $target->rev($rev);

        $rev->tags([]) unless $keep_categories;

        if ($keep_attachments) {
            my %target_attachments = map { $_->attachment_id => 1 }
                $target->attachments;
            for my $source_attachment ($self->attachments) {
                next if $target_attachments{$source_attachment->attachment_id};
                $source_attachment->clone(page => $target);
            }
        }

        $target->store(user => $dest_hub->current_user);
        $target->rev->clear_prev; # which still points to the old page

        Socialtext::Events->Record({
            event_class => 'page',
            action => ($is_rename ? 'rename' : 'duplicate'),
            page => $self,
            target_workspace => $dest_hub->current_workspace,
            target => $target,
        });

        Socialtext::Events->Record({
            event_class => 'page',
            action => 'edit_save',
            page => $target,
        });

        return 1;
    } }
    catch {
        carp "duplicate failed: $_";
        return 0;
    };
}

# REVIEW: We should consider throwing exceptions here rather than return codes.
sub rename {
    my $self = shift;
    my $new_page_title = shift;
    my $keep_categories = shift;
    my $keep_attachments = shift;
    my $clobber = shift || '';


    # If the new title of the page has the same page-id as the old then just
    # change the title, and don't mess with the other bits.
    my $new_id = title_to_id($new_page_title);
    if ( $self->page_id eq $new_id ) {
        return sql_txn {
            my $rev = $self->edit_rev();
            $rev->name($new_page_title);
            $self->store();
            return 1;
        };
    }

    return sql_txn {
        my $ok = $self->duplicate(
            $self->hub->current_workspace,
            $new_page_title,
            $keep_categories,
            $keep_attachments,
            $clobber,
            'rename'
        );
        return 0 unless $ok;

        my $localized_str = wiki2html(
            loc("page.renamed=title", $new_page_title)
        );
        my $rev = $self->edit_rev();
        $rev->body_ref(\$localized_str);
        $rev->page_type('xhtml');
        $self->store();

        return 1;
    };
}

# REVIEW: Candidate for Socialtext::Validate
sub _validate_has_addresses {
    my $self = shift;
    return (
        (not defined($_[0])) # May be undef
            or
        (not ref $_[0])      # or an address
            or
        (@{$_[0]} >= 1)      # or list of one or more addresses
    );
}

sub send_as_email {
    my $self = shift;
    my %p = validate(@_, {
        from => SCALAR_TYPE,
        to => {
            type => SCALAR | ARRAYREF | UNDEF, default => undef,
            callbacks => { 'has addresses or send_copy' => sub {
                my ($val, $params) = @_;
                $params->{send_copy} or $self->_validate_has_addresses(@_);
            } }
        },
        cc => {
            type => SCALAR | ARRAYREF | UNDEF, default => undef,
            callbacks => { 'has addresses' => sub { $self->_validate_has_addresses(@_) } }
        },
        subject => { type => SCALAR, default => $self->name },
        body_intro => { type => SCALAR, default => '' },
        include_attachments => { type => BOOLEAN, default => 0 },
        send_copy => { type => BOOLEAN, default => 0 },
    });
    
    # If send_copy is specified and no to address, make the
    # to address be equal to the from address
    if (!$p{to} && $p{send_copy}) {
        $p{to} = $p{from};
    }

    die "Must provide at least one address via the to or cc parameters"
      unless $p{to} || $p{cc};

    if ( $p{cc} and not $p{to} ) {
        $p{to} = $p{cc};
        delete $p{cc},
    }

    if ($p{send_copy}) {
        if ((!ref($p{to})) && ($p{from} ne $p{to})) {
            $p{to}=[$p{to}, $p{from}];
        } elsif ((ref($p{to}) eq "ARRAY") && 
            (! grep {$_ eq $p{from}} @{$p{to}})) {
            push(@{$p{to}}, $p{from});
        }
    }

    my $body_content;

    my $make_body_content = sub {
        if ($self->is_spreadsheet or $self->is_xhtml) {
            my $content = $self->to_absolute_html($self->body_ref);
            return $content unless $p{body_intro} =~ /\S/;
            my $intro = $self->hub->viewer->process($p{body_intro}, $self);
            return "$intro<hr/>$content";
        }

        local $DISABLE_CACHING = 1 if $p{body_intro};
        my $new_content = $p{body_intro} . ${$self->body_ref};
        return $self->to_absolute_html(\$new_content);
    };

    if ($p{include_attachments}) {
        my $prev_viewer = $self->hub->viewer;
        my $formatter = Socialtext::Pages::Formatter->new(hub => $self->hub);
        $self->hub->viewer->parser(
            Socialtext::Formatter::Parser->new(
                table => $formatter->table,
                wafl_table => $formatter->wafl_table
            )
        );
        $body_content = $make_body_content->();
        $self->hub->viewer($prev_viewer);
    }
    else {
        # If we don't have attachments, don't link to nonexistent "cid:" hrefs. {bz: 1418}
        $body_content = $make_body_content->();
    }

    my $html_body = $self->hub->template->render(
        'page_as_email.html',
        title        => $p{subject},
        body_content => $body_content,
    );

    my $text_body = Text::Autoformat::autoformat(
        $p{body_intro} . ($self->is_spreadsheet ? "\n" : $self->is_xhtml ? $self->_to_plain_text : $self->content), {
            all    => 1,
            # This won't actually work properly until the next version
            # of Text::Autoformat, as 1.13 has a bug.
            ignore =>
                 qr/# this regex is copied from Text::Autoformat ($ignore_indented)
                   (?:^[^\S\n].*(\n[^\S\n].*)*$)
                   |
                   # this matches table rows
                   (?:^\s*\|(?:(?:[^\|]*\|)+\n)+$)
                  /x,
        },
    );

    my %email = (
        to        => $p{to},
        subject   => $p{subject},
        from      => $p{from},
        text_body => $text_body,
        html_body => $html_body,
    );
    $email{cc} = $p{cc} if defined $p{cc};
    $email{attachments} = [ $self->attachments ] if $p{include_attachments};

    my $locale = system_locale();
    my $email_sender = Socialtext::EmailSender::Factory->create($locale);
    $email_sender->send(%email);
}

*is_in_category = *has_tag;

{
    Readonly my $spec => {
        revision_id => POSITIVE_FLOAT_TYPE,
        user        => USER_TYPE,
    };
    sub restore_revision {
        my $self = shift;
        my %p = validate( @_, $spec );

        $self->switch_rev($p{revision_id});
        my $num = $self->revision_num;

        my $rev = $self->edit_rev(editor => $p{user});

        # Give this rev a new ID, but use the old sequence number
        $rev->revision_num($num);
        $rev->revision_id(0);

        # Re-use the old revision's content. Marking the body not-modified
        # will trigger a row-to-row copy at the database level IFF the
        # editing-revision has a previous revision (which this one does).
        $rev->body_modified(0);
        $rev->edit_summary($rev->prev->edit_summary);
        $rev->summary($rev->prev->summary);

        $self->store(user => $p{user}, skip_rev_check => 1);

        # XXX TODO no events or logging for restore actions (by flawed design)
    }
}

sub edit_in_progress {
    my $self = shift;

    my $reporter = Socialtext::Events::Reporter->new(
        viewer => $self->hub->current_user,
    );

    my $yesterday = DateTime->now() - DateTime::Duration->new( days => 1 );
    my $events = $reporter->get_page_contention_events({
        page_workspace_id => $self->hub->current_workspace->workspace_id,
        page_id => $self->page_id,
        after  => $yesterday,
    }) || [];

    my $cur_rev = $self->revision_id;
    my @relevant_events;
    for my $evt (@$events) {
        last if $evt->{context}{revision_id} < $cur_rev;
        unshift @relevant_events, $evt;
    }

    my %open_edits;
    for my $evt (@relevant_events) {
        my $actor_id = $evt->{actor}{id};
        if ($evt->{action} eq 'edit_start') {
            if (my $e = $open_edits{ $actor_id }) {
                push @{ $open_edits{ $actor_id }}, $evt;
            }
            else {
                $open_edits{ $actor_id } = [ $evt ];
            }
        }

        if ($evt->{action} eq 'edit_cancel') {
            my $evts = $open_edits{ $actor_id };
            if ($evts) {
                pop @$evts;
                delete $open_edits{$actor_id} if @$evts == 0;
            }
            # otherwise ignore the cancel
        }
    }

    if (%open_edits) {
        my @edits = sort { $a->{at} cmp $b->{at} }
                    map { @{$open_edits{$_}} }
                    keys %open_edits;
        for my $evt (@edits) {
            my $user = Socialtext::User->new(user_id => $evt->{actor}{id});
            return {
                user_id => $user->user_id,
                username => $user->best_full_name,
                email_address => $user->email_address,
                user_business_card => $self->hub->pluggable->hook(
                    'template.user_business_card.content', [$user->user_id]),
                user_link => $self->hub->pluggable->hook(
                    'template.open_user_link.content', [$user->user_id]
                ),
                minutes_ago   => int((time - str2time($evt->{at})) / 60 ),
            };
        }
    }

    return undef;
}

sub formatted_date {
    # formats the current date/time in iso8601 format
    my $now = DateTime->now();
    my $fmt = DateTime::Format::Strptime->new( pattern => '%F %T %Z' );
    my $res = $fmt->format_datetime( $now );
    $res =~ s/UTC$/GMT/;    # refer to it as "GMT", not "UTC"
    return $res;
}

sub number_of_revisions {
    my $self = shift;

    my $count = sql_singlevalue(qq{
        SELECT count(revision_id)
          FROM page_revision
         WHERE workspace_id = ? AND page_id = ?
    }, $self->workspace_id, $self->page_id);
    return $count;
}

sub all_revision_ids {
    my $self = shift;
    my $order = shift || Socialtext::SQL::OLDEST_FIRST;

    $order = $order eq Socialtext::SQL::OLDEST_FIRST ? 'asc' : 'desc';
    my $sth = sql_execute(qq{
        SELECT
          revision_id
        FROM
          page_revision
        WHERE
          workspace_id = ?
        AND
          page_id = ?
        ORDER BY
          revision_id $order
    }, $self->workspace_id, $self->page_id);
    my @ids = map { $_->[0] } @{$sth->fetchall_arrayref || []};
    return @ids;
}

sub original_revision_id {
    my $self = shift;
    my $id = sql_singlevalue(qq{
        SELECT min(revision_id)
          FROM page_revision
         WHERE workspace_id = ? AND page_id = ?
         GROUP BY workspace_id, page_id
    }, $self->workspace_id, $self->page_id);
    return $id;
}

sub attachments {
    my ($self, @args) = @_;
    return @{$self->hub->attachments->all(
        @args, page => $self, page_id => $self->page_id)};
}

sub _log_page_action {
    my $self = shift;

    my $action = $self->hub->action || '';
    my $clobber = eval { $self->hub->rest->query->param('clobber') };

    return if $clobber
        || $action eq 'submit_comment'
        || $action eq 'attachments_upload';

    my $log_action;
    if ($action eq 'delete_page') {
        $log_action = 'DELETE';
    }
    elsif ($action eq 'rename_page') {
        $log_action = ($self->revision_count == 1) ? 'CREATE' : 'RENAME';
    }
    elsif ($action eq 'edit_content') {
        if ($self->restored) {
            $log_action = 'RESTORE';
        }
        elsif ($self->revision_count == 1) {
            $log_action = 'CREATE';
        }
        else {
            $log_action = 'EDIT';
        }
    }
    elsif ($action eq 'revision_restore') {
        $log_action = 'RESTORE';
    }
    elsif ($action eq 'undelete_page') {
        $log_action = 'RESTORE';
    }
    else {
        if ($self->revision_count == 1) {
            $log_action = 'CREATE';
        }
        else {
            $log_action = 'EDIT';
        }
    }

    my $user = $self->hub->current_user;
    st_log()->info("$log_action,PAGE,"
       . 'workspace:'.$self->workspace_name.'('.$self->workspace_id.'),'
       . 'page:'.$self->page_id.','
       . 'user:'.$user->username.'('.$user->user_id.'),'
       . '[NA]'
    );
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
