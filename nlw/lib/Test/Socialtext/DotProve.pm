use 5.12.0;

package Test::Socialtext::DotProve;
use base 'Exporter';
our @EXPORT_OK = qw(load save);

use TAP::Parser::YAMLish::Reader ();
use TAP::Parser::YAMLish::Writer ();
use Carp qw(croak);

#stolen frpm App::Prove::State and hacked up.
#because it uses its own YAML dialect :-(

sub save {
    my ($yaml, $store) = @_;

    my $writer = TAP::Parser::YAMLish::Writer->new;
    local *FH;
    open FH, ">", "$store" or croak "Can't write $store ($!)";
    $writer->write( $yaml, \*FH);
    close FH;
}

sub load {
    my $name = shift;
    my $reader = TAP::Parser::YAMLish::Reader->new;
    local *FH;
    open FH, "<$name" or croak "Can't read $name ($!)";

    # XXX this is temporary
    my $yaml = $reader->read(
        sub {
            my $line = <FH>;
            defined $line && chomp $line;
            return $line;
        }
    );

    close FH;
    return $yaml;
}

__END__

=head1 NAME

Test::Socialtext::DotProve - Load and save .prove files

=head1 SYNOPSIS

    use Test::Socialtext::DotProve qw(load save);
    my $prove = load(".prove");
    save($prove, ".prove");

=head1 DESCRIPTION

This module provides save/load functions to C<.prove> files,
used as part of build system integration with Hudson.

=head1 SEE ALSO

F<dev-bin/merge-prove>

=cut
