// Breaking out smaller test failures from big-formatting-roundtrip.t

var t = new Test.Wikiwyg();

var filters = {
    wikitext: ['template_vars']
};

t.plan(2);

t.filters(filters);

t.run_roundtrip('wikitext');

/* Test
=== table has only one line afterwards
--- wikitext
␤| foo |

bar bar

=== table has only one line afterwards
--- wikitext
␤| foo |

{rt: 12345}

*/
