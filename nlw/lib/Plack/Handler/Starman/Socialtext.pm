package Plack::Handler::Starman::Socialtext;
use warnings;
use strict;
use Starman::Server;
use base 'Plack::Handler::Starman';

$::proctitle ||= 'starman-socialtext';

# mostly copied from P:H:Starman:
sub run {
    my($self, $app) = @_;

    if ($ENV{SERVER_STARTER_PORT}) {
        require Net::Server::SS::PreFork;
        @Starman::Server::ISA = qw(Net::Server::SS::PreFork); # Yikes.
    }

    Starman::Server::Socialtext->new->run($app, {%$self});
}

{
    package Starman::Server::Socialtext;
    use base 'Starman::Server';

    sub run_parent {
        my $self = shift;
        local $self->{options}{argv} = [$::proctitle];
        $self->SUPER::run_parent(@_);
    }

    sub child_init_hook {
        my $self = shift;
        local $self->{options}{argv} = [$::proctitle];
        $self->SUPER::child_init_hook(@_);
    }

    sub _finalize_response {
        my ($self, $env, $res) = @_;
        if ($env->{'socialtext.keep-alive.force'}) {
            # Forced keep-alive (for NTLM); ignore harakiri flag from SizeLimit
            $env->{'psgix.harakiri.commit'} = 0;
            $self->{client}{keepalive} = 1;
        }
        return $self->SUPER::_finalize_response($env, $res);
    }
}

1;
__END__

=head1 NAME

Plack::Handler::Starman::Socialtext - Socialtext custom Plack::Handler::Starman

=head1 SYNOPSIS

  plackup -s Starman::Socialtext ...

=head1 DESCRIPTION

Custom handler to wrap Starman's.

=head1 COPYRIGHT

Portions derived from L<Plack::Handler::Starman> are copyright the respective
owners.

The rest is (c) 2010 Socialtext Inc.

=cut


