package Socialtext::Rest::Workspaces;
# @COPYRIGHT@

use warnings;
use strict;

use base 'Socialtext::Rest::Collection';

use Socialtext::JSON;
use Socialtext::HTTP ':codes';
use Socialtext::Permission;
use Socialtext::SQL ':txn';
use Socialtext::Workspace;
use Socialtext::Account;
use Socialtext::Exceptions qw(param_error);
use Socialtext::User;
use Socialtext::Group;
use Socialtext::Permission 'ST_ADMIN_PERM';
use Socialtext::Workspace::Permissions;
use Socialtext::JobCreator;
use Socialtext::AppConfig;
use Socialtext::Timer;
use Socialtext::l10n 'loc';

# Anybody can see these, since they are just the list of workspaces the user
# has 'selected'.
sub permission { +{} }

sub _initialize {
    my ( $self, $rest, $params ) = @_;

    $self->SUPER::_initialize($rest, $params);

    $self->{FilterParameters}->{'title_filter'} = 'title';
}


sub collection_name {
    'Workspaces';
}

sub _entities_for_query {
    my $self = shift;
    my $rest = $self->rest;

    my $query = $rest->query->param('q');
    my $minimal = $rest->query->param('minimal');
    my $set_filter = $rest->query->param('permission_set');
    my $name_filter = $rest->query->param('name_filter');
    my $user  = $rest->user();

    if ($set_filter) {
        param_error "permission_set is invalid" if
            !Socialtext::Workspace::Permissions->SetNameIsValid($set_filter);
    }

    # REVIEW: 'all' should only work for some super authenticate user,
    # but which one? business admin seems right
    my $fetch_all = defined $query && $query eq 'all'
        && $user->is_business_admin;

    my $workspaces;
    if ($fetch_all) {
        if ($name_filter) {
            my $offset = $rest->query->param('offset');
            my $limit = ($rest->query->param('limit') || $rest->query->param('count'));
            $workspaces = Socialtext::Workspace->ByName(
                case_insensitive => 1,
                name => $name_filter,
                ((defined $limit) ? (limit => $limit) : ()),
                ((defined $offset) ? (offset => $offset) : ()),
            )
        }
        else {
            $workspaces = Socialtext::Workspace->All();
        }
    }
    else {
        $workspaces = $rest->user->workspaces( minimal => $minimal );
    }

    if ($set_filter && !$minimal) { # can't do this for minimal
        $workspaces = Socialtext::MultiCursorFilter->new(
            cursor => $workspaces,
            filter => sub {
                shift->permissions->current_set_name eq $set_filter},
        );
    }

    return $workspaces->all();
}

sub _entity_hash {
    my $self      = shift;
    my $workspace = shift;

    Socialtext::Timer->Continue('entity_hash');
    $self->{__default_ws} ||= Socialtext::AppConfig->default_workspace || '__NONE__';
    if (ref($workspace) eq 'HASH') {
        # Minimal mode doesn't give us an object, for speed
        $workspace->{default} = $workspace->{name} eq $self->{__default_ws} ? 1 : 0;
        $workspace->{uri} = '/data/workspaces/' . $workspace->{name};
        Socialtext::Timer->Pause('entity_hash');
        return $workspace;
    }

    my $hash = {
        name  => $workspace->name,
        uri   => '/data/workspaces/' . $workspace->name,
        title => $workspace->title,
        # not really modified time, but it is the time we have
        modified_time => $workspace->creation_datetime,
        default => $workspace->is_default ? 1 : 0,
        account_id => $workspace->account_id,
        user_count => $workspace->user_count(direct => 1),
        group_count => $workspace->group_count(direct => 1),
        permission_set => $workspace->permissions->current_set_name,
        is_all_users_workspace => $workspace->is_all_users_workspace ? 1 : 0,

        # workspace_id is the 'right' name for this field, but hang on to 'id'
        # for backwards compatibility.
        workspace_id => $workspace->workspace_id,
        id => $workspace->workspace_id,

        # REVIEW: more?
    };
    Socialtext::Timer->Pause('entity_hash');
    return $hash;
}

sub POST {
    my $self = shift;
    my $rest = shift;
    my $user = $rest->user;

    unless ($user->is_authenticated && !$user->is_deleted) {
        $rest->header(-status => HTTP_401_Unauthorized);
        return '';
    }

    my $request = decode_json( $rest->getContent() );
    $request = ref($request) eq 'HASH' ? [$request] : $request;
    unless (ref($request) eq 'ARRAY') {
        $rest->header(
            -status => HTTP_400_Bad_Request,
            -type  => 'text/plain', );
        return "bad json";
    }

    my @workspaces;

    eval {
        # Do initial error checking outside the transaction to avoid creating
        # the workspaces if possible
        for my $meta (@$request) {

            unless ($meta->{account_id}) {
                die Socialtext::Exception::DataValidation->new(
                    loc("error.valid-account-for-this-wiki-required")
                );
            }

            if (my $members = $meta->{members}) {
                die Socialtext::Exception::Auth->new(
                    loc('error.must-be-business-admin-to-set-members-of-wiki')
                ) unless $user->is_business_admin;

                unless (grep { $_->{role_name} eq 'admin' } @$members) {
                    die Socialtext::Exception::DataValidation->new(
                        loc("error.at-least-one-wiki-administrator-required")
                    );
                }
            }
            else {
                $meta->{members} = [
                    { role_name => 'admin', user_id => $user->user_id }
                ];
            }
        }

        sql_txn {
            for my $meta (@$request) {
                my $ws = $self->_create_workspace_from_meta($meta);
                push @workspaces, $ws;

                for my $m (@{$meta->{members}}) {
                    my $role = Socialtext::Role->new(
                        name => $m->{role_name}
                    );
                    if (my $uid = $m->{user_id}) {
                        $ws->add_user(
                            user => Socialtext::User->new(user_id => $uid),
                            role => $role,
                            actor => $user,
                        );
                    }
                    elsif (my $gid = $m->{group_id}) {
                        $ws->add_group(
                            group => Socialtext::Group->GetGroup(
                                group_id => $gid,
                            ),
                            role  => $role,
                            actor => $user,
                        );
                    }
                }
            }
        }
    };
    if (my $e = $@) {
        my ($status, $message);
        if (ref($e)) {
            $status = $e->isa('Socialtext::Exception::Auth')
                ? HTTP_401_Unauthorized
                : HTTP_400_Bad_Request;

            $message = join("\n", $e->message);
        }
        else {
            $status  = HTTP_400_Bad_Request;
            $message = $e;
            warn $message;
        }
        $rest->header(
            -status => $status,
            -type   => 'text/plain',
        );
        $message =~ s/at\s+.+\.pm\s+line\s+\d+\s*$//;
        return $message;
    }

    my $location = @workspaces > 1
        ? '/data/workspaces'
        : '/data/workspaces/' . $workspaces[0]->name;

    $rest->header(
        -status   => HTTP_201_Created,
        -type     => 'application/json',
        -Location => Socialtext::URI::uri(path => $location),
    );
    return '"created"';

}

sub _create_workspace_from_meta {
    my $self  = shift;
    my $meta  = shift;
    my $actor = $self->rest->user;

    die Socialtext::Exception::DataValidation->new(loc('error.name-title-required'))
        unless $meta->{name} and $meta->{title};

    $meta->{account_id} ||= $actor->primary_account_id;
    my $acct = Socialtext::Account->new(account_id => $meta->{account_id});
    die Socialtext::Exception::Auth->new(loc('error.user-cannot-access-account'))
        unless $actor->is_business_admin || $acct->role_for_user($actor);

    Socialtext::Workspace->new(name => $meta->{name})
        and die Socialtext::Exception::Conflict->new(loc('error.wiki-exists'));

    my $ws = Socialtext::Workspace->create(
        creator                         => $actor,
        name                            => $meta->{name},
        title                           => $meta->{title},
        account_id                      => $meta->{account_id},
        cascade_css                     => $meta->{cascade_css},
        customjs_name                   => $meta->{customjs_name},
        customjs_uri                    => $meta->{customjs_uri},
        skin_name                       => $meta->{skin_name},
        dont_add_creator                => 1,
        show_welcome_message_below_logo =>
            $meta->{show_welcome_message_below_logo},
        show_title_below_logo => $meta->{show_title_below_logo},
        header_logo_link_uri  => $meta->{header_logo_link_uri},

        ( $meta->{clone_pages_from} 
            ? ( clone_pages_from => $meta->{clone_pages_from} )
            : () ),
    );

    $ws->permissions->set(set_name => $meta->{permission_set})
        if $meta->{permission_set};

    if (my $groups = $meta->{groups}) {
        $self->_add_groups_to_workspace($ws, $groups);
    }

    return $ws;
}

sub _add_groups_to_workspace {
    my $self    = shift;
    my $ws      = shift;
    my $groups  = shift;
    my $rest    = $self->rest;
    my $creator = $rest->user;

    $groups = ref($groups) eq 'HASH' ? [$groups] : $groups;
    die Socialtext::Exceptions::DataValidation->new(loc('error.bad-json'))
        unless ref($groups) eq 'ARRAY';

    for my $meta (@$groups) {
        my $group = Socialtext::Group->GetGroup(
            group_id => $meta->{group_id}
        ) or die Socialtext::Exception::NotFound->new(loc('error.group-does-not-exist'));

        $ws->has_group($group, {direct => 1})
            and die Socialtext::Exception::Conflict->new(
                loc('error.group-already-in-wiki'));

        $group->user_can(
            user => $creator,
            permission => ST_ADMIN_PERM,
        ) or die Socialtext::Exception::Auth->new(loc('error.user-is-not-group-admin'));

        my $role = Socialtext::Role->new(
            name => $group->{role} ? $group->{role} : 'member'
        ) or die Socialtext::Exception::Param->new(loc('error.invalid-role-for-group'));

        $ws->add_group(
            group => $group,
            role  => $role,
            actor => $creator,
        );
    }

    return undef;
}

1;
