# @COPYRIGHT@
package Socialtext::l10n;
use strict;
use warnings;
use base 'Exporter';

our @EXPORT = qw(__ loc lcmp lsort lsort_by);
our @EXPORT_OK = qw(loc_lang system_locale best_locale getSortKey);
our %EXPORT_TAGS = (all => [@EXPORT, @EXPORT_OK]);
our $CUR_LOCALE = 'en';
our $SYS_LOCALE = 'en';

sub _reload_l10n {
    delete $INC{'Socialtext/l10n.pm'};
    no warnings 'redefine';
    local $SIG{__WARN__} = sub { 1 };
    require Socialtext::l10n;
    _rebind_overrides();
    for my $sym (@EXPORT, 'getSortKey') {
        no strict 'refs';
        *$sym = \&{"Socialtext::l10n::$sym"};
    }
}

for my $sym (@EXPORT, 'getSortKey') {
    no strict 'refs';
    *$sym = sub {
        _reload_l10n();
        goto &{"Socialtext::l10n::$sym"};
    }
}

sub __loc_lang__ {
    $CUR_LOCALE = shift if @_;
    return $CUR_LOCALE;
}

sub __best_locale__ {
    my $x = __loc_lang__() || __system_locale__();
    return $x;
}

sub __system_locale__ {
    $SYS_LOCALE = shift if @_;
    return $SYS_LOCALE;
}

sub _rebind_overrides {
    *loc_lang = \&__loc_lang__;
    *best_locale = \&__best_locale__;
    *system_locale = \&__system_locale__;
}



_rebind_overrides();

1;
