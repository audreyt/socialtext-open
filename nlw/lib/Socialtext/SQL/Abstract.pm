package Socialtext::SQL::Abstract;
# @COPYRIGHT@
use strict;
use warnings;
use base 'SQL::Abstract::Limit';

=head1 NAME

Socialtext::SQL::Abstract - Adds GROUP BY functionality to SQL::Abstract

=head1 SYNOPSIS

    use Socialtext::SQL::Builder qw/sql_abstract/

    my $sql = sql_abstract()->select(
        'table', 'field',
        { where_col => 'where_field' },
        {
            group_by => 'group_col',
            order_by => [qw(order_col1 order_col2)},
        },
    );

=head1 DESCRIPTION

Shoe horn in a Group By clause for SQL::Abstract. We're already useing
SQL::Abstract::Limit to add limit and offset capabilities. However, this
module also tries to call back into SQL::Abstract's 'select()' method
directly, so we can't simply inherit and override.

Instead, we're left with this dirty, smelly, hackish mess in order to get the
job done.

=cut

no warnings 'redefine';
my $orig = \&SQL::Abstract::_order_by;

*SQL::Abstract::_order_by = sub {
    my ($self, $arg) = @_;

    return $orig->($self, $arg, @_)
        unless ref $arg eq 'HASH'
            and keys %$arg
            and not grep { $_ =~ /^-(?:desc|asc)/i } keys %$arg;

    my $ret = '';

    if (my $g = $arg->{group_by}) {
        $ret = $self->_sqlcase(' group by ') . $g;
    }

    if (defined $arg->{order_by}) {
        my ($frag, @bind) = $orig->($self, $arg->{order_by});
        push(@{$self->{order_bind}}, @bind);
        $ret .= $frag;
    }

    return $ret;
};

1;

