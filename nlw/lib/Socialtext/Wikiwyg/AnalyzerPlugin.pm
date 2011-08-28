# @COPYRIGHT@
package Socialtext::Wikiwyg::AnalyzerPlugin;
use strict;
use warnings;
use Socialtext::l10n '__';

use base 'Socialtext::Plugin';

use Class::Field qw( const );

const class_id => 'analyzer';
const class_title => __('class.analyzer');

sub register {
    my $self = shift; 
    my $registry = shift;
    $registry->add(action => 'wikiwyg_analyzer');
}

sub wikiwyg_analyzer {
    my $self = shift;
    return $self->hub->template->process('wikiwyg_analyzer.html',
        page_ids => [ $self->hub->pages->all_ids_newest_first ],
    );
}

1;

