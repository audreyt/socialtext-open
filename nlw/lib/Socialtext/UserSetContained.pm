package Socialtext::UserSetContained;
# @COPYRIGHT@
use Moose::Role;
use Carp qw/croak/;
use Socialtext::UserSet qw/:const/;
use Socialtext::UserSetPerspective;
use Socialtext::Timer qw/time_scope/;
use namespace::clean -except => 'meta';

requires 'user_set_id';

sub _sorted_workspace_roles_order_by {
    my $ob = shift;
    my @cols;
    my $sort;
    my $join = q{
        JOIN "Workspace" w USING (user_set_id)
    };

    if ($ob =~ /^(?:workspace_)?name$/) {
        push @cols, 'w.name AS name';
        $sort = 'w.name';
    }
    elsif ($ob =~ /^(?:primary_)?account(?:_name)?$/) {
        push @cols, 'a.name AS account_name';
        $join .= q{
            JOIN (SELECT account_id, name FROM "Account") a
                ON (w.account_id = a.account_id)
        };
        $sort = 'account_name';
    }
    elsif ($ob eq 'creator') {
        push @cols, 'crtr.display_name AS creator';
        $join .= q{
            JOIN users crtr ON (w.created_by_user_id = crtr.user_id)
        };
        $sort = 'creator';
    }
    elsif ($ob eq 'creation_datetime') {
        push @cols, 'w.creation_datetime';
        $sort = 'w.creation_datetime';
    }
    else {
        croak "Cannot sort workspaces by '$ob'";
    }
    return ($join,$sort,@cols);
}

sub _sorted_workspace_roles_apply {
    my $row = shift;
    return {
        %$row,
        workspace => Socialtext::Workspace->new(
            workspace_id => $row->{workspace_id}),
    };
}

{
    my $perspective = Socialtext::UserSetPerspective->new(
    cols => [
        'user_set_id',
        'user_set_id - '.PG_WKSP_OFFSET.' AS workspace_id',
    ],
    subsort => "user_set_id ASC, role_id ASC",
    view => [
        from       => 'contained',
        into       => 'workspaces',
        into_alias => 'user_set_id', # for JOINing convenience
        alias      => 'xwr',
    ],
    aggregates => {
        user_count    => [ from => 'users',    using => 'user_set_id' ],
        group_count   => [ from => 'groups',   using => 'user_set_id' ],
        account_count => [ into => 'accounts', using => 'user_set_id' ],
    },
    order_by => \&_sorted_workspace_roles_order_by,
    apply    => \&_sorted_workspace_roles_apply,
    );

    sub sorted_workspace_roles {
        my ($self, %opts) = @_;
        my $t = time_scope('sorted_wksp_roles');
        require Socialtext::Workspace;
        $opts{where} = ['xwr.from_set_id' => $self->user_set_id];
        $opts{thing} = $self;
        return $perspective->get_cursor(\%opts);
    }
}

sub _sorted_account_roles_order_by {
    my $ob = shift;
    my @cols;
    my $sort;
    my $join = q{
        JOIN "Account" a USING (user_set_id)
    };

    if ($ob =~ /^(?:account|(?:account_)?name)$/) {
        push @cols, 'a.name AS account_name';
        $sort = 'account_name';
    }
    else {
        croak "Cannot sort accounts by '$ob'";
    }
    return ($join,$sort,@cols);
}

sub _sorted_account_roles_apply {
    my $row = shift;
    my $thing = $row->{user} || $row->{group};
    return {
        %$row,
        account => Socialtext::Account->new(account_id => $row->{account_id}),
    };
}

{
    my $perspective = Socialtext::UserSetPerspective->new(
    cols => [
        'user_set_id',
        'user_set_id - '.PG_ACCT_OFFSET.' AS account_id',
    ],
    subsort => "user_set_id ASC, role_id ASC",
    view => [
        from       => 'contained',
        into       => 'accounts',
        into_alias => 'user_set_id', # for JOINing convenience
        alias      => 'xar',
    ],
    aggregates => {
        user_count      => [ from => 'users',      using => 'user_set_id' ],
        group_count     => [ from => 'groups',     using => 'user_set_id' ],
        workspace_count => [ from => 'workspaces', using => 'user_set_id' ],
    },
    order_by => \&_sorted_account_roles_order_by,
    apply    => \&_sorted_account_roles_apply,
    );

    sub sorted_account_roles {
        my ($self, %opts) = @_;
        my $t = time_scope('sorted_acct_roles');
        require Socialtext::Account;
        $opts{where} = ['xar.from_set_id' => $self->user_set_id];
        $opts{thing} = $self;
        return $perspective->get_cursor(\%opts);
    }
}

1;
__END__

=head1 NAME

Socialtext::UserSetContained - Role for "contained" user-set classes

=head1 SYNOPSIS

    package MyContained;
    use Moose;
    has 'user_set_id' => (..., isa => 'Int');
    with 'Socialtext::UserSetContainer';
    
    my $o = MyContained->new;
    
    # workspaces this set is contained in
    my $mc = $o->sorted_workspace_roles(...);
    # accounts this set is contained in
    my $mc = $o->sorted_account_roles(...);

=head1 DESCRIPTION

Role for applying methods common to all "Contained" user-sets.  

L<Socialtext::Workspace> partially applies this role; it excludes the
'sorted_workspace_roles' method.

=cut
