package Socialtext::Rest::Workspace;
# @COPYRIGHT@

use Moose;
use Socialtext::HTTP ':codes';
use Socialtext::JSON;
use Socialtext::Workspace;
use Socialtext::Workspace::Permissions;
use Socialtext::Permission 'ST_READ_PERM';
use Socialtext::User;
use Socialtext::Group;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Entity';
with 'Socialtext::Rest::WorkspaceRole';

# we handle perms ourselves for PUT
sub permission      { +{ GET => undef, PUT => undef } }
sub allowed_methods {'GET, PUT, HEAD'}
sub entity_name     { 'workspace ' . $_[0]->workspace->title }

sub if_authorized {
    my $self = shift;
    my $method = shift;
    my $call = shift;

    return $self->no_resource('workspace') unless $self->workspace;

    my $has_perm = $self->workspace->permissions->user_can(
        user => $self->rest->user,
        permission => ST_READ_PERM,
    );
    unless ($has_perm or $self->rest->user->is_business_admin) {
        return $self->not_authorized;
    }

    return $self->$call(@_);
}


# Generic method called by the other GET_* routines.
#
sub _GET_any {
    my( $self, $rest ) = @_;

    # Return any problems as an HTTP 400 error message.
    #
    my @errors;
    if ( ! $self->validate_resource_id( $rest, \@errors ) ) {
        return $self->http_400( $rest, join("\n", @errors) );
    }

    # Call the superclass method with the same name as the calling
    # subroutine.
    #
    # REVIEW: This feels too clever, but the SUPER:: call is the *only*
    # difference among the different GET_* methods.  DRY wins over
    # simpler-but-duplicated code, at least for now.
    #
    # (The GET_* methods could also be generated based on a template,
    # but that seems even worse.)
    #
    my $super_method = (caller 1)[3];   # - get fully-qualified name of calling sub
    $super_method =~ s/^.+::/SUPER::/;  # - replace package name with SUPER
    return $self->$super_method($rest); # - call the superclass method
}

sub GET_html { _GET_any(@_) }
sub GET_text { _GET_any(@_) }
sub GET_json { _GET_any(@_) }


sub get_resource {
    my( $self, $rest ) = @_;

    my $workspace = $self->workspace;
    my $is_admin = sub {
        $self->hub->checker->check_permission('admin_workspace')
            || $rest->user->is_business_admin;
    };
    my $peon_view
        = sub { workspace_id => $workspace->workspace_id, name => $workspace->name, title => $workspace->title };
    my $extra_data
        = sub { pages_uri => $self->full_url('/pages'), group_ids => $workspace->group_ids };
    my $extra_admin_data
        = sub { permission_set => $workspace->permissions->current_set_name };

    return
          !$workspace ? undef
        : &$is_admin  ? { &$extra_data, &$extra_admin_data, %{$workspace->to_hash} }
                      : { &$extra_data, &$peon_view };
}

sub PUT {
    my( $self, $rest ) = @_;

    return $self->can_admin(sub {
        my $workspace = $self->workspace;

        return $self->http_404($self->rest)
            unless $workspace;

        my $data = decode_json($rest->getContent());

        my $uri = $data->{customjs_uri};
        if (defined $uri) {
            $workspace->update(customjs_uri => $uri);
        }

        my $set  = $data->{permission_set};
        if ($set) {
            my @sets = keys %Socialtext::Workspace::Permissions::PermissionSets;
            return $self->http_400($self->rest, "$set unknown")
                unless grep { $_ eq $set } @sets;

            $workspace->permissions->set( set_name => $set );
        }


        $rest->header( -status => HTTP_204_No_Content );
        return '';
    });
}

sub DELETE {
    my ( $self, $rest ) = @_;

    return $self->can_admin(sub {
        my $ws = $self->workspace;

        $ws->delete;

        $rest->header(
            -status => HTTP_204_No_Content,
        );
        return $self->ws . ' removed';
    });
}

sub POST_to_trash {
    my $self = shift;

    $self->can_admin(sub {
        $self->modify_roles(sub {
            my $data = decode_json($self->rest->getContent());
            my $ws   = $self->workspace;

            for my $thing (@$data) {
                my $condemned;
            
                $condemned = Socialtext::User->new(user_id => $thing->{user_id}) if $thing->{user_id};
                $condemned ||= Socialtext::User->new(username => $thing->{username}) if $thing->{username};
                if (!$condemned) {
                    $condemned = eval {
                        Socialtext::Group->GetGroup(group_id => $thing->{group_id})
                    };
                }
                next unless $condemned
                    && $ws->user_set->direct_object_role($condemned);

                $ws->remove_role(
                    actor  => $self->rest->user,
                    object => $condemned,
                );
            }
            return '';
        });
    });
}

sub validate_resource_id {
    my( $self, $rest, $errors ) = @_;

    return Socialtext::Workspace->NameIsValid(
        name    => $self->ws,
        errors  => $errors
    );
}

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
