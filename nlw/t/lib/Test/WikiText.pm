# @COPYRIGHT@
package Test::WikiText;
use Test::Base -Base;

package Test::WikiText::Filter;
use Test::Base::Filter -base;

sub parse_wikitext {
    eval "require $Test::WikiText::parser_module; 1" or die;
    eval "require $Test::WikiText::emitter_module; 1" or die;

    my $parser = $Test::WikiText::parser_module->new(
        receiver => $Test::WikiText::emitter_module->new,
    );
    $parser->parse(shift);
}
