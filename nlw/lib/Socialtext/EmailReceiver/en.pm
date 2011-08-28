# @COPYRIGHT@
package Socialtext::EmailReceiver::en;

use strict;
use warnings;

use base 'Socialtext::EmailReceiver::Base';

sub format_date {
    my $self = shift;
    my $datetime = shift;
    my $date_header;
    
    my $format_datetime = DateTime::Format::Mail->new;

    $date_header = "Date: " . $format_datetime->format_datetime($datetime);
    return $date_header;
}



1;
