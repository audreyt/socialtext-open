package Socialtext::UserSetPerspective;
# @COPYRIGHT@
use Moose;
use Socialtext::UserSet qw/:const/;
use Socialtext::MultiCursor;
use Socialtext::SQL qw/sql_execute sql_singlevalue/;
use Socialtext::SQL::Builder qw/sql_abstract/;
use namespace::clean -except => 'meta';

has 'cols' => (
    is => 'ro', isa => 'ArrayRef',
    required => 1,
    auto_deref => 1,
);

has 'subsort'     => (is => 'ro', isa => 'Str', required => 1);
has 'always_join' => (is => 'ro', isa => 'Maybe[Str]');

has 'view'        => (
    is => 'ro', isa => 'ArrayRef',
    required => 1,
    auto_deref => 1,
);

has 'order_by' => (is => 'ro', isa => 'CodeRef', required => 1);
has 'apply'    => (is => 'ro', isa => 'CodeRef', required => 1);

has 'aggregates' => (
    is => 'ro', isa => 'HashRef[ArrayRef]',
    default => sub { +{} },
);

sub get_order_by {
    my ($self, $ob, $opts) = @_;
    my ($join,$sort,@cols);

    if ($ob =~ /^role(?:_name)?$/) {
        # need a subselect string-concatenation-aggregate join to sort
        die "can't sort by role name when multiplexing roles yet" if $opts->{mux_roles};
        push @cols, '"Role".name';
        $join = ' JOIN "Role" USING (role_id)';
        $sort = '"Role".name';
    }
    else {
        eval {
            ($join,$sort,@cols) = $self->order_by->($ob);
        };
        confess $@ if $@;
    }
    return ($join,$sort,@cols);
}

sub get_total {
    my ($self,$opts) = @_;

    die "where is a required option and must be an ArrayRef"
        unless ($opts->{where} && ref($opts->{where}) eq 'ARRAY');

    my $mux = $opts->{mux_roles};
    my @cols = $self->cols;
    push @cols, ($mux ? 'role_ids' : 'role_id');

    my $from = Socialtext::UserSet->RoleViewSQL(
        $self->view,
        direct => $opts->{direct},
        mux_roles => $opts->{mux_roles},
        omit_roles => $opts->{omit_roles},
        exclude_acct_paths => $opts->{exclude_acct_paths},
    );
    $from .= $self->always_join if $self->always_join;

    my @where = @{$opts->{where}};

    my ($sql, @bind) = sql_abstract()->select(\$from, \@cols, \@where); 
    return sql_singlevalue(qq{
        SELECT COUNT(1) FROM ($sql) countable
    }, @bind);
}

sub get_cursor {
    my ($self,$opts) = @_;

    die "where is a required option and must be an ArrayRef"
        unless ($opts->{where} && ref($opts->{where}) eq 'ARRAY');

    my $mux = $opts->{mux_roles};
    my $omit = $opts->{omit_roles};
    my @cols = $self->cols;
    push @cols, ($mux ? 'role_ids' : 'role_id') unless $omit;

    my $from = Socialtext::UserSet->RoleViewSQL(
        $self->view,
        direct => $opts->{direct},
        mux_roles => $mux,
        omit_roles => $omit,
        exclude_acct_paths => $opts->{exclude_acct_paths},
    );
    $from .= $self->always_join if $self->always_join;

    my @where = @{$opts->{where}};
    my %aggregates;

    $opts->{sort_order} ||= 'ASC';
    my $sort_order = ($opts->{sort_order} =~ /^ASC|DESC$/i)
        ? uc $opts->{sort_order} : 'ASC';

    my $order = $self->subsort;

    # Remove role_id out of the order by; it's always ASC in an array when
    # muxing (and gone when omitting)
    $order =~ s/(?:\s*,\s+)role_id\s*(?:ASC|DESC)?(\s*,)?/$1 ? $1 : ''/ie
        if (($mux or $omit) and $order);

    if (my $ob = lc $opts->{order_by}) {
        my ($join,$sort,@extra_cols);
        if (exists $self->aggregates->{$ob}) {
            $aggregates{$ob} = 1;
            $sort = $ob;
        }
        else {
            ($join,$sort,@extra_cols) = $self->get_order_by($ob,$opts);
            $from .= $join if $join;
            push @cols, @extra_cols;
        }

        $order = "$sort $sort_order, $order";
    }

    if ($opts->{include_aggregates}) {
        $aggregates{$_} = 1 for keys %{$self->aggregates};
    }

    if (%aggregates) {
        for my $agg (keys %aggregates) {
            my $agg_conf = $self->aggregates->{$agg};
            my ($col,$query) = Socialtext::UserSet->AggregateSQL(@$agg_conf);
            push @cols, "$col AS $agg";
            $from .= $query;
        }
    }

    my ($sql, @bind) = sql_abstract()->select(
        \$from, \@cols, \@where, $order, $opts->{limit}, $opts->{offset});
 
    my $sth = sql_execute($sql, @bind);
    my $rows = $sth->fetchall_arrayref({});
    $rows = $self->decorate_result($opts,$rows);

    my $apply_cb = $self->apply;
    my $apply = $opts->{raw}
        ? sub { $_[0] }
        : sub {
            my $row = shift;
            if ($mux) {
                $row->{roles} = [
                    map { Socialtext::Role->new(role_id => $_) }
                    @{$row->{role_ids}}
                ];
            }
            elsif (!$omit) {
                $row->{role} = 
                    Socialtext::Role->new(role_id => $row->{role_id});
            }
            return $apply_cb->($row);
        };
    return Socialtext::MultiCursor->new(
        iterables => [$rows],
        apply => $apply,
    );
}

sub decorate_result {
    my ($self,$opts,$rows) = @_;

    my $thing = $opts->{thing};
    if ($thing && blessed($thing)) {
        my @add_all;
        if ($thing->isa('Socialtext::Group')) {
            @add_all = (group_id => $thing->group_id);
            push @add_all, (group => $thing) unless $opts->{raw};
        }
        elsif ($thing->isa('Socialtext::Workspace')) {
            @add_all = (workspace_id => $thing->workspace_id);
            push @add_all, (workspace => $thing) unless $opts->{raw};
        }
        elsif ($thing->isa('Socialtext::Account')) {
            @add_all = (account_id => $thing->account_id);
            push @add_all, (account => $thing) unless $opts->{raw};
        }
        elsif ($thing->isa('Socialtext::User')) {
            @add_all = (user_id => $thing->user_id);
            push @add_all, (user => $thing) unless $opts->{raw};
        }
        else {
            @add_all = (user_set_id => $thing->user_set_id);
            push @add_all, (user_set => $thing) unless $opts->{raw};
        }
        $rows = [map { +{%$_, @add_all} } @$rows];
    }
    return $rows;
}

__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 NAME

Socialtext::UserSetPerspective - Declare an object's view of other user-sets

=head1 SYNOPSIS

  use Socialtext::UserSetPerspective;
  my $perspective = Socialtext::UserSetPerspective->new(
    # see code for exact usage.
    # good examples are in UserSetContained and UserSetContainer
    cols => [ 'user_id' ],
    subsort => 'user_id ASC, role_id ASC',
    view => [
        from => 'users',
        into => 'container',
        alias => 'ucroles'
    ],
    aggregates => {
        # allow a workspace count per-user
        workspace_count => [ into => 'workspaces', using => 'user_id' ],
    },
    order_by => \&_generate_order_by,
    apply => \&_apply_function_for_multicursor,
  );

  sub sorted_user_roles {
      my ($self,%opts) = @_;
      # optional object; inlined into every row (id only in raw mode)
      $opts{thing} = $self;

      # SQL::Abstract where-clause syntax:
      $opts{where} = ['ucroles.into_set_id' => $self->user_set_id];

      # don't call the apply method when true; just return raw rows then
      $opts{raw} ||= 0;
      # always include aggregates as columns (named after attributes)
      $opts{include_aggregates} ||= 0;
      # direct (1) or transitive (0)?
      $opts{direct} ||= 0;

      # paging and sorting controls
      $opts{order_by} ||= 'name'; # subsort used if not specified
      $opts{sort_order} ||= 'ASC'; # default ASC, applied to order_by only
      $opts{limit} ||= 0;
      $opts{offset} ||= 0;

      return $perspective->get_cursor(\%opts);
  }

=head1 DESCRIPTION

Generates paged and sorted L<Socialtext::MultiCursor> using
L<Socialtext::UserSet>, L<SQL::Abstract>, and L<Socialtext::SQL>.

The usage for the 'view' argument is in L<Socialtext::UserSet>'s
C<RoleViewSQL> method. A C<< direct => 1 >> argument can be passed in via the
%opts hash to control querying direct vs. transitive relationships.

The usage for the 'aggregates' argument is in L<Socialtext::UserSet>'s
C<AggregateSQL>.  All aggregates are automatically "order_by" clauses and
don't need to be handled by the C<order_by> callback.

=cut
