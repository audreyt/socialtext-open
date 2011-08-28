package Socialtext::Job;
# @COPYRIGHT@
use Moose;
use TheSchwartz::Moosified::Worker;
use namespace::clean -except => 'meta';

# TS:M:W doesn't inherit from Moose::Object as of 0.005_05. To get constructor
# inlining to work properly under newer versions of Moose, we extend it here.
BEGIN {
    my @ext = 'TheSchwartz::Moosified::Worker';
    unshift @ext, 'Moose::Object'
        unless TheSchwartz::Moosified::Worker->isa('Moose::Object');
    extends @ext;
}

# By default, jobs are deemed to be "short running".
# XXX: this'd be *far* better done using MooseX::ClassAttribute
sub is_long_running { 0 }

has job => (
    is => 'rw', isa => 'TheSchwartz::Moosified::Job',
    handles => [qw(
        jobid funcname 
        arg uniqkey insert_time run_after grabbed_until priority coalesce
        permanent_failure failed completed replace_with
        exit_status failure_log failures
        as_hashref
    )],
);

has workspace => (
    is => 'ro', isa => 'Maybe[Socialtext::Workspace]',
    lazy_build => 1,
);

has account => (
    is => 'ro', isa => 'Maybe[Socialtext::Account]',
    lazy_build => 1,
);

has hub => (
    is => 'ro', isa => 'Maybe[Socialtext::Hub]',
    lazy_build => 1,
);

has indexer => (
    is => 'ro', isa => 'Object',
    lazy_build => 1,
);

has page => (
    is => 'ro', isa => 'Maybe[Socialtext::Page]',
    lazy_build => 1,
);

has signal => (
    is => 'ro', isa => 'Maybe[Socialtext::Signal]',
    lazy_build => 1,
);

has group => (
    is => 'ro', isa => 'Maybe[Socialtext::Group]',
    lazy_build => 1,
);

has user => (
    is => 'ro', isa => 'Maybe[Socialtext::User]',
    lazy_build => 1,
);

# These are called as class methods:
override 'keep_exit_status_for' => sub {60 * 60 * 24};
override 'grab_for'             => sub {3600};
override 'retry_delay'          => sub {0};
override 'max_retries'          => sub {0};

sub work {
    my $class = shift;
    my $job = shift;
    eval {
        my $self = $class->new(job => $job);
        $self->inflate_arg unless ref $self->arg;
        $self->do_work();
    };
    if ($@) {
        # make sure to record a result of 255
        $job->failed($@, 255);
        die $@;
    }
}

sub inflate_arg {
    my $self = shift;
    my $arg = $self->arg;
    return unless defined $arg;
    my (%kv) = split('-',$arg);
    $self->arg(\%kv);
}

sub _build_workspace {
    my $self = shift;
    my $ws_id = $self->arg->{workspace_id} || 0;

    require Socialtext::Workspace;

    return Socialtext::NoWorkspace->new() unless $ws_id;

    my $ws = Socialtext::Workspace->new(workspace_id => $ws_id);
    if (!$ws) {
        my $msg = "workspace id=$ws_id no longer exists";
        $self->permanent_failure($msg);
        die $msg;
    }

    $self->hub->current_workspace($ws) if $self->has_hub;
    return $ws;
}

sub _build_account {
    my $self = shift;
    my $account_id = $self->arg->{account_id} || return;

    require Socialtext::Account;

    my $account = Socialtext::Account->new(account_id => $account_id);
    if (!$account) {
        my $msg = "account id=$account_id no longer exists";
        $self->permanent_failure($msg);
        die $msg;
    }

    return $account;
}

sub _build_hub {
    my $self = shift;
    my $ws = $self->workspace or return;
    my $user = $self->user || Socialtext::User->SystemUser;

    require Socialtext;
    require Socialtext::User;

    my $main = Socialtext->new();
    $main->load_hub(
        current_workspace => $ws,
        current_user      => $user,
    );
    $main->hub()->registry()->load();

    return $main->hub;
}

sub _build_indexer {
    my $self = shift;

    my $ws = $self->workspace;

    require Socialtext::Search::Solr::Factory;

    my $indexer = Socialtext::Search::Solr::Factory->new->create_indexer(
            ($ws ? ($ws->name) : ()
        )
    );
    unless ($indexer) {
        my $err = $@ || 'unknown error';
        my $msg = "Couldn't create an indexer: $@";
        $self->permanent_failure($msg);
        die $msg;
    }
    return $indexer;
}

sub _build_page {
    my $self = shift;
    my $hub = $self->hub or return;
    my $page_id = $self->arg->{page_id};
    return unless $page_id;

    my $page = eval { $hub->pages->new_from_name($self->arg->{page_id}) };
    return $page if ($page && $page->exists); # checks filesystem

    my $msg = "Couldn't load page id=$page_id from the '" . 
        $hub->current_workspace->name .
        "' workspace: $@";
    $self->permanent_failure($msg);
    die $msg;
}

sub _build_signal {
    my $self = shift;
    my $signal_id = $self->arg->{signal_id};
    return unless $signal_id;

    require Socialtext::Signal;
    return eval { Socialtext::Signal->Get( signal_id => $signal_id ) };
}

sub _build_group {
    my $self = shift;
    my $group_id = $self->arg->{group_id};
    return unless $group_id;

    require Socialtext::Group;
    return eval { Socialtext::Group->GetGroup( group_id => $group_id ) };
}

sub _build_user {
    my $self = shift;
    my $user_id = $self->arg->{user_id};
    return unless $user_id;
    my $user = Socialtext::User->new(user_id => $user_id);
    $self->hub->current_user($user) if $self->has_hub;
    return $user;
}

sub to_hash {
    my $self = shift;
    my $hash = $self->as_hashref;
    $hash->{funcname} = $self->funcname;
    delete $hash->{funcid};
    return $hash;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
