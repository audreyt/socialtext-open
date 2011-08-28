package Test::Socialtext::CLIUtils;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/expect_success expect_failure is_last_exit call_cli_argv/;
our %EXPORT_TAGS = ('all' => \@EXPORT_OK);
use Test::More;
use Test::Output;

our $LastExitVal;
{
    no warnings 'redefine';
    *Socialtext::CLI::_exit = sub { $LastExitVal = shift; die 'exited'; };
}

sub expect_success {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $sub    = shift;
    my $expect = shift;
    my $desc   = shift;

    my $test = ref $expect ? \&stdout_like : \&stdout_is;

    local $@;
    local $LastExitVal;
    $expect = [$expect] unless ref($expect) and ref($expect) eq 'ARRAY';
    for my $e (@$expect) {
        $test->( sub { eval { $sub->() } }, $e, $desc );
        warn $@ if $@ and $@ !~ /exited/;
        is( $LastExitVal, 0, 'exited with exit code 0' );
    }
}

sub expect_failure {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $sub    = shift;
    my $expect = shift;
    my $desc   = shift;
    my $error_code = shift || 1;

    my $test = ref $expect ? \&stderr_like : \&stderr_is;

    local $@;
    local $LastExitVal;
    $test->(
        sub {
            eval { $sub->() };
        },
        $expect,
        $desc
    );
    warn "expect_failed: $@" if $@ and $@ !~ /exited/;
    is( $LastExitVal, $error_code, "exited with exit code $error_code" );
}

sub is_last_exit {
    my $error_code = shift;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is( $LastExitVal, $error_code, "exited with exit code $error_code" );
}

=over 4

=item call_cli_argv

Returns a subref that will call the passed-in cli method (first arg) with
given "argv" parameters.

Intended for use with "expect_failure/_success". Example:

  expect_failure(
      call_cli_argv(enable_plugin => 
          '--account' => $acct_name,
          qw(--plugin foo)
      ),
      qr/Plugin foo does not exist!/,
      'enable invalid plugin',
  );

=back
=cut

sub call_cli_argv {
    my $method = shift;
    my $argv   = [$method, @_];
    return sub {
        local @ARGV = @{$argv};
        my $cli = Socialtext::CLI->new(argv => $argv);
        $cli->run();
    }
}

1;
__END__

=head1 NAME

Test::Socialtext::CLIUtils -- Commandline test utils

=head1 DESCRIPTION

Test utilities that aid in writing st-admin unit tests.

=head1 SYNOPSIS

    use Test::Socialtext::CLIUtils qw/expect_success
        expect_failure is_last_exit call_cli_argv/;

=cut
