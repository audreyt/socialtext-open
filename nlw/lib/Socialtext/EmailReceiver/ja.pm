# @COPYRIGHT@
package Socialtext::EmailReceiver::ja;

use strict;
use warnings;

use base 'Socialtext::EmailReceiver::Base';
use Socialtext::l10n qw(loc system_locale);

use DateTime::Format::Strptime;
use utf8;

sub format_date {
    my $self     = shift;
    my $datetime = shift;
    my $date_header;


    my $fmt = DateTime::Format::Strptime->new(
        pattern   => '%Y年%m月%d日%H時%M分%S秒',
        locale    => 'ja',
    );

    $date_header = $fmt->format_datetime($datetime);
    Encode::_utf8_on($date_header);

    return $date_header;
}

1;

