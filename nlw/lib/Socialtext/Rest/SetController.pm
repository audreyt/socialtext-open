package Socialtext::Rest::SetController;
# @COPYRIGHT@
use Moose;
use MooseX::StrictConstructor;
use Carp 'croak';
use Socialtext::Role;
use Socialtext::Exceptions qw(bad_request auth_error data_validation_error);
use Moose::Util::TypeConstraints qw(enum);
use List::MoreUtils 'none';
use namespace::clean -except => 'meta';

my @valid_actions = qw(add update remove); # 'skip' exists for internal use.
enum 'SetController.action' => @valid_actions;
my @valid_scopes  = qw(user group);
enum 'SetController.scope' => @valid_scopes;
my @valid_roles  = qw(admin member);
enum 'SetController.role' => @valid_roles;

has 'actor' => (
    is => 'ro', isa => 'Socialtext::User',
    required => 1,
);

has 'container' => (
    is => 'ro', isa => 'Socialtext::UserSetContainer',
    required => 1,
);

has 'scopes' => (
    is => 'rw', isa => 'ArrayRef[SetController.scope]',
    required => 1, default => sub { [@valid_scopes] },
    auto_deref => 1,
);

has 'actions' => (
    is => 'rw', isa => 'ArrayRef[SetController.action]',
    required => 1, default => sub { [@valid_actions] },
    auto_deref => 1,
);

has 'roles' => (
    is => 'rw', isa => 'ArrayRef[SetController.role]',
    required => 1, default => sub { [@valid_roles] },
    auto_deref => 1,
);

has 'hooks' => (
    is => 'rw', isa => 'HashRef[CodeRef]',
    required => 1, default => sub { +{} },
);

has 'self_action_only' => (is => 'rw', isa => 'Bool');

sub alter_members {
    my $self     = shift;
    my $requests = shift;

    for my $req (@$requests) {
        $self->alter_one_member($req);
    }
}

sub alter_one_member {
    my $self = shift;
    my @req  = (@_ == 1) ? %{$_[0]} : @_;

    data_validation_error "request is null" unless scalar(@req);

    my ($scope,$thing_key) = $self->request_scope(@req);

    if ($self->self_action_only) {
        bad_request "self-only mode only allowed for users"
            unless $scope eq 'user';
    }

    my $role   = $self->request_role(@req);
    my $thing  = $self->request_thing($thing_key, @req);
    my $action = $self->request_action($scope, $thing, $role);

    my $req = {object=>$thing, role=>$role, actor=>$self->actor};

    return undef if $action eq 'skip';

    # restrict roles a user can grant for 'add' and 'update' actions
    if ($action ne 'remove' && none { $_ eq $role->name } $self->roles ) {
        bad_request "you may only use roles: " . join(', ', $self->roles);
    }

    if    ($action eq 'add')    { $self->container->add_role($req) }
    elsif ($action eq 'remove') { $self->container->remove_role($req) }
    elsif ($action eq 'update') { $self->container->assign_role($req) }
    else { return } # do nothing

    return $self->run_post_hook($action, $scope, $req);
}

sub run_post_hook {
    my $self   = shift;
    my $scope  = shift;
    my $action = shift;
    my $req    = shift;

    my $hook_idx = join('_', 'post', $action, $scope);
    if ( my $hook = $self->hooks->{$hook_idx} ) {
        return $hook->($req);
    }
    return undef;
}

{
    my $realize = {
        username => sub { Socialtext::User->new(username => $_[0]) },
        user_id  => sub { Socialtext::User->new(user_id => $_[0]) },
        group_id => sub {
            eval{Socialtext::Group->GetGroup(group_id => $_[0])} },
    };

    sub request_thing {
        my $self  = shift;
        my $key   = shift;
        my %req   = @_;

        if ($self->self_action_only) {
            data_validation_error "can only act on users in self-action mode"
                unless ($key eq 'username' || $key eq 'user_id');
            auth_error "can only act on self"
                unless ($req{$key} eq $self->actor->$key);
            return $self->actor;
        }

        my $realizor = $realize->{$key};
        croak "cannot realize '$key : $req{$key}'" unless $realizor;

        my $thing = $realizor->($req{$key});
        data_validation_error "no result for '$key : $req{$key}'"
            unless $thing;
        return $thing;
    }
}

sub request_role {
    my $self = shift;
    my %req  = @_;

    my $role_name = $req{role_name};
    return unless $role_name;

    my $role = Socialtext::Role->new(name => $req{role_name});
    data_validation_error "no such role '$role_name'" unless $role;

    return $role;
}

sub request_action {
    my $self  = shift;
    my $scope = shift;
    my $thing = shift;
    my $role  = shift;

    my $has_role_id = $self->container->user_set->direct_object_role($thing);

    my $action;

    if ($has_role_id) {
        if (!$role) { $action = 'remove' }
        elsif ($has_role_id == $role->role_id) { $action = 'skip' }
        else { $action = 'update' }
    }
    else {
        $action = $role ? 'add' : 'skip';
    }


    auth_error "action '$action' is not allowed"
        unless $action eq 'skip' || grep { $action eq $_ } $self->actions;

    return $action;
}

{ 
    my $scopes_for_key = {
        user_id  => 'user',
        username => 'user',
        group_id => 'group',
    };

    sub request_scope {
        my $self = shift;
        my @req  = @_;

        for my $key (@req) {
            next unless $key;

            my $scope = $scopes_for_key->{$key};
            next unless $scope;

            auth_error "scope for key '$key' is illegal"
                unless grep { $_ eq $scope } $self->scopes;

            return ($scope => $key);
        }
        data_validation_error "no scope found for request";
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;

=head1 NAME

Socialtext::Rest::SetController - A generic interface for ReST interaction
with user sets.

=head1 SYNOPSIS

    use Socialtext::Rest::SetController;

    my $controller = Socialtext::Rest::SetController->new(
        container => $workspace,
        actor     => $user,
        scope     => 'user',
    );

    # Alter one user
    $controller->alter_one_member(
        user_id   => 13,
        role_name => 'member',
    );

    # Alter many users
    $controller->alter_members([
        { username => 'bob@example.com', role_name => 'member' },
        { user_id  => 15               , role_name => 'admin' },
        { user_id  => 21               , role_name => undef },
    ]);

=head1 DESCRIPTION

C<Socialtext::Rest::SetController> is a generic, easily-configurable interface
that can be used to build out ReST calls to a
C<Socialtext::UserSetContainer>'s sets, be they Users or Groups.

=cut
