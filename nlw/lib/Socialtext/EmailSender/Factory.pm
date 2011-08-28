# @COPYRIGHT@
package Socialtext::EmailSender::Factory;
use strict;
use Socialtext::l10n qw(system_locale);
use Socialtext::EmailSender::en;

sub create {
    shift;
    my $locale = shift;

    my $class = _get_class($locale);
    eval "use $class";
    if ($@) {
        $locale = system_locale();
        $class = _get_class($locale);

        # this code is used when we use test locale
        eval "use $class";
        if($@) {
            return Socialtext::EmailSender::en->new;
        }
    }
    
    return $class->new;
}

sub _get_class {
    my $locale = shift;
    my $class  = "Socialtext::EmailSender::" . $locale;
    return $class;
}

1;
