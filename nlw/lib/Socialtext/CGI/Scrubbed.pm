package Socialtext::CGI::Scrubbed;
# @COPYRIGHT@
use strict;
use warnings;
use parent 'CGI::PSGI';
use Class::Field 'field';
use HTML::Scrubber;
use methods-invoker;

field 'scrubber', -init => 'HTML::Scrubber->new';

my %dont_scrub = map { $_ => 1 } qw(page_name page_body content comment users_new_ids POSTDATA PUTDATA tag_name widget widget_string up_page_title keywords add_tag signal status env_initial_text xml edit_summary new_title variables);

method new ($env) {
    if ($Socialtext::PlackApp::CGI) {
        return bless({%$Socialtext::PlackApp::CGI} => $self);
    }
    $->SUPER::new($env || $Socialtext::PlackApp::Request->{env})
}

method param {
    if (@_ == 1) {
        my $key = $_[0];
        my @res = map { (ref $_ || $dont_scrub{$key}) ? $_ : $->scrubber->scrub($_) }
                  $->SUPER::param($key);
        return wantarray ? @res : $res[0];
    }
    return $->SUPER::param(@_);
}
