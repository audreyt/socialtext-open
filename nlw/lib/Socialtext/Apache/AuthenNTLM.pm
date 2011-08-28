package Socialtext::Apache::AuthenNTLM;
# @COPYRIGHT@
use 5.12.0;
use warnings;
use methods;
use Apache::Constants; # Use our overrided version

method import ($after_get_config) {
    no warnings 'redefine';
    require Apache::AuthenNTLM;
    *Apache::AuthenNTLM::sockaddr_in = sub {
        return '127.0.0.1', '0bogus';
    };
    if ($after_get_config) {
        state $orig_get_config //= \&Apache::AuthenNTLM::get_config;
        *Apache::AuthenNTLM::get_config = sub {
            return if ($_[0]{smbpdc});
            $orig_get_config->(@_);
            $after_get_config->(@_);
        };
    }

    # paranoia: disable the IPC::Semaphore stuff
    *Apache::AuthenNTLM::Lock::lock = sub { 'dummy' };
    *Apache::AuthenNTLM::Lock::DESTROY = sub {};
    *cache = *Apache::AuthenNTLM::cache;
}

method run ($r) {
    unshift @_, 'Apache::AuthenNTLM';
    goto &{Apache::AuthenNTLM->can('run')};
}


#
# Override a bunch of modules to prevent Apache::AuthenNTLM from loading
# mod_perl components.
#
$INC{$_} = __FILE__ for qw( mod_perl.pm Apache/File.pm);

package mod_perl;
our $VERSION = 0.01;

# Caution: this class is a blessed Int, not a hashref:
package Apache::Connection;
use warnings;
use strict;

sub remote_addr {}
use constant remote_host => '127.0.0.1';
use constant remote_ip => '127.0.0.1';
use constant remote_port => '0bogus';

package Apache::Table;
use Moose;
use MooseX::AttributeHelpers;

has '_table' => (is => 'rw', isa => 'HashRef',
    default => sub {{}},
    metaclass => 'Collection::Hash',
    provides => {
        get => 'get',
        set => 'add',
    }
);

package Apache;
use Moose;
use MooseX::AttributeInflate;
use Socialtext::Log qw(st_log);

use constant auth_type => 'ntlm,basic';
use constant auth_name => '';
use constant proxyreq => 0;

has '_sid' => (is => 'rw', isa => 'Str');

has '_dir_config' => (is => 'rw', isa => 'Apache::Table', lazy_build => 1);
has_inflated 'err_headers_out' => (is => 'rw', isa => 'Apache::Table');
has_inflated 'headers_in' => (
    is => 'rw', isa => 'Apache::Table',
    handles => {
        header_in => 'get',
    }
);
has_inflated 'headers_out' => (is => 'rw', isa => 'Apache::Table');
has 'uri' => (is => 'rw', isa => 'Str');
has 'user' => (is => 'rw', isa => 'Str');

has 'reason' => (
    is      => 'rw',
    isa     => 'Str',
    writer  => 'log_reason',
    trigger => sub {
        my ($self, $new_reason, $old_reason) = @_;
        st_log->warning("AuthenNTLM reason: $new_reason");
    },
);

# only support ntlm, not Basic
has 'authtype' => (is => 'rw', isa => 'Str', default => 'ntlm');

our $AUTOLOAD;
sub AUTOLOAD {
    use Data::Dumper; warn "Autoload Apache $AUTOLOAD ".Dumper([caller,@_]);
    return '';
}

sub connection {
    my $self = shift;
    my $con = 42;
    return bless \$con, 'Apache::Connection';
}

sub _build__dir_config {
    return Apache::Table->new(_table => {
        ntdomain          => 'foo bar baz',
        ntlmdebug         => 0,
        ntlmsemkey        => 0, # disable IPC::Semaphore locking
        ntlmauthoritative => 1,
    });
}

sub dir_config {
    my $self = shift;
    my $k = shift;
    if (!$k) {
        return $self->_dir_config;
    }
    return $self->_dir_config->get($k);
}

package Apache::File; # just prevent this one from loading
use warnings;
use strict;

=head1 NAME

Socialtext::Apache::AuthenNTLM

=head1 SYNOPSIS

  <Location /nlw/ntlm>
    PerlAuthenHandler   +Socialtext::Apache::AuthenNTLM
  </Location>

=head1 DESCRIPTION

Socialtext wrapper around Apache::AuthenNTLM

=cut
