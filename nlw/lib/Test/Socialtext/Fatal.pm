package Test::Socialtext::Fatal;
use warnings;
use strict;
use base 'Exporter';

our @EXPORT = qw/exception/;

sub exception (&) {
    my $code = shift;
    local $@;
    my $ok;
    eval {
        local $SIG{__DIE__};
        $code->();
        $ok = 1;
    };
    return if $ok;

    return "<undef>" unless defined $@;
    return $@ if $@;
    return $@ eq '' ? "<empty-string>" : "$@ but true";
}

1;
__END__

=head1 NAME

Test::Socialtext::Fatal - like Test::Fatal, but simpler

=head1 SYNOPSIS

 use Test::More tests => 1234; # or Test::Socialtext
 use Test::Socialtext::Fatal;
 like exception { die "narhwal" }, qr/narhwal/, "like a unicorn, but real";

=head1 DESCRIPTION

Inspired by L<Test::Fatal>, but without the L<Try::Tiny> complexity.

Doesn't have the stack-pollution problems that L<Test::Exception> does.

Where you'd write this with C<Test::Exception>:

    lives_ok { foo() } "baz";
    dies_ok { foo() } "baz";
    throws_ok { foo() } qr/bar/, "baz";
    throws_ok { foo() } "My::Class", "baz";

You write it like this with Test::Fatal and Test::Socialtext::Fatal

    ok !exception { foo() }, "baz";
    ok exception { foo() }, "baz";
    like exception { foo() }, qr/bar/, "baz";
    isa_ok exception { foo() }, "My::Class", "baz";

It's worth the extra 5-7 characters to not have to rely on flakey
Sub::Uplevel+Test::Exception.

=head1 FUNCTIONS

=over 4

=item exception BLOCK

Returns the exception thrown by the block or C<undef> if it ran successfully.

There are a few weird cases that this module attempts to cover. If the
exception is undef, the string C<< <undef> >> is returned.  If the exception
is the empty string, instead of that the string C<< <empty-string> >> is
returned.  If the exception is string-equal to "0", the string C<< 0 but true
>> is returned.  Test::Fatal takes a different approach of C<confessing> when
it sees one of those cases.

=back

=cut
