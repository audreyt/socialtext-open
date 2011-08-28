package Socialtext::Async::DNS;
# @COPYRIGHT@
use warnings;
use strict;

use AnyEvent::DNS 5.2;
use base 'AnyEvent::DNS';
use Clone qw/clone/;
use Scalar::Util qw/weaken/;
use List::MoreUtils qw/any firstidx/;

BEGIN {
    if ($AnyEvent::DNS::VERSION < 5.2 or $AnyEvent::DNS::VERSION > 5.34) {
        warn "Only AnyEvent::DNS versions 5.2 thru 5.34 have been tested\n";
        # if you see this, please read the REVIEW ON UPGRADE sections BEFORE
        # you up the version check.
        die "AnyEvent::DNS version mismatch; refusing to load";
    }
}

# if you update these please update the POD below.
our $EnableCache = 1;
our $RespectTTL = 1;
our $DefaultTTL = 3600;

patch_it: {
    no strict 'refs';
    no warnings 'redefine';
    *{'AnyEvent::DNS::_dec_rr'} = \&_dec_rr_with_ttl;
    my $resolver = AnyEvent::DNS::resolver();
    bless $resolver, __PACKAGE__;
    $resolver->clear_cache;
}

# REVIEW ON UPGRADE:
# check that _dec_rr_with_ttl is still the same as the real _dec_rr (minus
# namespacing) in AnyEvent/DNS.pm, but with an extra $ttl field at the end of
# the return-value.
#
# Easiest way to do this is to diff the old and new sources.
#
# The TTL is offset 4 bytes after the "name" field and is
# an unsigned 32-bit int ("N" in pack/unpack syntax). See section 3.2.1 of
# ftp://ftp.rfc-editor.org/in-notes/rfc1035.txt

sub _dec_rr_with_ttl {
   my $name = AnyEvent::DNS::_dec_name;

   my ($rt, $rc, $ttl, $rdlen) = unpack "nn N n", substr $AnyEvent::DNS::pkt, $AnyEvent::DNS::ofs; $AnyEvent::DNS::ofs += 10;
   local $_ = substr $AnyEvent::DNS::pkt, $AnyEvent::DNS::ofs, $rdlen; $AnyEvent::DNS::ofs += $rdlen;

   [
      $name,
      $AnyEvent::DNS::type_str{$rt}  || $rt,
      $AnyEvent::DNS::class_str{$rc} || $rc,
      ($AnyEvent::DNS::dec_rr{$rt} || sub { $_ })->(),
      $ttl, # <-- the only thing different from the original _dec_rr
   ]
}

sub _check_cache {
    my ($self, $request) = @_;
    my ($qtype, $qname, $flat_opt, $cbs, $opt) = @$request;
    goto skip_cache unless $EnableCache;

    my $now = AE::now;
    my $cache = $self->{st_cache};

    $cache->{$qtype} ||= {};
    $cache->{$qtype}{$qname} ||= [];
    my $name_cache = $cache->{$qtype}{$qname};

    if ($name_cache && @$name_cache) {
        # expire old results:
        @$name_cache = grep { $_->[1] > $now } @$name_cache;

        for my $ent (@$name_cache) {
            next unless ($ent->[0] eq $flat_opt);
            my $res = $ent->[2];
            while (my $cb = shift @$cbs) {
                local $@;
                eval { 
                    my $clone = clone $res;
                    $cb->(@$clone)
                };
                warn "error during cached DNS request callback (ignored): $@"
                    if $@;
            }
            return;
        }
    }

skip_cache:

    # look to see if there's a pending request for the same thing
    # (which we want to prevent even if not caching)
    for my $p (@{$self->{st_pending}}) {
        if ($p->[0] eq $qtype and
            $p->[1] eq $qname and
            $p->[2] eq $flat_opt)
        {
            push @{$p->[3]}, @{$request->[3]}; # merge callbacks
            return;
        }
    }

    push @{$self->{st_pending}}, $request;
    return 1;
}

sub _store_cache {
    my ($self, $request, $res) = @_;

    my ($qtype, $qname, $flat_opt, $cbs, $opt) = @$request;

    my $min_ttl = $DefaultTTL;
    if ($RespectTTL && $EnableCache) {
        my $min_ttl = 0x7feeeeef; # arbitrary sentinel
        for my $r (@$res) {
            my $ttl = pop @$r;
            $min_ttl = $ttl if $ttl < $min_ttl;
        }
        
        $min_ttl = $DefaultTTL if $min_ttl >= 0x7feeeeef;
    }
    else {
        pop @$_ for @$res; # discard the TTLs
    }

    my $ent;
    if ($EnableCache) {
        $ent = [$flat_opt, $min_ttl+AE::now(), $res];
        push @{$self->{st_cache}{$qtype}{$qname}}, $ent;
    }
    
    while (my $cb = shift @{$request->[3]}) {
        local $@;
        eval { 
            my $clone = clone $res;
            $cb->(@$clone)
        };
        warn "error during DNS request callback (ignored): $@" if $@;
    }
    
    my $idx = firstidx { $_ == $request } @{$self->{st_pending}};
    splice @{$self->{st_pending}}, $idx, 1;
    return;
}

# override
sub resolve ($%) {
    my $cb = pop;
    my ($self, $qname, $qtype, %opt) = @_;

    my $flat_opt = join("\0", map { $_ => $opt{$_} } sort keys %opt);
    my $request = [$qname, $qtype, $flat_opt, [$cb], \%opt];

    return unless $self->_check_cache($request);
    weaken $self;
    $cb = sub { $self->_store_cache($request,\@_) }; 
    $self=$self; # strengthen
    $self->SUPER::resolve($qname, $qtype, %opt, $cb);
}

sub clear_cache {
    my $class_or_self = shift;
    my $self = ref($class_or_self) ? $class_or_self : AnyEvent::DNS::resolver();
    $self->{st_cache} = {};
    $self->{st_pending} = [];
}

1;
__END__

=head1 NAME

Socialtext::Async::DNS - A gentler, friendlier AnyEvent::DNS

=head1 SYNOPSIS

    use AnyEvent;
    use Socialtext::Async::DNS;

    $Socialtext::Async::EnableCache = 1;

    AnyEvent::DNS::a('somehostname.domain',sub {
        $cv->send(@_);
    });
    my @resp = $cv->recv;
    AnyEvent::DNS::a('somehostname.domain',sub {
        $cv->send(@_);
    });
    my @cached_resp = $cv->recv;

To enable per-process permanent caching:

    $Socialtext::Async::RespectTTL = 0;
    $Socialtext::Async::DefaultTTL = 0x7fffffff;

=head1 DESCRIPTION

De-duplicates and caches requests via AnyEvent::DNS.  Just load the module to
enable and use the GLOBALS below to tweak.

Requests asking the same query (e.g. "get me the A record for
foo.example.com") are de-duplicated so that the actual network request is only
done once.  The success or failure of this request will cause the success or
failure for all of the callbacks supplied (which are all run in their own
C<eval {}> block.

=head1 GLOBALS

Defaults given per item.

=over 4

=item $EnableCache = 1

If true store/retrieve items in the cache.  Don't store/retrieve if false.

=item $RespectTTL = 1

If true, use the TTL on each DNS resource-record (or the lowest TTL in a set
of records for the same query) as the in-memory cache TTL.

If false, force every record to use C<$DefaultTTL>.

=item $DefaultTTL = 3600

The TTL to use when a TTL can't be identified for the query B<or>
C<$RespectTTL> has been turned off.

=back

=head1 COPYRIGHT

(C) 2010 Socialtext Inc.

This module is open-source may be used under the terms of the CPAL, Apache
2.0, or Artistic 2.0 licenses at your discression.

=cut
