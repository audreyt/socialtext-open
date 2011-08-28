package Socialtext::PrefsTable;
# @COPYRIGHT@
use Moose;
use Socialtext::SQL qw/:exec sql_txn/;
use Socialtext::SQL::Builder qw/sql_abstract/;
use namespace::clean -except => 'meta';

has 'table' => (is => 'ro', isa => 'Str', required => 1);
has 'identity' => (is => 'ro', isa => 'HashRef[Str]', required => 1);
has 'defaults' => (is => 'ro', isa => 'HashRef', default => sub {+{}});

around 'clear' => \&sql_txn;
sub clear {
    my $self = shift;
    my ($sql,@bind) = sql_abstract()->delete($self->table,$self->identity);
    my $sth = sql_execute($sql,@bind);
    return $sth->rows;
}

sub get {
    my $self = shift;
    my ($sql,@bind) = sql_abstract()->select(
        $self->table,[qw(plugin key value)],$self->identity);
    my $sth = sql_execute($sql,@bind);
    my $rows = $sth->fetchall_arrayref({}) || [];

    my $data = { %{$self->defaults} };
    if ($self->identity->{plugin}) {
        $data->{ $_->{key} } = $_->{value} for @$rows;
    }
    else {
        $data->{ $_->{plugin} }{ $_->{key} } = $_->{value} for @$rows;
    }
    return $data;
}

sub set {
    my ($self,%prefs) = @_;

    return unless %prefs;
    my %id = %{$self->identity};

    my ($del_sql,@del_bind) = sql_abstract()->delete(
        $self->table, {
            %id,
            key => {-in => [keys %prefs]}
        }
    );

    my @ins = (keys(%id),qw(key value));
    my $cols = join(',',@ins);
    my $qs = '?,' x @ins;
    chop $qs;

    my $ins_sql =
        "INSERT INTO ".$self->table." ($cols) VALUES ($qs)";

    my @keys;
    my @vals;
    while (my ($k,$v) = each %prefs) {
        next unless (defined $v and !ref($v));
        push @keys, $k;
        push @vals, $v;
    }

    # copy the identity into the first few columns
    my @array_columns = map { [($id{$_}) x @keys] } keys %id;
    # ... and then the preferences
    push @array_columns, \@keys, \@vals;

    sql_txn {
        sql_execute($del_sql,@del_bind);
        sql_execute_array($ins_sql,{},@array_columns);
    };
    return;
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 NAME

Socialtext::PrefsTable - CRUD for a preferences table

=head1 SYNOPSIS

  use Socialtext::PrefsTable;
  
  my $pt = Socialtext::PrefsTable->new(
    table    => 'user_prefs',
    identity => {user_id => $user_id}
  );
  my $hash = $pt->get();

  $hash->{some_pref} = $some_val;
  $pt->set(%$hash); # update prefs for this user

  $pt->clear(); # removes all for this user

=head1 DESCRIPTION

Assumes that you have a table with some identity columns plus C<key> and
C<value>. For example, here's the table that matches the SYNOPSIS in pseudo-SQL:

  CREATE TABLE user_prefs(
    user_id int NOT NULL,
    key text NOT NULL,
    value text NOT NULL,
    PRIMARY KEY (user_id,key)
  );

The C<identity> parameter to the constructor identifies the "owner" of the
preferences.

Keys must be unique and values must be defined, non-reference scalars.

=cut
