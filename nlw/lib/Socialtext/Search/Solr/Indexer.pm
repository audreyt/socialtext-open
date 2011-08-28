package Socialtext::Search::Solr::Indexer;
# @COPYRIGHT@
use Date::Parse qw(str2time);
use DateTime::Format::Pg;
use DateTime;
use Moose;
use MooseX::AttributeInflate;
use MooseX::AttributeHelpers;
use Socialtext::AppConfig;
use Socialtext::Timer qw/time_scope/;
use Socialtext::Hub;
use Socialtext::Workspace;
use Socialtext::Page;
use Socialtext::User;
use Socialtext::Attachment;
use Socialtext::Attachments;
use Socialtext::Log qw(st_log);
use Socialtext::Search::ContentTypes;
use Socialtext::Search::Utils;
use Socialtext::File;
use Socialtext::File::Stringify;
use WebService::Solr;
use Socialtext::WikiText::Parser::Messages;
use Socialtext::WikiText::Emitter::Messages::Solr;
use Socialtext::String qw(uri_escape);
use Socialtext::l10n qw(getSortKey);
use namespace::clean -except => 'meta';

=head1 NAME

Socialtext::Search::Solr::Indexer

=head1 SYNOPSIS

  my $i = Socialtext::Search::Solr::Factory->create_indexer($workspace_name);
  $i->index_workspace(...);
  $i->index_page(...);
  $i->index_attachment(...);

=head1 DESCRIPTION

Index documents using Solr;

=cut

extends 'Socialtext::Search::Indexer';
extends 'Socialtext::Search::Solr';

has '_docs' => (
    is => 'rw', isa => 'ArrayRef[WebService::Solr::Document]',
    metaclass => 'Collection::Array',
    default => sub { [] },
    provides => { 
        push => '_add_doc',
        clear => '_clear_docs',
    },
);

has 'always_commit' => (is => 'rw', isa => 'Bool', default => 1);

use constant FUDGE_ATTACH_REVS => 25;

######################
# Workspace Handlers
######################

# Make sure we're in a valid workspace, then recreate the index and get all
# the active pages, add each of them, and then add all the attachments on each
# page. 
sub index_workspace {
    my ( $self, $ws_name ) = @_;
    $self->delete_workspace($ws_name);
    _debug("Starting to retrieve page ids to index workspace.");
    for my $page_id ( $self->hub->pages->all_ids ) {
        my $page = $self->_load_page($page_id) || next;
        $self->_add_page_doc($page);
        $self->_index_page_attachments($page,0);
    }
    $self->_commit;
}

# Delete the index directory.
sub delete_workspace {
    my $self = shift;
    my $ws_name = shift || $self->ws_name;
    my $t = time_scope('solr_del_wksp');
    my $ws = Socialtext::Workspace->new(name => $ws_name);
    my $ws_id = $ws->workspace_id;
    
    $self->solr->delete_by_query("w:$ws_id");
    $self->_commit;
}

# Get all the active attachments on a given page and add them to the index.
sub _index_page_attachments {
    my ( $self, $page ) = @_;
    _debug( "Retrieving attachments from page: " . $page->id );
    my $attachments = $page->hub->attachments->all( page_id => $page->id );
    _debug( sprintf "Retreived %d attachments", scalar @$attachments );
    for my $attachment (@$attachments) {
        $self->_add_attachment_doc($attachment);
    }
}

##################
# Page Handling
##################

# Load up the page and add its content to the index.
sub index_page {
    my ( $self, $page_uri ) = @_;
    my $page = $self->_load_page($page_uri, 'deleted ok') || return;
    return $self->delete_page($page_uri) if $page->deleted;
    $self->_add_page_doc($page);
    $self->_commit;
}

# Remove the page from the index.
sub delete_page {
    my ( $self, $page_uri ) = @_;
    my $page = $self->_load_page($page_uri, 'deleted ok') || return;
    my $key = $self->page_key($page->id);
    $self->solr->delete_by_query("page_key:$key");
    $self->_commit;
}

# Create a new Document object and set it's fields.  Then delete the document
# from the index using 'key', which should be unique, and then add the
# document to the index.  The 'key' is just the page id.
sub _add_page_doc {
    my $self = shift;
    my $page = shift;
    my $t = time_scope('solr_page');

    my $ws_id = $self->workspace->workspace_id;
    my $id = join(':',$ws_id,$page->id);
    st_log->debug("Indexing page doc $id");

    my $editor_id = $page->last_edited_by->user_id;
    my $creator_id = $page->creator->user_id;

    my $revisions = $page->revision_count;

    my $body; {
        my $t = time_scope('solr_page_body');
        $body = $page->_to_plain_text;
        _scrub_field(\$body);
        $self->_truncate( $id, \$body );
    }
    my $title = $page->title;
    _scrub_field(\$title);

    my $tags = $page->tags;
    my @fields = (
        [id => $id], # composite of workspace and page
        # it is important to call this 'w' instead of 'workspace_id', because
        # we specify it many times for inter-workspace search, and we face 
        # lengths on the URI limit.
        [w => $ws_id],
        [w_title => $self->workspace->title],
        [doctype => 'page'], 
        [pagetype => $page->page_type],
        [page_key => $self->page_key($page->id)],
        [title => $title],
        [editor => $editor_id],
        [creator => $creator_id],
        [revisions => $revisions],
        [tag_count => scalar(@$tags) ],
        (map { [ tag => $_ ] } @$tags),
        Socialtext::Search::Solr::BigField->new(body => \$body),
    );
    if (my $mtime = _datetime_to_iso($page->last_edit_time)) {
        push @fields, [date => $mtime];
    }
    if (my $ctime = _datetime_to_iso($page->create_time)) {
        push @fields, [created => $ctime];
    }

    $self->_add_doc(WebService::Solr::Document->new(@fields));
}

sub page_key {
    my $self = shift;
    my $page_id = shift;

    join '__', $self->workspace->workspace_id, $page_id;
}

########################
# Attachment Handling
########################

# Load an attachment and then add it to the index.
sub index_attachment {
    my ( $self, $page_id, $attachment_or_id, $check_skip ) = @_;

    my $attachment = blessed($attachment_or_id)
        ? $attachment_or_id
        : $self->hub->attachments->load(
            id      => $attachment_or_id,
            page_id => $page_id,
        );
    my $attachment_id = $attachment->id;
    _debug("Loaded attachment: page_id=$page_id attachment_id=$attachment_id");

    if ($check_skip) {
        my $doc_id = join(':',
            $self->workspace->workspace_id,$page_id,$attachment_id);
        $doc_id = qq{"$doc_id"};
        my $resp = $self->solr->search("id:$doc_id", {fl=>'id',qt=>'standard'});
        my $docs = $resp->docs;
        if ($docs && @$docs == 1) {
            _debug("Skipping $attachment_id, doc id $doc_id already present");
            return;
        }
    }

    $self->_add_attachment_doc($attachment);
    $self->_commit();
}

# Remove an attachment from the index.
sub delete_attachment {
    my ( $self, $page_id, $attachment_id ) = @_;
    my $ws_id = $self->workspace->workspace_id;
    my $page = $self->_load_page($page_id, 'deleted ok') || return;
    my $doc_id = join(':',$ws_id,$page->id,$attachment_id);
    $self->solr->delete_by_id($doc_id);
    $self->_commit();
    _debug("Deleted attachment $doc_id");
}

# Get the attachments content, create a new Document, set the Doc's fields,
# and add the Document to the index.
sub _add_attachment_doc {
    my $self = shift;
    my $att = shift;
    my $t = time_scope('solr_add_attach');

    my $ws_id = $self->workspace->workspace_id;
    my $id = join(':',$ws_id,$att->page_id,$att->id);

    st_log->debug("Indexing attachment doc $id <".$att->filename.">");
    my $date = _datetime_to_iso($att->created_at);

    # XXX: this code assumes there's just one attachment revision
    # counteract the revisions boost by providing a dummy constant
    # XXX: This FUDGE is for the boost, but it doesn't make sense.
    my $revisions = FUDGE_ATTACH_REVS;

    my ($body, $key);
    {
        my $t = time_scope('solr_attach_body');
        $att->to_string(\$body,'temp');
        $key = $self->page_key($att->page_id);

        if (length $body) {
            _scrub_field(\$body);
            $self->_truncate( $id, \$body );
        }
    }

    _debug( "Retrieved attachment content.  Length is " . length $body );

    my $filename = $att->filename;
    (my $ext = $filename) =~ s/.+\.//;
    my @fields = (
        [id => $id],
        [w => $ws_id], 
        [w_title => $self->workspace->title],
        [doctype => 'attachment'],
        [page_key => $key],
        [attach_id => $att->id],
        [filename => $filename],
        [filename_ext => $ext],
        [editor => $att->editor_id],
        [creator => $att->creator_id],
        [date => $date],
        [created => $date],
        [revisions => $revisions],
        # NOTE if you add any more fields, check that the "skip indexing"
        # check in index_attachment() is still valid.
        Socialtext::Search::Solr::BigField->new(body => \$body),
    );

    $self->_add_doc(WebService::Solr::Document->new(@fields));
}

# See {link dev-tasks [Maximum File Size Cap]} for more
# information.
sub _truncate {
    my ( $self, $id, $text_ref ) = @_;
    my $max_size = Socialtext::AppConfig->stringify_max_length;
    return if length($$text_ref) <= $max_size;
    st_log()->info("Trimming $id from ".length($$text_ref)." to $max_size");
    _debug("Truncating text to $max_size characters: $id");
    substr($$text_ref, $max_size) = '';
    return;
}

##################
# Signal Handling
##################

sub index_signal {
    my ( $self, $signal ) = @_;
    return $self->delete_signal($signal->signal_id) if $signal->is_hidden;
    $self->_add_signal_doc($signal);
    $self->_commit;
}

# Remove the signal from the index.
sub delete_signal {
    my ( $self, $signal_id ) = @_;
    $self->solr->delete_by_query("signal_key:$signal_id");
    $self->_commit;
}

sub delete_signals {
    my $self = shift;
    $self->solr->delete_by_query("doctype:signal");
    $self->_commit;
}

# Create a new Document object and set it's fields.  Then delete the document
# from the index using 'key', which should be unique, and then add the
# document to the index.  The 'key' is just the signal id.
sub _add_signal_doc {
    my $self = shift;
    my $signal = shift;
    my $t = time_scope('solr_signal');

    my $id = "signal:" . $signal->signal_id;
    st_log->debug("Indexing doc $id");

    my $ctime = _pg_date_to_iso($signal->at);
    my $recip = $signal->recipient_id || 0;
    my @user_topics = $signal->user_topics;
    my ($body, $external_links, $page_links) = $self->render_signal_body($signal);
    _scrub_field(\$body);

    my $in_reply_to = $signal->in_reply_to;
    my $is_question = $body =~ m/\?\s*$/ ? 1 : 0;

    my $likes = $signal->likers;

    my @fields = (
        [id => $id],
        [doctype => 'signal'], 
        [signal_key => $signal->signal_id],
        [date => $ctime], [created => $ctime],
        [creator => $signal->user_id],
        [creator_name => $signal->user->best_full_name],
        [is_question => $is_question],
        [pvt => $recip ? 1 : 0],
        [dm_recip => $recip],
        (map { [a => $_] } @{ $signal->account_ids }),
        (map { [g => $_] } @{ $signal->group_ids }),
        ($in_reply_to ? [reply_to =>$in_reply_to->user_id] : ()),
        (map { [mention => $_->user_id] } @user_topics ),
        (map { [link_w => $_->[0]],
               [link_page_key => $_->[1]],
            } @$page_links),
        (map { [link => $_] } @$external_links),
        (map { [tag => $_->tag] } @{$signal->tags}),
        [ tag_count => scalar(@{$signal->tags}) ],
        Socialtext::Search::Solr::BigField->new('body' => \$body),
        [has_likes => 1],
        [like_count => scalar(@$likes) ],
        (map { [ like => $_ ] } @$likes),
    );

    for my $triplet (@{ $signal->annotation_triplets }) {
        push @fields, [annotation => lc join '|', @$triplet];
    }

    for my $attachment (@{ $signal->attachments }) {
        $self->_add_signal_attachment_doc($signal, $attachment);
    }

    $self->_add_doc(WebService::Solr::Document->new(@fields));
}

sub _add_signal_attachment_doc {
    my $self = shift;
    my $signal = shift;
    my $att = shift;
    my $t = time_scope('solr_signal_attachment');

    my $id = "signal:" . $signal->signal_id . ":filename:" . $att->filename;
    st_log->debug("Indexing doc $id");

    my $ctime = _pg_date_to_iso($signal->at);
    my $recip = $signal->recipient_id || 0;

    my $body; {
        my $t = time_scope('solr_attach_body');
        $att->to_string(\$body);
        _scrub_field(\$body);
        $self->_truncate( $id, \$body );
        _debug( "Retrieved attachment content.  Length is " . length $body );
    }

    (my $ext = $att->filename) =~ s/.+\.//;
    my @fields = (
        # These fields are mostly shared with the signal for visibility
        # and consistency reasons
        [id => $id],
        [signal_key => $signal->signal_id], # so delete deletes both
        [date => $ctime], [created => $ctime],
        [creator => $signal->user_id],
        [creator_name => $signal->user->best_full_name],
        [pvt => $recip ? 1 : 0],
        [dm_recip => $recip],
        (map { [a => $_] } @{ $signal->account_ids }),
        (map { [g => $_] } @{ $signal->group_ids }),
        [title => $att->filename],
        [filename => $att->filename],
        [filename_ext => $ext],
        [doctype => 'signal_attachment'], 
        Socialtext::Search::Solr::BigField->new(body => \$body),
    );
    $self->_add_doc(WebService::Solr::Document->new(@fields));
}


sub render_signal_body {
    my $self = shift;
    my $signal = shift;
    my $t = time_scope('solr_signal_body');

    my @external_links;
    my @page_links;
    my $parser = Socialtext::WikiText::Parser::Messages->new(
        receiver => Socialtext::WikiText::Emitter::Messages::Solr->new(
            callbacks => {
                href_link => sub {
                    my $ast = shift;
                    my $link = $ast->{attributes}{target};
                    push @external_links, $link;
                },
                noun_link => sub {
                    my $ast = shift;
                    my $wksp = Socialtext::Workspace->new(name => $ast->{workspace_id});
                    return unless $wksp;
                    my $wksp_id = $wksp->workspace_id;
                    my $pid = Socialtext::String::uri_unescape($ast->{page_id});
                    $pid = Socialtext::String::title_to_id($pid, 'no escape');
                    push @page_links, [ $wksp_id, "$wksp_id:$pid" ];
                },
            },
        ),
    );
    my $body = $parser->parse($signal->body);
    return $body, \@external_links, \@page_links;
}

##################
# Person Handling
##################

sub index_person {
    my ( $self, $user ) = @_;
    if (   $user->is_deleted
        or $user->is_profile_hidden
        or $user->is_system_created) {
        return $self->delete_person($user->user_id);
    }
    $self->_add_person_doc($user);
    $self->_commit;
}

# Remove the person from the index.
sub delete_person {
    my ( $self, $user_id ) = @_;
    $self->solr->delete_by_query("person_key:$user_id");
    $self->_commit;
}

sub delete_people {
    my $self = shift;
    $self->solr->delete_by_query("doctype:person");
    $self->_commit;
}

# Create a new Document object and set it's fields.  Then delete the document
# from the index using 'key', which should be unique, and then add the
# document to the index.  The 'key' is just the user id.
sub _add_person_doc {
    my $self = shift;
    my $user = shift;
    my $t = time_scope('solr_person');

    my $user_id = $user->user_id;
    st_log->debug("Indexing person $user_id");

    my @fields = (
        [id => "person:$user_id"],
        (map { [a => $_] } $user->accounts(ids_only => 1)),
        (map { [g => $_] } $user->groups(ids_only => 1)->all),
        [doctype => 'person'], 
        [person_key => $user_id],

        [first_name_pf_s => $user->first_name],
        [middle_name_pf_s => $user->middle_name],
        [last_name_pf_s => $user->last_name],
        [email_address_pf_s => $user->email_address],
        [username_pf_s => $user->username],
        # allow fuzzy/stem searching on the full name
        [name_pf_t => $user->proper_name],      # first/last
        [name_pf_t => $user->best_full_name],   # calculated; preferred, proper, guess
        # explicitly specify how we want to sort Users by name
        [name_asort => join '', map sprintf('%04X', $_), unpack("U*", getSortKey($user->best_full_name))],
    );

    my $profile = eval {
        Socialtext::People::Profile->GetProfile($user);
    };
    if ($profile) {
        my $mtime = _pg_date_to_iso($profile->last_update);
        push @fields, [date => $mtime];

        my @tags = map { [tag => $_] } keys %{$profile->tags};
        push @fields, @tags, [tag_count => scalar @tags];

        my $prof_fields = $profile->fields->to_hash;
        for my $field ($profile->fields->all) {
            # {bz 4836}: Don't index "preferred_name" if it is hidden.
            next if ($field->name eq 'preferred_name') and $field->is_hidden;
            my $solr_field = $field->solr_field_name;
            my $value;
            if ($field->is_relationship) {
                $value = $profile->get_reln_id($field->name) or next;
                if (my $other_user = Socialtext::User->new(user_id => $value)) {
                    my $bfn_field = $field->name . '_pf_rt';
                    push @fields, [$bfn_field => $other_user->best_full_name ];
                    my $uid_field = $field->name . '_pf_i';
                    push @fields, [$uid_field => $other_user->user_id ];
                }
                next;
            }
            else {
                $value = $profile->get_attr($field->name);
            }
            next unless defined $value;
            push @fields, [$solr_field => $value];
        }
    }

    $self->_add_doc(WebService::Solr::Document->new(@fields));
}


#################
# Group Handling
#################

sub index_group {
    my ( $self, $group ) = @_;
    $self->_add_group_doc($group);
    $self->_commit;
}

# Remove the group from the index.
sub delete_group {
    my ( $self, $group_id ) = @_;
    $self->solr->delete_by_query("group_key:$group_id");
    $self->_commit;
}

sub delete_groups {
    my $self = shift;
    $self->solr->delete_by_query("doctype:group");
    $self->_commit;
}

sub _add_group_doc {
    my $self = shift;
    my $group = shift;
    my $t = time_scope('solr_group');

    my $group_id = $group->group_id;
    st_log->debug("Indexing group $group_id");

    my @fields = (
        [id => "group:$group_id"],
        [g => $group_id],
        [doctype => 'group'], 
        [group_key => $group_id],
        [date => _datetime_to_iso()],
        [created => _datetime_to_iso($group->creation_datetime)],
        [creator => $group->created_by_user_id],
        [creator_name => $group->creator->display_name],
        [title => $group->display_name],
        [body => $group->description],
        [sounds_like => $group->display_name],
        [sounds_like => $group->description],
    );

    $self->_add_doc(WebService::Solr::Document->new(@fields));
}


#################
# Miscellaneous 
#################

# Given a page_id, retrieve the corresponding Page object.
sub _load_page {
    my ( $self, $page_id, $deleted_ok ) = @_;
    _debug("Loading $page_id");
    my $page = $self->hub->pages->By_id(
        hub => $self->hub,
        workspace_id => $self->hub->current_workspace->workspace_id,
        page_id => $page_id,
        deleted_ok => 1,
        no_die => 1,
    );
    unless ($page and $page->exists) {
        _debug("Could not load page $page_id");
    }
    unless (eval { $page->rev; 1 }) {
        _debug("Could not load latest page rev for $page_id");
    }
    if ( !$deleted_ok and $page->deleted ) {
        _debug("Page $page_id is deleted, skipping.");
        undef $page;
    }
    _debug("Finished loading $page_id");
    return $page;
}

# Send a debugging message to syslog.
sub _debug {
    my $msg = shift || "(no message)";
    $msg = __PACKAGE__ . ": $msg";
    st_log->debug($msg);
}

sub _pg_date_to_iso {
    my $pgdate = shift;
    return '1970-01-01T00:00:00Z' if $pgdate eq '-infinity';
    return '2038-01-01T00:00:00Z' if $pgdate eq 'infinity'; # XXX: Y2k38 bug
    $pgdate =~ s/Z$//;
    my $dt = DateTime::Format::Pg->new(
        server_tz => 'UTC',
    );
    my $utc_time = $dt->parse_timestamptz( $pgdate );
    # rounds to second:
    my $date = DateTime->from_epoch( epoch => $utc_time->epoch );
    $date->set_time_zone('UTC');
    return $date->iso8601 . 'Z';
}

sub _datetime_to_iso {
    my $date = shift || DateTime->now;
    $date->set_time_zone('UTC');
    return $date->iso8601 . 'Z';
}

sub _scrub_field {
    my $body_ref = shift;
    $$body_ref =~ s/[[:cntrl:]]+/ /g; # make Jetty happy
}

sub _commit {
    my $self = shift;
    my $docs = $self->_docs || [];

    if (@$docs) {
        st_log->debug('Adding '.@$docs.' documents to index');
        my $t2 = time_scope('solr_add');
        $self->solr->add($docs);
    }

    if ($self->always_commit) {
        my $t = time_scope('solr_commit');
        $self->solr->commit();
    }

    $self->_clear_docs;
}

__PACKAGE__->meta->make_immutable;
1;
