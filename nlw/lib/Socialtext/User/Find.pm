package Socialtext::User::Find;
# @COPYRIGHT@
use Moose;
use MooseX::StrictConstructor;
use Socialtext::SQL qw/sql_execute sql_singlevalue/;
use Socialtext::SQL::Builder qw/sql_abstract/;
use Socialtext::String;
use Socialtext::User;
use Socialtext::Encode 'ensure_is_utf8';
use namespace::clean -except => 'meta';

has 'viewer'   => (is => 'rw', isa => 'Socialtext::User', required => 1);
has 'limit'    => (is => 'rw', isa => 'Maybe[Int]');
has 'offset'   => (is => 'rw', isa => 'Maybe[Int]');
has 'filter'   => (is => 'rw', isa => 'Maybe[Str]');
has 'show_pvt' => (is => 'ro', isa => 'Bool', default => 0 );
has 'order'    => (is => 'rw', isa => 'Maybe[Str]', writer => '_order');
has 'reverse'  => (is => 'ro', isa => 'Bool', default => undef);
has 'all'      => (is => 'rw', isa => 'Bool', default => undef, writer => '_all');

# 0 = full representation
# 1 = limited representation
# 2 = only BFN, user_id and display_name (forced by just_visiting)
has 'minimal' => (is => 'rw', isa => 'Int', default => 0, writer => '_minimal');

has 'just_visiting' => (is => 'ro', isa => 'Bool');

sub BUILD {
    my $self = shift;
    if ($self->just_visiting) {
        $self->_all(1);
        $self->_minimal(2);
        $self->filter(undef); # everyone
        $self->_order('name');
    }
    $self->cleanup_filter;
}

sub cleanup_filter {
    my $self = shift;

    # undef: everyone
    # empty: invalid query
    # non-empty: prefix match

    return $self->filter('%') unless defined $self->filter;

    my $filter = lc Socialtext::String::trim($self->filter);

    # If we don't get rid of these wildcards, the LIKE operator slows down
    # significantly.  Matching on anything other than a prefix causes Pg to not
    # use the 'text_pattern_ops' indexes we've prepared for this query.
    $filter =~ s/[_%]//g; # remove wildcards

    # Remove start of word character
    $filter =~ s/\\b//g;

    die "empty filter"
        if (defined $filter && $filter =~ /^\s*$/);

    $filter .= '%';

    return $self->filter($filter);
}

has 'sql_from' => (
    is => 'ro', isa => 'Str', lazy_build => 1,
);
sub _build_sql_from {
    return q{
        users
    };
}

has 'sql_cols' => (
    is => 'ro', isa => 'ArrayRef', lazy_build => 1,
);
sub _build_sql_cols {
    my $self = shift;
    my @cols = ('DISTINCT users.user_id', 'display_name');
    if ($self->minimal < 2) {
        push @cols,
            qw/first_name last_name email_address driver_username/,
            $self->_private_sql_cols;
    }

    return \@cols;
}

sub _private_sql_cols {
    my $self = shift;

    return $self->show_pvt
        ? @Socialtext::User::private_interface : ();
}

has 'sql_count' => (
    is => 'ro', isa => 'ArrayRef', lazy_build => 1,
);
sub _build_sql_count {
    return ['COUNT(DISTINCT(users.user_id))'];
}

has 'sql_where' => (
    is => 'ro', isa => 'HashRef', lazy_build => 1,
);
sub _build_sql_where {
    my $self = shift;
    my $filter = $self->filter;

    my %where = (
        '-or'  => [
            'lower(first_name)'      => { '-like' => $filter },
            'lower(last_name)'       => { '-like' => $filter },
            'lower(email_address)'   => { '-like' => $filter },
            'lower(driver_username)' => { '-like' => $filter },
            'lower(display_name)'    => { '-like' => $filter },
        ],
    );

    # get sql/bindings for Users that are actually visible to us
    if (!$self->all) {
        my ($vis_sql, @vis_bind);
        $vis_sql = q{
            EXISTS (
                SELECT 1
                FROM user_set_path other
                WHERE other.from_set_id = users.user_id
                  AND EXISTS (
                    SELECT 1
                    FROM user_set_path viewer
                    WHERE viewer.from_set_id = ?
                      AND other.into_set_id = viewer.into_set_id
                  )
            )
        };
        @vis_bind = ($self->viewer->user_id);
        $where{'-nest'} = \[ $vis_sql, @vis_bind ],
    }

    return \%where;
}

has 'sql_order' => ( is => 'ro', isa => 'HashRef', lazy_build => 1 );

sub _build_sql_order {
    my $self = shift;

    my $order = $self->order;
    die if $order and $order !~ /^\w+$/;
    $order = ['display_name']
        if !$order or $order eq 'name' or $order eq 'alpha';

    my $group = $self->sql_group;

    return {
        order_by => $self->reverse ? { -desc => $order } : { -asc => $order },
        $group ? (group_by => $group) : (),
    }
}

has 'sql_group' => ( is => 'ro', isa => 'Maybe[Str]', lazy_build => 1);
sub _build_sql_group {}

sub get_results {
    my $self = shift;

    my ($sql, @bind) = sql_abstract()->select(
        \$self->sql_from, $self->sql_cols, $self->sql_where,
        $self->sql_order, $self->limit, $self->offset,
    );

    my $sth = sql_execute($sql, @bind);
    return $sth->fetchall_arrayref({}) || [];
}

sub get_count {
    my $self = shift;
    my ($sql, @bind) = sql_abstract()->select(
        \$self->sql_from, $self->sql_count, $self->sql_where,
    );
    return sql_singlevalue($sql, @bind);
}

sub typeahead_find {
    my $self = shift;
    if ($self->all and
        !($self->viewer->is_business_admin or $self->just_visiting))
    {
        die "Only Business Admin's can search for Users across all Accounts.\n";
    }

    my $prefix = lc ensure_is_utf8($self->filter);
    $prefix =~ s/%$//;
    my $prefix_re;
    if (length $prefix) {
        $prefix_re = qr/\b$prefix/i;
    }

    my $rows = $self->get_results;
    my $min = $self->minimal;
    if ($min >= 2) {
        return [ map { 
            my $user = Socialtext::User->new(user_id => $_->{user_id});

            # {bz: 4811}: If preferred name does not match, return first+last name
            # as "display_name" so client-side lookahead can highlight them instead.
            if ($prefix_re and $_->{display_name} !~ $prefix_re) {
                $_->{display_name} = $user->proper_name;
            }

            +{
                best_full_name => $user->guess_real_name,
                user_id => $_->{user_id}, 
                display_name => $_->{display_name}
            } 
        } @$rows ];
    }

    my @results;
    for my $row (@$rows) {
        next if Socialtext::User::Default::Users->IsDefaultUser(
            username => $row->{driver_username},
        );

        # {bz: 4811}: If preferred name does not match, return first+last name
        # as "display_name" so client-side lookahead can highlight them instead.
        my $user;
        if ($prefix_re and $row->{display_name} !~ $prefix_re) {
            $user = Socialtext::User->new(user_id => $row->{user_id});
            $row->{display_name} = $user->proper_name;
        }

        unless ($min) {
            $user ||= Socialtext::User->new(user_id => $row->{user_id});
            $row->{best_full_name} = $user->guess_real_name;
            $row->{name} = $row->{driver_username};
            $row->{uri} = "/data/users/$row->{driver_username}";

            # Backwards compatibility stuff
            $row->{email} = $row->{email_address};
            $row->{username} = $row->{driver_username};
        }
        push @results, $row;
    }
    return \@results;
}

__PACKAGE__->meta->make_immutable;
1;
