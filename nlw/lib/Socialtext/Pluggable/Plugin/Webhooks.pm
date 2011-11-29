package Socialtext::Pluggable::Plugin::Webhooks;
# @COPYRIGHT@
use warnings;
use strict;
use Socialtext::WebHook;
use base 'Socialtext::Pluggable::Plugin';
use List::MoreUtils qw/all/;
use Socialtext::SQL qw(sql_timestamptz_now);

use constant scope => 'account';
use constant hidden => 1; # hidden to admins
use constant read_only => 0; # cannot be disabled/enabled in the control panel
use constant is_hook_enabled => 1;

sub register {
    my $self = shift;

    $self->add_hook("nlw.user.deactivate"       => \&deactivate_user);
    $self->add_hook("nlw.user.activate"         => \&activate_user);
    $self->add_hook("nlw.signal.new"            => \&signal_new);
    $self->add_hook("nlw.page.update"           => \&page_update);
    $self->add_hook("nlw.page.watch"            => \&page_watch);
    $self->add_hook("nlw.page.unwatch"          => \&page_unwatch);
    $self->add_hook("nlw.add_user_account_role" => \&user_account_join);
    $self->add_hook("nlw.remove_user_account_role" => \&user_account_leave);
    $self->add_hook("nlw.user.create"       => \&create_user);
}

sub create_user {
    my $self = shift;
    my $user = shift;

    my $user_hash = $user->to_hash();
    delete $user_hash->{password};
    Socialtext::WebHook->Add_webhooks(
        class => 'user.create',
        user => $user,
        payload_thunk => sub { 
            return {
                class => 'user.create',
                actor => {
                    id             => $self->user->user_id,
                    best_full_name => $self->user->best_full_name,
                },
                at     => sql_timestamptz_now(),
                object => $user_hash,
            };
        },
    );
}

sub user_account_leave {
    my $self = shift;
    my $account = shift;
    my $user = shift;
    my $role = shift;

    my $user_hash = $user->to_hash();
    delete $user_hash->{password};
    Socialtext::WebHook->Add_webhooks(
        class => 'user.leaveaccount',
        user => $user,
        payload_thunk => sub { 
            return {
                class => 'user.leaveaccount',
                actor => {
                    id             => $self->user->user_id,
                    best_full_name => $self->user->best_full_name,
                },
                at     => sql_timestamptz_now(),
                object => {
                    user => $user_hash,
                    account => $account->to_hash,
                    role => defined($role) ? $role->name : '',
                },
            };
        },
    );
}

sub user_account_join {
    my $self = shift;
    my $account = shift;
    my $user = shift;
    my $role = shift;

    my $user_hash = $user->to_hash();
    delete $user_hash->{password};
    Socialtext::WebHook->Add_webhooks(
        class => 'user.joinaccount',
        user => $user,
        payload_thunk => sub { 
            return {
                class => 'user.joinaccount',
                actor => {
                    id             => $self->user->user_id,
                    best_full_name => $self->user->best_full_name,
                },
                at     => sql_timestamptz_now(),
                object => {
                    user => $user_hash,
                    account => $account->to_hash,
                    role => defined($role) ? $role->name : '',
                },
            };
        },
    );
}

sub activate_user {
    my $self = shift;
    my $user = shift;

    my $user_hash = $user->to_hash();
    delete $user_hash->{password};
    Socialtext::WebHook->Add_webhooks(
        class => 'user.activate',
        user => $user,
        payload_thunk => sub { 
            return {
                class => 'user.activate',
                actor => {
                    id             => $self->user->user_id,
                    best_full_name => $self->user->best_full_name,
                },
                at     => sql_timestamptz_now(),
                object => $user_hash,
            };
        },
    );
}

sub deactivate_user {
    my $self = shift;
    my $user = shift;

    # Delete all webhooks created by this user
    $_->delete for @{ Socialtext::WebHook->Find(creator_id => $user->user_id) };

    my $user_hash = $user->to_hash();
    delete $user_hash->{password};
    Socialtext::WebHook->Add_webhooks(
        class => 'user.deactivate',
        user => $user,
        payload_thunk => sub { 
            return {
                class => 'user.deactivate',
                actor => {
                    id             => $self->user->user_id,
                    best_full_name => $self->user->best_full_name,
                },
                at     => sql_timestamptz_now(),
                object => $user_hash,
            };
        },
    );
}

sub signal_new {
    my ($self, $signal) = @_;

    Socialtext::WebHook->Add_webhooks(
        class => 'signal.create',
        signal => $signal,
        account_ids => $signal->account_ids,
        group_ids   => $signal->group_ids,
        tags        => $signal->tags,
        payload_thunk => sub { 
            return {
                class => 'signal.create',
                actor => {
                    id             => $signal->user->user_id,
                    best_full_name => $signal->user->best_full_name,
                },
                at     => $signal->at,
                object => {
                    id          => $signal->signal_id,
                    create_time => $signal->at,
                    attachments => [ $signal->attachments_as_hashes ],
                    uri         => $signal->uri,
                    group_ids   => $signal->group_ids || [],
                    account_ids => $signal->account_ids || [],
                    annotations => $signal->annotations || [],
                    topics      => [ $signal->topics_as_hashes ],
                    body        => $signal->body,
                    hash        => $signal->hash,
                    hidden      => $signal->is_hidden ? 1 : 0,
                    tags => [ map { $_->tag } @{ $signal->tags } ],
                    (
                        $signal->recipient_id
                        ? (recipient_id => $signal->recipient_id)
                        : (),
                    ),
                    (
                        $signal->in_reply_to ? (
                            in_reply_to => {
                                map { $_ => $signal->in_reply_to->$_ }
                                    qw(signal_id user_id uri)
                            }
                            )
                        : ()
                    ),
                },
            };
        },
    );
}

sub _fire_page_webhooks {
    my $self  = shift;
    my $class = shift;
    my $page  = shift;
    my %p     = @_;
    my $wksp  = $p{workspace} or die "workspace is mandatory!";
    my $tags_added = $p{tags_added} || [];
    my $tags_deleted = $p{tags_deleted} || [];

    my $thunk = sub {
        my %p = @_;
        my $editor = $page->last_editor;
        my $editor_blob = {
            id             => $editor->user_id,
            best_full_name => $editor->best_full_name,
        };
        return {
            class  => $p{class},
            actor  => $editor_blob,
            at     => $page->datetime_utc,
            object => {
                workspace => {
                    title => $wksp->title,
                    name  => $wksp->name,
                    id    => $wksp->workspace_id,
                },
                id           => $page->id,
                name         => $page->name,
                uri          => $page->full_uri,
                edit_summary => $page->edit_summary,
                tags         => $page->tags,
                tags_added   => $tags_added,
                tags_deleted => $tags_deleted,
                edit_time    => $page->datetime_utc,
                type         => $page->page_type,
                editor       => $editor_blob,
                create_time  => $page->createtime_utc,
                revision_count => $page->revision_count,
                revision_id    => $page->revision_id,
            }
        };
    };

    my %hook_opts = (
        account_ids   => [ $wksp->account->account_id ],
        workspace_id  => $wksp->workspace_id,
        tags          => $p{tags} || $page->tags,
        page_id       => $page->id,
        payload_thunk => $thunk,
    );

    # Main hook will also call the wildcard
    Socialtext::WebHook->Add_webhooks(
        %hook_opts, 
        wildcard => 'page.*',
        class => $class,
    );

    if (@$tags_added or @$tags_deleted) {
        Socialtext::WebHook->Add_webhooks(%hook_opts, class => 'page.tag');
    }

    if ($class eq 'page.create' or $class eq 'page.delete') {
        Socialtext::WebHook->Add_webhooks(%hook_opts, class => 'page.update');
    }
}

sub page_update {
    my ($self, $page, %p) = @_;

    my $class = 'page.update';
    if ($page->revision_count == 1) {
        $class = 'page.create';
        $p{tags_added} = $page->tags;
    }
    elsif ($page->deleted) {
        $class = 'page.delete';
        $p{tags} = $page->prev_rev->tags;
    }
    else {
        $class = 'page.create' if $page->restored;

        # Look for page tag changes
        my %prev_tags = $page->has_prev_rev ?
            (map { $_ => 1 } @{ $page->prev_rev->tags }) : ();
        my %now_tags  = map { $_ => 1 } @{ $page->tags };

        my (@added, @deleted);
        for my $t (keys %prev_tags) {
            next if $now_tags{$t};
            push @deleted, $t;
        }
        for my $t (keys %now_tags) {
            next if $prev_tags{$t};
            push @added, $t;
        }
        $p{tags_added} = \@added;
        $p{tags_deleted} = \@deleted;
    }

    $self->_fire_page_webhooks($class, $page, %p);
}

sub page_watch {
    my $self = shift;
    $self->_fire_page_webhooks('page.watch', @_);
}

sub page_unwatch {
    my $self = shift;
    $self->_fire_page_webhooks('page.unwatch', @_);
}

1;
__END__

=head1 NAME

Socialtext::Pluggable::Plugin::Webhooks

=head1 SYNOPSIS

Uses NLW hooks to fire Webhooks.

=head1 DESCRIPTION

=cut
