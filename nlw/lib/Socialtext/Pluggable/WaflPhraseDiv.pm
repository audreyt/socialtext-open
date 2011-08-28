package Socialtext::Pluggable::WaflPhraseDiv;
# @COPYRIGHT@
use strict;
use warnings;
use Class::Field qw( const field);
use Socialtext::Formatter::WaflPhrase;
use base 'Socialtext::Formatter::WaflPhraseDiv';
use Socialtext::Permission 'ST_READ_PERM';
use Socialtext::l10n qw( loc );

field instance => undef;
field method => undef;
field wafl_id => 'pluggable_waflphrasediv';

sub html {
    my $self = shift;
    my $wafl = $self->method;
    return $self->hub->pluggable->hook("wafl.$wafl",[$self->arguments]);
}

1;
