package Socialtext::PageRevision;
use Moose;
use MooseX::StrictConstructor;
use Time::HiRes ();
use Carp qw/croak carp/;
use Moose::Util::TypeConstraints;
use Tie::IxHash;
use Try::Tiny;
use Socialtext::JSON qw/encode_json decode_json_utf8/;

use Socialtext::Moose::UserAttribute;
use Socialtext::MooseX::Types::Pg;
use Socialtext::MooseX::Types::UniStr;

use Socialtext::SQL qw/:exec :txn :time/;
use Socialtext::SQL::Builder qw/sql_nextval sql_insert/;
use Socialtext::Encode qw/ensure_is_utf8 ensure_ref_is_utf8/;
use Socialtext::String qw/title_to_id trim MAX_PAGE_ID_LEN/;
use Socialtext::Workspace;
use Socialtext::Exceptions qw/data_validation_error/;
use Socialtext::l10n;

use namespace::clean -except => 'meta';

with 'Socialtext::Annotations';

enum 'PageType' => qw(wiki spreadsheet);

has 'hub' => (is => 'rw', isa => 'Socialtext::Hub', weak_ref => 1);

# be careful to weaken if you add workspace/page lazy-accessors here:
has 'workspace_id' => (is => 'rw', isa => 'Int');
has 'page_id'      => (is => 'rw', isa => 'Str');
*id = *page_id; # legacy code uses this alias
has 'revision_id'  => (is => 'rw', isa => 'Num');

has 'revision_num' => (is => 'rw', isa => 'Int', default => 0);
has 'name'         => (is => 'rw', isa => 'UniStr', coerce => 1);

has_user 'editor' => (is => 'rw');
has 'edit_time'   => (
    is => 'rw', isa => 'Pg.DateTime',
    coerce => 1,
    default => sub { Socialtext::Date->now(hires=>1, timezone=>'GMT') },
);

has 'page_type' => (is => 'rw', isa => 'PageType', default => 'wiki');
has 'deleted'   => (is => 'rw', isa => 'Bool');
has 'locked'    => (is => 'rw', isa => 'Bool');

has $_ => (
    is => 'rw', isa => 'UniStr',
    coerce  => 1,
    default => '',
    clearer => 'clear_'.$_,
) for qw(summary edit_summary);

has 'tags' => (
    is => 'rw', isa => 'ArrayRef[Str]',
    default => sub {[]},
    trigger => sub { $_[0]->_tags_changed($_[1],$_[2]) },
);
has 'tag_set' => (
    is => 'rw', isa => 'Tie::IxHash',
    lazy_build => 1,
    writer => '_tag_set',
);

has 'body_ref' => (
    is => 'rw', isa => 'ScalarRef',
    lazy_build => 1,
    trigger => sub { $_[0]->_body_modded($_[1], $_[2]) }
);
has 'body_length'   => (is => 'rw', isa => 'Int', lazy_build => 1);
has 'body_modified' => (is => 'rw', isa => 'Bool');

has 'prev' => (
    is => 'rw', isa => 'Socialtext::PageRevision',
    predicate => 'has_prev',
    clearer => 'clear_prev',
    handles => {
        prev_revision_id  => 'revision_id',
        prev_revision_num => 'revision_num',
    },
);

# don't modify __mutable this outside of this package, please!
has 'mutable' => (
    is => 'rw', isa => 'Bool',
    writer => '__mutable',
    init_arg => '__mutable',
);

use constant COLUMNS => qw(
    workspace_id page_id revision_id revision_num name editor_id edit_time
    page_type deleted summary edit_summary locked tags body_length
    anno_blob
);
use constant COLUMNS_STR => join(', ',COLUMNS());
use constant SELECT_COLUMNS_STR => COLUMNS_STR.
    q{, edit_time AT TIME ZONE 'UTC' || 'Z' AS edit_time_utc};

around 'BUILDARGS' => sub {
    my $orig = shift;
    my $class = shift;
    my $args = shift;
    $args->{$_} //= '' for qw(summary edit_summary);
    return $orig->($class, $args);
};

sub Get {
    my $class = shift;
    my $p = ref($_[0]) ? $_[0] : {@_};
    
    my $hub = $p->{hub};
    croak "hub is required" unless $hub;
    croak "revision_id is required" unless $p->{revision_id};
    my $ws_id = $p->{workspace_id}
        || $hub->current_workspace->workspace_id;
    my $page_id = $p->{page_id}
        || $hub->pages->current->page_id;

    my $sth = sql_execute(q{
        SELECT }.SELECT_COLUMNS_STR.q{
          FROM page_revision
         WHERE workspace_id = ? AND page_id = ? AND revision_id = ?
    }, $ws_id, $page_id, $p->{revision_id});

    croak "unknown revision for page" unless $sth->rows == 1;
    my $row = $sth->fetchrow_hashref();
    $row->{edit_time} = delete $row->{edit_time_utc};
    $row->{hub} = $p->{hub};
    return $class->new($row);
}

sub Blank {
    my $class = shift;
    my %p = ref($_[0]) ? %{$_[0]} : @_;

    croak "hub is required to make a new revision" unless $p{hub};
    my $name = $p{name} // delete $p{title} //
        croak "name (a title) is required";

    my $hub = $p{hub};
    $p{workspace_id} = $hub->current_workspace->workspace_id;
    $p{name} = $name;
    $p{page_id} = title_to_id($name);
    $p{revision_id} = $p{revision_num} = 0;
    $p{editor} = $hub->current_user;
    $p{editor_id} = $p{editor}->user_id;
    $p{__mutable} = ($p{page_id} eq "_") ? 0 : 1;
    
    return Socialtext::PageRevision->new(\%p);
}

sub _build_anno_blob {
    my $self = shift;

    my $rev_id = $self->revision_id;

    my $blob;
    if (!$rev_id && $self->has_prev) {
        if ($self->prev->has_body_ref) {
            $blob = $self->prev->anno_blob;
        }
        else {
            $rev_id = $self->prev->revision_id;
        }
    }

    if ($rev_id && !defined($blob)) {
        $blob = sql_singlevalue(q{
            SELECT anno_blob FROM page_revision
             WHERE workspace_id = $1 AND page_id = $2 AND revision_id = $3
        }, $self->workspace_id, $self->page_id, $rev_id);
    }

    $blob = '[]' unless defined $blob;
    Encode::_utf8_on($blob); # it should always be in the db as utf8

    return $blob;
}

sub _get_blob {
    my $self = shift;
    my $rev_id = $self->revision_id;

    my $blob;
    if (!$rev_id && $self->has_prev) {
        if ($self->prev->has_body_ref) {
            $blob = ${$self->prev->body_ref}; # copy bytes
        }
        else {
            $rev_id = $self->prev->revision_id;
        }
    }

    if ($rev_id && !defined($blob)) {
        sql_singleblob(\$blob, q{
            SELECT body FROM page_revision
             WHERE workspace_id = $1 AND page_id = $2 AND revision_id = $3
        }, $self->workspace_id, $self->page_id, $rev_id);
    }

    $blob = '' unless defined $blob;
    Encode::_utf8_on($blob); # it should always be in the db as utf8

    return \$blob;
}

sub _build_body_length {
    my $self = shift;
    my $blobref;
    if ($self->has_body_ref) {
        # this branch shouldn't happen, but is here for defense
        $blobref = $self->body_ref;
    }
    else {
        $blobref = $self->_get_blob();
        # break Moose encapsulation to avoid trigger:
        $self->{body_ref} = $blobref;
    }
    return length $$blobref;
}

sub _build_body_ref {
    my $self = shift;
    my $blobref = $self->_get_blob();
    $self->body_length(length($$blobref));
    return $blobref;
}

sub _body_modded {
    my ($self, $newref, $oldref) = @_;
    confess "body modified while PageRevision wasn't mutable"
        unless $self->mutable;

    try {
        unless ($newref && defined $$newref &&
                Encode::is_utf8($$newref, Encode::FB_CROAK | Encode::LEAVE_SRC))
        {
            try {
                $$newref = Encode::decode_utf8($$newref, Encode::FB_CROAK | Encode::LEAVE_SRC);
            }
            catch {
                die $_ unless /Modification of a read-?only value/;
                my $decoded = Encode::decode_utf8($$newref, Encode::FB_CROAK | Encode::LEAVE_SRC);
                $newref = \$decoded;
                # XXX: break Moose encapsulation so we don't recurse:
                $self->{body_ref} = $newref;
            };
        }
    }
    catch {
        confess "body is not encoded as valid utf8: $_";
    };

    $self->body_modified((defined($newref) || defined($oldref))? 1 : undef);
    $self->clear_summary();
    if ($newref && defined $$newref) {
        $self->body_length(length $$newref);
    }
    return;
}

sub pkey {
    my $self = shift;
    return map { $self->$_ } qw(workspace_id page_id revision_id);
}

sub modified_time { $_[0]->edit_time->epoch };

sub mutable_clone {
    my $self = shift;
    my $p = ref($_[0]) ? $_[0] : {@_};
    confess "PageRevision is already mutable" if $self->mutable;
    confess "The '_' page cannot be made mutable" if $self->page_id eq '_';

    $p->{editor} //= $self->hub->current_user;

    # NOTE: exists breaks Moose encapsulation, but gets the job done in lieu
    # of defining predicates for everything
    my %clone_args = map { $_ => $self->$_ }
        grep { exists $self->{$_} }
        qw(page_id workspace_id revision_num name page_type deleted
            locked summary body_length);

    $clone_args{revision_id} = 0;
    $clone_args{revision_num}++;
    $clone_args{tags} = [@{$self->tags}]; # semi-deep copy

    if ($p->{copy_body}) {
        my $body = ${$self->body_ref}; # copy the bytes
        $clone_args{body_ref} = \$body; # will cause trigger to run
        $clone_args{body_length} = $self->body_length;
        $clone_args{edit_summary} = $self->edit_summary if $self->edit_summary;
    }

    $clone_args{prev} = $self;
    $clone_args{hub} = $self->hub;
    $clone_args{editor_id} = $p->{editor}->user_id;
    $clone_args{editor} = $p->{editor};
    $clone_args{edit_time} = $p->{edit_time} if $p->{edit_time};
    $clone_args{__mutable} = 1;
    return Socialtext::PageRevision->new(\%clone_args);
}

sub _build_tag_set {
    my $self = shift;
    return Tie::IxHash->new(
        map { my $x=$_; lc(ensure_is_utf8($x)) => $x } @{shift || $self->tags}
    );
}

sub _tags_changed {
    my ($self, $new_tags, $old_tags) = @_;

    # Should only have $old_tags *after* construction. This is just a sanity
    # check anyhow.
    confess "PageRevision isn't mutable" if $old_tags && !$self->mutable;

    $self->clear_tag_set;
    return unless $new_tags && @$new_tags;

    my $set = Tie::IxHash->new;
    for my $tag (@$new_tags) {
        ensure_ref_is_utf8(\$tag);
        my $lc_tag = lc($tag);
        next if $set->EXISTS($lc_tag);
        $set->Push($lc_tag => $tag);
    }
    @{$self->tags} = $set->Values();
    $self->_tag_set($set);
    return $self->tags;
}

*add_tag = *add_tags;
sub add_tags {
    my $self = shift;
    my $add = ref($_[0]) ? $_[0] : [@_];
    confess "PageRevision isn't mutable" unless $self->mutable;
    my $set = $self->tag_set;
    my $tags = $self->tags;
    my @added;
    for my $tag (@$add) {
        my $lc_tag = lc(ensure_is_utf8($tag));
        next if $set->EXISTS($lc_tag);
        $set->Push($lc_tag => $tag);
        push @added, $tag;
    }
    @$tags = $set->Values();
    return \@added;
}

*delete_tag = *delete_tags;
sub delete_tags {
    my $self = shift;
    my $del = ref($_[0]) ? $_[0] : [@_];
    confess "PageRevision isn't mutable" unless $self->mutable;
    my $set = $self->tag_set;
    my $tags = $self->tags;
    my @deleted;
    for my $tag (@$del) {
        my $lc_tag = lc(ensure_is_utf8($tag));
        my $was = $set->Delete($lc_tag);
        push @deleted, $was if defined $was;
    }
    @$tags = $set->Values();
    return \@deleted;
}

sub has_tag {
    my $self = shift;
    my $tag = shift;
    my $lc_tag = lc(ensure_is_utf8($tag));
    return $self->tag_set->FETCH($lc_tag);
}

sub tags_sorted {
    my $self = shift;
    return lsort @{$self->tags};
}

sub is_recently_modified {
    my $self = shift;
    my $limit = shift || 3600; # 1hr
    return $self->age_in_seconds < $limit;
}

sub age_in_minutes {
    my $self = shift;
    $self->age_in_seconds / 60;
}

has 'age_in_seconds' => (is => 'ro', isa => 'Int', lazy_build => 1);
sub _build_age_in_seconds {
    my $self = shift;
    my $time = $Socialtext::Page::REFERENCE_TIME || time;
    return $time - $self->modified_time;
}

sub age_in_english {
    my $self = shift;
    my $age = $self->age_in_seconds;
    my $english =
        $age < 60 ? loc('time.seconds=count', $age) :
        $age < 3600 ? loc('time.minutes=count', int($age / 60)) :
        $age < 86400 ? loc('time.hours=count', int($age / 3600)) :
        $age < 604800 ? loc('time.days=count', int($age / 86400)) :
        $age < 2592000 ? loc('time.weeks=count', int($age / 604800)) :
        loc('time.months=count', int($age / 2592000));
    $english =~ s/^(1 .*)s$/$1/;
    return $english;
}

sub is_spreadsheet { $_[0]->page_type eq 'spreadsheet' }
sub is_wiki { $_[0]->page_type eq 'wiki' }

sub is_untitled {
    my $class_or_self = shift;
    my $id = shift || $class_or_self->page_id;
    if ($id eq 'untitled_page') {
        return 'Untitled Page';
    }
    elsif ($id eq 'untitled_spreadsheet') {
        return 'Untitled Spreadsheet';
    }
    return '';
}

sub is_bad_page_title {
    my ( $class_or_self, $title ) = @_;
    $title = defined($title) ? $title : "";

    # No empty page titles.
    return 1 if $title =~ /^\s*$/;
    my $id = title_to_id($title);

    return 1 if $class_or_self->is_untitled($id); # unlocalized

    # Can't have a page named "Untitled Page" in the current locale
    my $untitled_page = title_to_id( loc("page.untitled") );
    return 1 if $id eq $untitled_page;
    my $untitled_spreadsheet = title_to_id( loc("sheet.untitled") );
    return 1 if $id eq $untitled_spreadsheet;

    return 0;
}

sub datetime_for_user {
    my $self = shift;
    return $self->hub->timezone->get_date_user($self->edit_time);
}

sub datetime_utc {
    my $self = shift;
    return $self->edit_time->strftime('%Y-%m-%d %H:%M:%S GMT');
}

# For overriding in tests, and potentially for providing legacy-compatible IDs
our $NextRevisionID;
sub next_revision_id {
    return $NextRevisionID++ if defined $NextRevisionID;

    my $hires = Time::HiRes::time();
    $hires =~ m/^(\d+)(?:\.(\d{0,5})\d*)?$/;
    my ($time, $fractional) = ($1, $2||0);
    my ($sec, $min, $hour, $mday, $mon, $year) = gmtime($time);
    my $id = sprintf(
        "%4d%02d%02d%02d%02d%02d.$fractional",
        $year + 1900, $mon + 1, $mday, $hour, $min, $sec
    );
    return $id;
}

sub store {
    my $self = shift;
    confess "PageRevision isn't mutable" unless $self->mutable;
    # XXX extra caution, but should be a database-level constraint
    confess "Can't store the '_' page_id" if $self->page_id eq '_';

    my @errors;

    # Putting whacky whitespace in a page title can kill javascript on the
    # front-end. This fixes {bz: 3475}.
    {
        my $name = $self->name;
        $name =~ s/\s+/ /g; $name =~ s/^ //; $name =~ s/ $//;
        $self->name($name);
    }

    my $name_check = title_to_id($self->name); 
    push @errors, loc("error.page-id-mismatch")
        unless $self->page_id eq $name_check;

    # Fix for {bz 2099} -- guard against storing an "Untitled Page".
    if (my $display_name = $self->is_untitled) {
        push @errors, loc('error.reserved-name=page', $display_name);
    }

    if ($self->is_bad_page_title($self->name)) {
        push @errors, loc('error.invalid-title=page', $self->name);
    }

    if (MAX_PAGE_ID_LEN < length($self->page_id)) {
        push @errors, loc("error.page-title-too-long");
    }

    Socialtext::Exception::DataValidation->throw(
        error => loc("error.store-revision"),
        errors => \@errors
    ) if @errors;

    for (qw(edit_summary summary)) {
        $self->$_(trim($self->$_)) if defined $self->$_;
    }

    my %args = map { $_ => $self->$_ } Socialtext::PageRevision::COLUMNS();
    $args{$_} = $args{$_} ? 1 : 0 for qw(locked deleted);
    $args{edit_time} = sql_format_timestamptz($args{edit_time});

    my $body;
    if ($self->body_modified) {
        $body = $self->body_ref;
        $args{body_length} = length($$body);
    }
    elsif (!$self->has_prev) {
        my $x = '';
        $self->body_ref(\$x);
        $body = $self->body_ref;
        $self->summary('');
        $args{body_length} = 0;
    }
    else {
        # reuse the previous revision's body, copying at the Pg-level
        $args{body_length} = -1;
    }

    sql_txn {
        # paranoia: never insert with zeros for either of these two:
        $args{revision_id} ||= next_revision_id();
        $args{revision_num} ||= 1;

        sql_insert(page_revision => \%args);

        if ($body) {
            # copy blob from Perl
            sql_saveblob($body, q{
                UPDATE page_revision SET body = $1
                 WHERE workspace_id = $2 AND page_id = $3 AND revision_id = $4
            }, @args{qw(workspace_id page_id revision_id)});
        }
        else {
            # copy blob from Pg
            my $prev = $self->prev;
            sql_execute(q{
                UPDATE page_revision
                  SET body = old_rev.body,
                      body_length = old_rev.body_length
                 FROM (
                     SELECT body, body_length
                       FROM page_revision
                      WHERE workspace_id = $1 AND page_id = $2
                        AND revision_id = $3
                 ) old_rev
                WHERE workspace_id = $4 AND page_id = $5
                  AND revision_id = $6
            }, $prev->workspace_id, $prev->page_id, $prev->revision_id,
               @args{qw(workspace_id page_id revision_id)});
        }
    };

    $self->revision_id($args{revision_id});
    $self->revision_num($args{revision_num});
    $self->body_modified(0);
    $self->clear_tag_set;
    $self->__mutable(0);

    return $self;
}

sub Export_to_file_from_row {
    my ($class, $row, $fh) = @_;

    my $editor_email =
        Socialtext::User->new(user_id => $row->{editor_id})->email_address;
    $row->{edit_time_utc} =~ s/Z$/ GMT/;
    $row->{summary} //= '';
    $row->{summary} =~ s/\n//g;
    $row->{edit_summary} //= '';
    $row->{edit_summary} =~ s/\n//g;
    $row->{anno_blob} //= '[]';

    print $fh <<EOH;
Subject: $row->{name}
From: $editor_email
Date: $row->{edit_time_utc}
Revision: $row->{revision_num}
Type: $row->{page_type}
Summary: $row->{summary}
RevisionSummary: $row->{edit_summary}
anno_blob: $row->{anno_blob}
Encoding: utf8
EOH
    print $fh "Locked: 1\n" if $row->{locked};
    print $fh "Control: Deleted\n" if $row->{deleted};
    print $fh "Category: $_\n" for @{$row->{tags}};
    print $fh "\n";

    my $blob;
    sql_singleblob(\$blob, q{
        SELECT body FROM page_revision
         WHERE workspace_id = $1 AND page_id = $2 AND revision_id = $3
    }, @$row{qw(workspace_id page_id revision_id)});
    Encode::_utf8_on($blob); # always on for rev-blobs as BYTEA
    print $fh $blob;

    return;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

__END__

=head1 NAME

Socialtext::PageRevision - Page revision object

=head1 SYNOPSIS

  my $page = ...
  $rev = $page->edit_rev(editor => $user);
  $rev->body_ref(\$new_content);
  $rev->summary($new_summary);
  $rev->add_tags($tags_without_events_fired);
  $page->store();

=head1 DESCRIPTION

Encapsulates a revision for a page.  You probably want to use the methods and
accessors via L<Socialtext::Page> instead.

=cut
