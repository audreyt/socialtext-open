# @COPYRIGHT@
package Socialtext::Formatter::WaflBlock;
use strict;
use warnings;

use base 'Socialtext::Formatter::Wafl', 'Socialtext::Formatter::Block';

use Class::Field qw( const field );


const formatter_id => 'wafl_block';
field 'method';
field 'arguments';

sub html_start { '<div class="wafl_block">'}

sub text_filter {
    my $self = shift;
    my $text = shift;
    $text =~ s/<!--\s+wiki:.*?\s-->//sg;
    $text;
}

sub html_end {
    my $self = shift;
    my $method  = $self->method;
    my $escaped = $self->escape_wafl_dashes( $self->matched );
    chomp $escaped;
    $self->hub->wikiwyg->generate_block_widget_image($self);
    return <<EOHTML;
<!-- wiki:
.$method
$escaped
.$method
--></div>
EOHTML
}

sub match {
    my $self = shift;
    my $text = shift;
    return
        unless $text
        =~ /\A(?:^\.([\w\-]+)\ *\n)((?:.*\n)*?)(?:^\.\1\ *\n|\z)/m;
    $self->set_match($2);
    my $method = lc $1;
    $self->method($method);
    $self->matched($2);
}

sub block_text {
    my $self = shift;
    $self->to_html_escaped_text
}

################################################################################
package Socialtext::Formatter::Preformatted;

use base 'Socialtext::Formatter::WaflBlock';
use Class::Field qw( const );

const wafl_id => 'pre';
sub html_start {
    my $self = shift;
    return $self->SUPER::html_start() . "<pre>\n";
}
sub html_end {
    my $self = shift;
    return "</pre>".$self->SUPER::html_end();
}

################################################################################
package Socialtext::Formatter::Html;

use base 'Socialtext::Formatter::WaflBlock';

use Class::Field qw( const );
use HTML::TreeBuilder ();
use HTML::PrettyPrinter;

const wafl_id => 'html';

sub text_filter {
    my $self = shift;
    my $text = $self->SUPER::text_filter(@_);
    $text =~ s/<(?=\/?(?i:html|head|body))/&lt;/g;
    $text;
}

sub escape_html {
    my $self = shift;
    my $text = shift;
    return $self->hub->current_workspace->allows_html_wafl
        ? $self->_pretty_print_html($text)
        : $self->html_escape($text);
}

sub _pretty_print_html {
    my $self = shift;

    # Fix {bz: 1979}: Allow nesting <embed> within <object> for YouTube.
    local %HTML::TreeBuilder::isHeadOrBodyElement = (
        %HTML::TreeBuilder::isHeadOrBodyElement,
        embed => 1,
    );

    # guts can return undef
    my $html = HTML::TreeBuilder->new_from_content(shift)->guts;
    return '' unless ( defined($html) && $html =~ /\S/ );
    my $html_text = join '',
        @{ HTML::PrettyPrinter->new(
            quote_attr      => 1,
            allow_forced_nl => 1,
            )->format($html)
        };
    $html->delete();
    return $html_text;
}

1;
