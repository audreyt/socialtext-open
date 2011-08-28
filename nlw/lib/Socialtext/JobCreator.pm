package Socialtext::JobCreator;
# @COPYRIGHT@
use MooseX::Singleton;
use MooseX::AttributeInflate;
use Socialtext::TheSchwartz;
use Socialtext::Search::AbstractFactory;
use Socialtext::SQL qw/:exec/;
use Carp qw/croak/;
use Socialtext::Log qw/st_log/;
use Socialtext::Cache ();
use namespace::clean -except => 'meta';

has_inflated '_client' => (
    is => 'ro', isa => 'Socialtext::TheSchwartz',
    lazy_build => 1,
    handles => qr/(?:list|find|get_server_time|func|move_jobs_by|cancel_job|bulk_insert)/,
);


sub insert {
    my $self = shift;
    my $job_class = shift;
    croak 'Job Class is required' unless $job_class;
    my $args = (@_==1) ? shift : {@_};
    $args->{job} ||= {};
    if ($job_class =~ /::Upgrade::/) {
        $args->{job}{priority} = -64 unless defined $args->{job}{priority};
    }
    return $self->_client->insert($job_class => $args);
}

sub index_attachment {
    my $self = shift;
    my $attachment = shift;
    my $search_config = shift;
    my %opts = @_;

    my $wksp_id = $attachment->workspace_id;
    my $page_id = $attachment->page_id;
    my $attach_id = $attachment->id;

    return if $attachment->is_temporary;

    return $self->index_attachment_by_ids(
        workspace_id => $wksp_id,
        page_id      => $page_id,
        attach_id    => $attach_id,
        config       => $search_config,
        %opts,
    );
}

sub index_attachment_by_ids {
    my $self = shift;
    my %p    = @_;
    my $wksp_id       = delete $p{workspace_id};
    my $page_id       = delete $p{page_id};
    my $attach_id     = delete $p{attach_id};
    my $priority      = delete $p{priority} || 63;
    my $search_config = delete $p{config};
    my $job_class     = delete $p{attachment_job_class}
                            || 'Socialtext::Job::AttachmentIndex';

    # order here is relevant: least-specific to most-specific:
    my $co_key = "$wksp_id-$page_id-$attach_id";

    return $self->insert($job_class => {
        workspace_id => $wksp_id,
        page_id => $page_id,
        attach_id => $attach_id,
        job => {
            priority => $priority,
            coalesce => $co_key,
        },
    });
}

sub index_page {
    my $self = shift;
    my $page = shift;
    my $search_config = shift;
    my %opts = (
        page_job_class => 'Socialtext::Job::PageIndex',
        @_,
    );
    

    return if $page->is_bad_page_title($page->id);

    my @job_ids;

    $opts{indexers} ||= [ 
        Socialtext::Search::AbstractFactory->GetIndexers(
            $page->hub->current_workspace->name,
        )
    ];

    my $wksp_id = $page->hub->current_workspace->workspace_id;
    my $page_id = $page->id;

    # order here is relevant: least-specific to most-specific:
    my $co_key = "$wksp_id-$page_id";

    my $job_id = $self->insert($opts{page_job_class} => {
        workspace_id => $wksp_id,
        page_id => $page_id,
        job => {
            priority => $opts{priority} || 63,
            coalesce => $co_key,
        },
    });
    push @job_ids, $job_id;

    my $attachments = $page->hub->attachments->all( page_id => $page->id );
    foreach my $attachment (@$attachments) {
        # We delete attachments immediately from the index (or file a job)
        # when they're removed from the page.
        next if $attachment->deleted();
        for my $indexer (@{ $opts{indexers} }) {
            my $job_id;
            if (ref($indexer) =~ m/solr/i) {
                $job_id = $self->index_attachment($attachment, 'solr', 
                    indexers => $opts{indexers},
                    attachment_job_class => $opts{attachment_job_class},
                    priority => $opts{priority},
                );
            }
            else {
                $job_id = $self->index_attachment($attachment, $search_config);
            }
            push @job_ids, $job_id;
        }
    }

    return @job_ids;
}

sub resolve_relationships {
    my $self     = shift;
    my %p        = @_;
    my $user_id  = $p{user_id};
    my $priority = $p{priority} || 50;
    return $self->insert('Socialtext::Job::ResolveRelationship', {
        user_id => $user_id,
        job => {
            priority => $priority,
            coalesce => $user_id,
        },
    } );
}

sub send_page_email {
    my $self = shift;
    my %opts = @_;

    return $self->insert( "Socialtext::Job::EmailPage" => \%opts );
}

sub send_page_notifications {
    my ($self,$page) = @_;
    return $self->_send_page_notifications($page, 
        [qw/WeblogPing EmailNotify WatchlistNotify/]);
}

sub send_page_watchlist_emails {
    my ($self,$page) = @_;
    return $self->_send_page_notifications($page, ['EmailNotify']);
}

sub send_page_email_notifications {
    my ($self,$page) = @_;
    return $self->_send_page_notifications($page, ['WatchlistNotify']);
}

sub _send_page_notifications {
    my $self = shift;
    my $page = shift;
    my $notification_tasks = shift; # array reference of notification tasks
    
    my $ws_id = $page->hub->current_workspace->workspace_id;
    my $page_id = $page->id;

    my @job_ids;

    for my $task (@$notification_tasks) {
        push @job_ids, $self->insert(
            "Socialtext::Job::$task" => {
                workspace_id => $ws_id,
                page_id => $page_id,
                modified_time => $page->modified_time,
                job => { uniqkey => "$ws_id-$page_id" },
            }
        );
    }
    return @job_ids;
}

sub index_signal {
    my $self = shift;
    my $signal_or_id = shift;
    my %p = @_;
    my $priority = delete $p{priority} || 70;

    # accept either a signal object or a signal id.
    my $id = (ref($signal_or_id) && $signal_or_id->isa('Socialtext::Signal'))
        ? $signal_or_id->signal_id
        : $signal_or_id;

    my $job_id = $self->insert(
        'Socialtext::Job::SignalIndex' => {
            %p,
            signal_id => $id,
            job => {
                priority => $priority,
                coalesce => $id,
            },
        }
    );
    return ($job_id);
}

sub index_group {
    my $self = shift;
    my $group_or_id = shift;
    my %p = @_;
    $p{priority} ||= 70;

    # accept either a group object or a group id.
    my $id = (ref($group_or_id) && $group_or_id->isa('Socialtext::Group'))
        ? $group_or_id->group_id
        : $group_or_id;

    my $job_id = $self->insert(
        'Socialtext::Job::GroupIndex' => {
            group_id => $id,
            job => {
                priority => $p{priority},
                coalesce => $id,
            },
        }
    );
    return ($job_id);
}

sub index_person {
    my $self = shift;
    my $maybe_user = shift;
    my %p = @_;
    $p{priority} ||= 70;

    my $user_id = ref($maybe_user) ? $maybe_user->user_id : $maybe_user;

    my $job_id;
    unless ($self->_cache('personindex')->get($user_id)) {
        $job_id = $self->insert(
            'Socialtext::Job::PersonIndex' => {
                user_id => $user_id,
                job => {
                    priority => $p{priority},
                    coalesce => $user_id,
                    ($p{run_after} ? (run_after => $p{run_after}) : ()),
                },
            }
        );
        $self->_cache('personindex')->set($user_id,1);
    }

    if ($p{name_is_changing}) {
        eval { $self->_index_related_people($maybe_user, $user_id, %p); };
        warn $@ if $@;
        eval { $self->_index_related_groups($user_id); };
        warn $@ if $@;
    }
    return ($job_id);
}

sub tidy_uploads {
    my ($self, $attachment_id) = @_;

    require Socialtext::Upload;
    $self->insert( 'Socialtext::Job::TidyUploads' => {
        attachment_id => $attachment_id,
        job => {
            run_after => time + Socialtext::Upload::TIDY_FREQUENCY(),
            coalesce => 'only',
            uniqkey => 'only',
            priority => -70, # VERY low
        },
    } );
}

sub _index_related_groups {
    my ($self, $user_id) = @_;

    my $sth = sql_execute(q{
        SELECT group_id FROM groups WHERE created_by_user_id = ?
        }, $user_id);
    while (my $row = $sth->fetchrow_arrayref) {
        $self->index_group($row->[0]);
    }
}

sub _index_related_people {
    my ($self, $maybe_user, $user_id, %p) = @_;
    local $@; # don't propagate
    my %to_reindex;
    require Socialtext::People::Profile;
    my $prof = Socialtext::People::Profile->GetProfile($maybe_user);
    my @attr_names = $prof->fields->relationship_names();
    for my $attr (@attr_names) {
        my $user_id = $prof->get_reln_id($attr);
        $to_reindex{$user_id} = 1 if $user_id;
    }
    for my $other_user_id (keys %to_reindex) {
        next if $self->_cache('personindex')->get($other_user_id);
        eval {
            $self->insert(
                'Socialtext::Job::PersonIndex' => {
                    user_id => $other_user_id,
                    job => {
                        priority => $p{priority},
                        coalesce => $other_user_id,
                        ($p{run_after} ? (run_after => $p{run_after}) : ()),
                    },
                }
            );
            $self->_cache('personindex')->set($other_user_id,1);
        };
    }
}

sub _cache {
    my $self = shift;
    my $kind = shift;
    return Socialtext::Cache->cache("jobcreator:$kind");
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
