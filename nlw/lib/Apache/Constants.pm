package Apache::Constants;
use 5.12.0;
use parent 'Exporter';
use HTTP::Status ();

use constant DECLINED => -1;
our @EXPORT = qw(
    DECLINED
);
our %EXPORT_TAGS = (
    common => \@EXPORT,
    response => \@EXPORT,
);

my %synonyms = (
    FOUND => 'REDIRECT',
    UNAUTHORIZED => 'AUTH_REQUIRED',
);

for my $method (@{$HTTP::Status::EXPORT_TAGS{constants}}) {
    no strict 'refs';
    (my $code = $method) =~ s/^HTTP_//;
    my $value = &{"HTTP::Status::$method"}();
    *$code = *$method = sub { $value };
    push @EXPORT, $code, $method;
    if (my $sym = $synonyms{$code}) {
        *$sym = sub { $value };
        push @EXPORT, $sym;
    }
}

1;

__END__

=head1 NAME

Apache::Constants - Drop-in replacement for the same module in mod_perl

=head1 SYNOPSIS

    use Apache::Constants;
    print NOT_FOUND; # 404

=head1 DESCRIPTION

This module uses L<HTTP::Status> to provide the same constants
as L<Apache::Constants> without requiring L<mod_perl>.

=cut
