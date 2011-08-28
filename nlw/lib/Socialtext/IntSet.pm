package Socialtext::IntSet;
# @COPYRIGHT@
use Moose;
use Judy::1 ();
use Scalar::Util ();
use namespace::clean -except => 'meta';

=head1 NAME

Socialtext::IntSet - A set of integers

=head1 SYNOPSIS

    use Socialtext::IntSet;

    # build an empty set:
    my $ints = Socialtext::IntSet->new;
    $ints->set(1234); # returns if was in set previously
    $ints->set(4567);
    if ($ints->get(1234)) {
        # ...
    }
    $ints->unset(4567); # returns if was in set previously

    my $ints2 = $ints->copy; # deep-copy

    # to and from a perl array reference:
    my $array = $ints->array;
    my $ints_copy = Socialtext::IntSet->FromArray($array); # list OK too

    # to and from a BER-encoded, delta-compressed list:
    my $serialized = $ints->serial;
    my $ints_copy = Socialtext::IntSet->FromSerial($serialized);

    # binary set operators:
    my $union = $a->union($b);
    my $isect = $a->intersection($b);
    my $diff = $a->subtraction($b);
    if ($a->disjoint($b)) {
        # ... nothing in common
    }
    if (my $common = $a->common($b)) {
        # ... at least one int in common
    }
    if ($a->is_subset_of($b)) { ... }
    if ($a->is_strict_subset_of($b)) { ... }
    if ($a->equals($b)) { ... }

=head1 DESCRIPTION

Represents a list of natural numbers (integers >0). Stores the set of numbers
internally as a C<Judy::1> vector, but abstracts the function-call API
required to manage this vector.

B<NOTE> Negative numbers are cast to their unsigned equivalent by C<Judy::1>,
for example -1 becomes 0xFFFFFFFF on a 32-bit machine.  This is convenient for
C<count_range>, but possibly a nuissance everywhere else.

Socialtext::IntSet does zero validation of input, relying on Judy to do that.
Garbage in, garbage out.

=cut

# Wrap the pointer Judy::1 uses in order to provide a destructor that frees
# memory. (instead of using Judy::_obj)
{
    package Socialtext::IntSet::Judy1;
    use warnings;
    use strict;
    sub new {
        my $x = $_[1] || 0;
        return bless \$x, __PACKAGE__;
    }
    sub DESTROY {
        my $self = shift;
        Judy::1::Free($$self) if $$self;
    }
}

=head1 ATTRIBUTES

=over 4

=item judy1

The C<Judy::1> instance can be obtained with the C<judy1> accessor (a
reference to it is returned). Be careful with passing around this
reference; its underlying structure will be de-allocated when its owning
IntSet is destroyed (which is important since C<Judy::1> allocates memory
differently than most perl objects).

In general, you should just be passing around a reference to the IntSet
itself.

=back

=cut

has 'judy1' => (
    is => 'ro', isa => 'Socialtext::IntSet::Judy1',
    default => sub { Socialtext::IntSet::Judy1->new },
);

=head1 METHODS

=head2 Conversion and instantiation

=over 4

=item Socialtext::IntSet->new

Create an empty set.

=item copy

Make a deep-copy of this IntSet.

=cut

sub copy {
    my $self = shift;
    my $ja = ${$self->judy1};
    my $jb = 0;
    my $k = Judy::1::First($ja,0);
    while (defined $k) {
        Judy::1::Set($jb, $k);
        $k = Judy::1::Next($ja,$k);
    }
    return Socialtext::IntSet->new(
        judy1 => Socialtext::IntSet::Judy1->new($jb));
}

=item Socialtext::IntSet->FromArray(1,2,3)

=item Socialtext::IntSet->FromArray([4,5,6])

Create a new IntSet from an array or array reference.  The input list need not
be ordered, but must be of positive integers.

=cut

sub FromArray {
    my $class = shift;
    my $arr = (defined $_[0] && ref $_[0]) ? $_[0] : \@_;
    my $j1 = 0;
    Judy::1::Set($j1, $_) for @$arr;
    return $class->new(judy1 => Socialtext::IntSet::Judy1->new($j1));
}

=item array

Returns the IntSet as an array-ref.  Guaranteed to be in ascending order.  The
empty set is returned as an empty array-ref.

=cut

sub array {
    my $self = shift;
    my @raw;
    my $j1ptr = ${$self->judy1};
    my $k = Judy::1::First($j1ptr,0);
    while (defined $k) {
        push @raw, $k;
        $k = Judy::1::Next($j1ptr,$k);
    }
    return \@raw;
}

=item Socialtext::IntSet->FromSerial(\$buf)

Instantiate an IntSet from a buffer of BER-encoded, delta-compressed numbers.

=item serial

Return a reference to a buffer of BER-encoded, delta-compressed numbers.

    my $buf_ref = $ints->serial();
    print $fh $$buf_ref;

Delta compressing makes it more probable to be encoded in a single base-128
digit (L<pack> has details).  This makes it highly suitable for a storage and
transmission format.  This is a space-versus-speed tradeoff, which will result
in a net win if you can assume I/O delays B<AND> similarity in the set
members.  If the numbers are highly disparate (large deltas) then it's
possible this will be a little worse.

Example: the following list is stored as 16 bytes using "network-longs":

    pack ('N*', 1004, 1005, 1007, 1017);

When serialized as BER-encoded numbers, it only takes up 8 bytes:

    pack('w*', 1004, 1005, 1007, 1017);

Instead, if we use the deltas between numbers then the list only takes up 5
bytes:

    pack('w*', 1004, 1, 2, 10);

=cut

sub FromSerial {
    my $j = 0;
    my $n = 0;
    for my $i (unpack 'w*', ${$_[1]}) {
        $n += $i;   
        Judy::1::Set($j, $n);
    }

    return $_[0]->new(judy1 => Socialtext::IntSet::Judy1->new($j));
}

sub serial {
    my $self = shift;
    my ($n,$i) = (0,0);
    return \pack 'w*', map {
        $i = $_ - $n;
        $n += $i;
        $i;
    } @{$self->array};
}

=back

=head2 Basic Operators

Simple set enquiry and modification methods.

=over 4

=item get($N) / check($N) / test($N)

Returns true if N is in the set.

=item nth($N)

Get the Nth item in the set.  Returns undef if no such N.  B<Note> that this is a 1-based index; the first set bit will be at 1, not 0 like in Perl.

=item set($N)

Add N to the set. Returns if it was previously in the set.

=item unset($N) / clear($N)

Remove N from the set. Returns if it was previously in the set.

=item count / size

The cardinality (size) of the set.

=item count_range($X => $Y)

The count of numbers present in the set between X and Y, inclusive.  Use -1
for the positive extreme.

=item mem_used

The amount of memory used by the C<Judy::1> set.

=back

=cut

sub get { Judy::1::Test (${$_[0]->judy1},$_[1]) }
*test = *check = \&get;

sub nth { Judy::1::Nth(${$_[0]->judy1},$_[1]) }

# These may modify the "pointer" value of the judy1 and are supposedly the
# only ones that can do so.
# Judy::1::Set returns if the bit was successfully changed, we want the
# previous state, so negate it. See set_sanity tests in the .t
sub set   { !Judy::1::Set  (${$_[0]->judy1},$_[1]) }
sub unset {  Judy::1::Unset(${$_[0]->judy1},$_[1]) }
*clear = \&unset;

*size = \&count;
sub count {
    my $self = shift;
    return 0 unless ${$self->judy1};
    return $self->count_range(0 => -1);
}

sub count_range { Judy::1::Count(${$_[0]->judy1}, $_[1] => $_[2]) }

sub mem_used { Judy::1::MemUsed(${$_[0]->judy1}) }

=head2 Looping

Method(s) for looping over an IntSet.

=over 4

=item generator

Returns a code-ref that can be called in a loop to iterate over the integers
in the set.  

The generator returns C<undef> when there are no more numbers. The number "0"
is returned as the string "0E0" (zero-but-true), making it safe to construct
loops like this:

    my $gen = $ints->generator();
    while (my $n = $gen->()) {
        # ...
    }

The code-ref keeps a weakened reference to the IntSet to prevent unwanted
reference-cycles. If the underlying IntSet is destroyed, the generator will
return C<undef>.  To prevent weakening the reference, pass in a true value as
the argument to this method.

=back

=cut

sub generator {
    my $self = shift;
    my $take_strong_ref = shift;

    my $k = Judy::1::First(${$self->judy1},0);
    return sub {} unless defined $k;

    Scalar::Util::weaken($self) unless $take_strong_ref;

    return sub {
        return unless defined $k;
        return unless $self; # ref went away
        my $i = $k+0; # copy
        $k = Judy::1::Next(${$self->judy1},$k);
        return $i ? $i : "0E0";
    };
}

=head2 Binary Set Operators

These operators act on two sets at once.  When a set is returned, it is a
newly-instantiated Socialtext::IntSet.

=over 4

=item $a->intersection($b)

Returns an IntSet of the integers in common between A and B.

=cut

*intersect = \&intersection;
sub intersection {
    my $self = shift;
    my $other = shift;

    my $ja = ${$self->judy1};
    my $jb = ${$other->judy1};
    my $jc = 0;

    my $ka = Judy::1::First($ja,0);
    my $kb = Judy::1::First($jb,$ka);

    while (defined $ka && defined $kb) {
        if ($ka == $kb) {
            Judy::1::Set($jc,$ka);
            $ka = Judy::1::Next($ja,$ka);
            $kb = Judy::1::Next($jb,$kb);
        }
        elsif ($ka < $kb) {
            $ka = Judy::1::Next($ja,$ka);
        }
        else {
            $kb = Judy::1::Next($jb,$kb);
        }
    }

    return Socialtext::IntSet->new(
        judy1 => Socialtext::IntSet::Judy1->new($jc));
}

=item $a->union($b)

Returns an IntSet that has integers present in A plus those in B.

=cut

sub union {
    my $self = shift;
    my $other = shift;

    my $jc = 0;

    for my $jr ($self->judy1, $other->judy1) {
        my $j = $$jr;
        my $k = Judy::1::First($j,0);
        while (defined $k) {
            Judy::1::Set($jc,$k);
            $k = Judy::1::Next($j,$k);
        }
    }

    return Socialtext::IntSet->new(
        judy1 => Socialtext::IntSet::Judy1->new($jc));
}

=item $a->subtraction($b)

Returns an IntSet for integers in A that are not also in B.

=cut

*subtract = \&subtraction;
sub subtraction {
    my $self = shift;
    my $other = shift;

    my $ja = ${$self->judy1};
    my $jb = ${$other->judy1};
    my $jc = 0;

    my $ka = Judy::1::First($ja,0);
    while (defined $ka) {
        Judy::1::Set($jc, $ka) unless Judy::1::Get($jb,$ka);
        $ka = Judy::1::Next($ja,$ka);
    }

    return Socialtext::IntSet->new(
        judy1 => Socialtext::IntSet::Judy1->new($jc));
}

=item $a->disjoint($b)

Returns true if A and B have no integers in common.

=item $a->common($b)

Returns true if A and B share at least one integer in common.  Returns the
lowest-common integer (or the string "0E0" (zero-but-true) if 0 is that
number).

If the two sets are expected to share some integer, this method can be faster
than calling C<disjoint> and negating the result due to an early-out
optimization.

=cut

sub disjoint {
    my $self = shift;
    return !$self->common(@_);
}

sub common {
    my $self = shift;
    my $other = shift;

    my $ja = ${$self->judy1};
    my $jb = ${$other->judy1};

    my $ka = Judy::1::First($ja,0);
    my $kb = Judy::1::First($jb,$ka);

    while (defined $ka && defined $kb) {
        if ($ka == $kb) {
            return $ka ? $ka : "0E0";
        }
        elsif ($ka < $kb) {
            $ka = Judy::1::Next($ja,$ka);
        }
        else {
            $kb = Judy::1::Next($jb,$kb);
        }
    }
    return;
}

=item $a->is_subset_of($b)

Returns true if all elements of A are present in B.

=item $a->is_strict_subset_of($b)

Returns true if all elements of A are present in B and A does not equal B.
This is also called a proper subset.

=cut

sub is_subset_of {
    my $self = shift;
    my $other = shift;

    my $ja = ${$self->judy1};
    my $jb = ${$other->judy1};

    return 1 if $ja == $jb; # same pointer? same set.

    my $ka = Judy::1::First($ja,0);
    while (defined $ka) {
        return unless Judy::1::Get($jb,$ka);
        $ka = Judy::1::Next($ja,$ka);
    }
    return 1;
}

sub is_strict_subset_of {
    my $self = shift;
    my $other = shift;

    return unless $self->is_subset_of($other);

    my $ja = ${$self->judy1};
    my $jb = ${$other->judy1};

    return if $ja == $jb; # same pointer? same set.

    # must exist at least one element of B that's not in A
    my $k = Judy::1::First($jb,0);
    while (defined $k) {
        return 1 unless Judy::1::Get($ja,$k);
        $k = Judy::1::Next($jb,$k);
    }
    return;
}

=item $a->equals($b)

Returns true if all elements of A are in B C<and> vice-versa.

=cut

sub equals {
    my $self = shift;
    my $other = shift;

    my $ja = ${$self->judy1};
    my $jb = ${$other->judy1};

    return 1 if $ja == $jb; # same pointer? same set.

    my $ka = Judy::1::First($ja,0);
    my $kb = Judy::1::First($jb,0);

    while (defined $ka && defined $kb) {
        return if ($ka != $kb); # one is missing some digit
        $ka = Judy::1::Next($ja,$ka);
        $kb = Judy::1::Next($jb,$kb);
    }

    # one of them is too short
    return if (defined $ka or defined $kb);
    return 1;
}

=back

=head1 COPYRIGHT

(C) 2010 Socialtext Inc. C<< code@socialtext.com >>.

=cut
__PACKAGE__->meta->make_immutable;
1;
