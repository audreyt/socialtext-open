package Test::Socialtext::AccountContext::features;
# @COPYRIGHT@
use Moose::Role;
use Test::More;
use namespace::clean -except => 'meta';

has 'context' => (is => 'ro', isa => 'Test::Socialtext::AccountContext',
                  required => 1, handles => ['registry']);
has 'share'   => (is => 'ro', isa => 'Maybe[HashRef]',
                  writer => '_share', clearer => 'clear_share');
has 'state'   => (is => 'ro', isa => 'Str', default => 'pristine',
                  writer => '_state');

requires qw/Tests prepare validate/;

our $Depth = 0;

sub fetch_feature_share {
    my $self     = shift;
    my $name     = shift;
    my $index    = shift;
    my $is_retry = shift; # to prevent infinite loop.

    my $feature = $self->context->registry->{$name};
    _die("cannot find feature $name\n") unless $feature;

    _die("self-referential access, use \$self->share instead, dummy\n")
        if $self == $feature;
    
    my $share = $feature->share;
    if ($share && $share->{$index}) {
        return $share->{$index};
    }

    _die("could not properly set up $name\n") if $is_retry;

    if (!$share) {
        $Depth++;
        _diag("resolving '$name' dependency");
        $feature->prepare if $self->state eq 'preparing';
        $feature->validate if $self->state eq 'validating';
        _diag("resolved '$name' dependency");
        $Depth--;

        return $self->fetch_feature_share($name, $index, 1);
    }

    _die("no '$index' share for $name\n");
}

around 'prepare'  => sub { _safe_do_work(@_, 'prepare') };
around 'validate' => sub { _safe_do_work(@_, 'validate') };

sub _safe_do_work {
    my $work    = shift;
    my $feature = shift;
    my $state   = shift;

    my $class   = ref($feature);
    my $working = substr($state, 0, -1) ."ing"; # take off the ending 'e'
    my $done    = $state . "d";

    return if $feature->state eq $done;

    _diag("$working $class") unless $Depth;

    _die("circular dependency detected while $working $class")
        if $feature->state eq $working;

    $feature->_state($working);
    $feature->clear_share();
    $feature->_share($work->($feature));
    $feature->_state($done);

    _diag("$class is $done") unless $Depth;
}

sub _die {
    my $message = shift;
    my $depth = $Depth ? " (depth: $Depth)" : '';
    die "ERROR:$depth $message\n";
}

sub _diag {
    my $message = shift;
    diag $Depth ? "(depth: $Depth) $message" : "$message";
}

1;

=head1 NAME

Test::Socialtext::AccountContext::features - A Moose role for Contextual
Account features.

=head1 SYNOPSIS

    package MyFeature;
    use Moose;

    with 'Test::Socialtext::AccountContext::features';

    ...

=head1 DESCRIPTION

A Moose Role to be used by proper Features. Its main function is to wrap some
of the required methods to make sure that we don't hit a circular dependency
when looking up inter-feature shares.

=cut
