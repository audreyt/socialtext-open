package Socialtext::Moose::Util;
use Moose();
use Moose::Util ();
use base 'Exporter';
our @EXPORT = qw(compat_meta_arg compat_with_meta caller_info);

=head1 NAME

Socialtext::Moose::Util

=head1 SYNOPSIS

    use Socialtext::Moose::Util;

=head1 DESCRIPTION

Utilities for "going meta".

=head1 FUNCTIONS

=over 4

=item compat_with_meta (@list_of_functions)

=item compat_meta_arg ($_[0])

Use this pair of functions with L<Moose::Exporter> to set up methods that will
get called with the caller's class meta-object.

    Moose::Exporter->setup_import_methods(
        compat_with_meta('has_foo'),
    );
    ...
    sub has_foo {
        my ($c_or_m, ...) = @_;
        my $meta = compat_meta_arg($c_or_m);
    }

This is needed due to Moose API changes in version 0.90.

=cut

sub compat_with_meta;
*compat_with_meta = ($Moose::VERSION < 0.90)
? sub { return with_caller => [@_] }
: sub { return with_meta => [@_] };

sub compat_meta_arg;
*compat_meta_arg = ($Moose::VERSION < 0.90)
? sub { Moose::Util::find_meta($_[0]) }
: sub { $_[0] };

=item caller_info

This is a copy of C<Moose::_caller_info> or C<Moose::Util::_caller_info> (It
moved packages sometime after 0.72).  It returns a hash with info of the
caller, just like L<perlfunc/caller> would.  You can specify additional frames
to ascend with a parameter.

This is useful for building the C<definition_context> parameter to
L<Moose::Meta::Class/add_attribute>.

=cut

sub caller_info (;$) {
    my $level = @_ ? ($_[0] + 1) : 2;
    my %info;
    @info{qw(package file line)} = caller($level);
    return \%info;
}

no Moose();
1;
__END__

=back

=head1 COPYRIGHT

Copyright (c) 2010 Socialtext Inc.

=cut
