package Socialtext::User::Find::Container;
# @COPYRIGHT@
use Moose;
use MooseX::StrictConstructor;
use Socialtext::SQL::Builder qw/sql_abstract/;
use Socialtext::String;
use Socialtext::User;
use List::MoreUtils qw/any/;
use Socialtext::UserSet qw(:const);
use namespace::clean -except => 'meta';

extends 'Socialtext::User::Find';

has 'container' => (is => 'ro', isa => 'Socialtext::UserSetContainer',
    required => 1);
has 'direct'    => (is => 'ro', isa => 'Bool', default => undef);

sub _build_sql_from {
    my $self = shift;
    my $table = $self->direct ? 'user_set_include' : 'user_set_path';
    my $from = $table . q{
        JOIN users ON (from_set_id = user_id)
    };
    if ($self->minimal < 2) {
        $from .= q{ JOIN "Role" USING(role_id) };
    }
    if ($self->minimal < 1) {
        $from .= qq{
            JOIN "UserMetadata" USING(user_id)
            JOIN "Account"
                ON "UserMetadata".primary_account_id = "Account".account_id
        };
    }
    return $from;
}

sub _build_sql_cols {
    my $self = shift;
    my @cols = qw(user_id display_name);
    if ($self->minimal < 2) {
        push @cols,
            qw(first_name last_name email_address driver_username),
            'array_accum(DISTINCT "Role".name) AS role_names',
            $self->_private_sql_cols;

    }
    if ($self->minimal < 1) {
        push @cols,
            '"UserMetadata".primary_account_id',
            '"Account".name AS primary_account_name',
            "to_char(creation_datetime, 'YYYY-MM-DD') AS creation_date",
            q{ 
                COALESCE((
                    SELECT COUNT(DISTINCT into_set_id)
                      FROM user_set_path countable
                     WHERE countable.from_set_id = user_id
                       AND into_set_id } . PG_WKSP_FILTER . q{
                ),0) AS workspace_count
            };
    }
    return \@cols;
}

has '+sql_where' => ( 'isa' => 'ArrayRef' );

sub _build_sql_where {
    my $self = shift;

    my @where = (
        into_set_id => $self->container->user_set_id,
    );

    unless ($self->all) {
        my ($sub_stmt, @sub_bind) = sql_abstract()->select(
            "user_sets_for_user", "1", {
                user_set_id => $self->container->user_set_id,
                user_id => $self->viewer->user_id,
            },
        );
        push @where, ('-nest' => \["EXISTS ($sub_stmt)" => @sub_bind]);
    }

    my $filter = $self->filter;
    push @where,
        '-or' => [
            'lower(first_name)'      => { '-like' => $filter },
            'lower(last_name)'       => { '-like' => $filter },
            'lower(email_address)'   => { '-like' => $filter },
            'lower(driver_username)' => { '-like' => $filter },
            'lower(display_name)'    => { '-like' => $filter },
        ];

    return ['-and' => \@where];
}

sub _build_sql_group {
    my $self = shift;
    my @group_cols = qw(user_id display_name);
    if ($self->minimal < 2) {
        push @group_cols,
            qw(first_name last_name email_address driver_username display_name),
            $self->_private_sql_cols;
    }
    if ($self->minimal < 1) {
        push @group_cols, qw(
            primary_account_name primary_account_id creation_date
        );
    }

    return join ', ', @group_cols;
}

around 'get_results' => sub {
    my $code = shift;
    my $self = shift;
    my $rows = $self->$code(@_);

    return $rows if ($self->minimal >= 2);
    for my $row (@$rows) {
        my @roles = map { Socialtext::Role->new(name => $_) }
            @{$row->{role_names} || []};

        my @sorted_role_names = map { $_->name }
            Socialtext::Role->SortByEffectiveness(roles => \@roles);

        delete $row->{role_names};
        $row->{role_name} = $sorted_role_names[-1];
        $row->{roles} = \@sorted_role_names;
        $row->{is_admin} = any { $_ eq 'admin' } @sorted_role_names;
    }
    return $rows;
};

__PACKAGE__->meta->make_immutable;

=head1 NAME

User::Find::Container - Find users in an UserSetContainer

=head1 SYNOPSIS

    my $user_find = Socialtext::User::Find::Container->new(
        container => $group,
        direct => $true_or_false,
        # ...standard User::Find parameters...
    )

=head1 DESCRIPTION

This module extends the Socialtext::User::Find interface with
two additional parameters:

=over 4

=item container

The scope to find users from.

Must be a L<Socialtext::UserSetContainer> object, such as a group.

=item direct

If true, only find users who are direct members of the container.

If false, also find indirect members of intermediate sub-containers.

=back

=cut

1;
