var t = new Test.Base();

var filters = {
    input: 'upper_case'
};

t.plan(1);
t.filters(filters);
t.run_is('input', 'output');

function upper_case(string) {
    return string.toUpperCase();
}

/* Test
=== Test Multiline Upper Case
--- input
foo
bar
baz
--- output
FOO
BAR
BAZ

*/
