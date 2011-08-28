#!/usr/bin/env perl
# @COPYRIGHT@
use utf8;
use strict;
use warnings;
use Test::Socialtext tests => 10;
use Socialtext::AppConfig;

fixtures(qw( empty ));

BEGIN {
    use_ok 'Socialtext::l10n', qw(:all);
}

set_system_locale('en');
my $hub = new_hub('empty');

Default_to_english: {
    is loc('Welcome'), 'Welcome';
    is loc('dashboard.welcome'), 'Welcome';
}

Test_locale: {
    my $result = loc_lang('zz');
    isa_ok($result, 'Socialtext::l10n::I18N::zz', 'found locale.');
    is loc('dashboard.welcome'), 'Zzzzzzz';
}

System_locale: {
    is( system_locale(), 'en', "Checking default system locale." );
    set_system_locale('xx');
    is( system_locale(), 'xx', "Checking changed system locale." );
}

Best_locale: {
    # Force non-english system locale
    set_system_locale('xx');

    #is( best_locale($hub), 'en', "Checking best locale - from user" );
    is( best_locale(), 'xx', "Checking best locale - from system" );
}

UnicodeCollation: {
    is(
        join(',', lsort(qw[ Ångström xylophone ḿegashark numanuma LOLcat ])),
        'Ångström,LOLcat,ḿegashark,numanuma,xylophone'
    );

    is(
        join(',', map { $_->{name} } lsort_by(name => map {
            +{ name => $_ }
        } qw[ Ångström xylophone ḿegashark numanuma LOLcat ])),
        'Ångström,LOLcat,ḿegashark,numanuma,xylophone'
    );
}

exit;

AutoBlockQuoting: {
    is(
        loc(
            'Foo [_2] ~[cow love] [quant,_4,foo,foos] [_1] [*,_4,blah][food][sofa]~~~~~[lick]~[love dude][_3]~[squared]man ~~~~~~[eek] [_1]',
            "aaa", "bbb", "ccc", 15
        ),
        "Foo bbb [cow love] 15 foos aaa 15 blahs[food][sofa]~~[lick][love dude]ccc[squared]man ~~~[eek] aaa",
        "Ensure that non-variable square brackets are quoted away."
    );
}

sub set_system_locale {
    my $locale = shift;
    Socialtext::AppConfig->set( locale => $locale );
    Socialtext::AppConfig->write;
}
