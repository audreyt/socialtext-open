var t = new Test.YAML();

var filters = {
    javascript: 'eval_dump_js',
};

t.plan(5);
t.filters(filters);
t.run_is('javascript', 'yaml');

/* Test
=== Simple hash with one entry
+++ javascript
foo = {"name":"Wally"}
+++ yaml
---
name: Wally

=== Simple hash with many entries
+++ javascript
hash = {};
hash.a = 1;
hash.b = 2;
hash.c = 3;
hash;
+++ yaml
---
a: 1
b: 2
c: 3

=== Hash of Hashes
+++ javascript
hash = {
    foo: { color: 'red', size: 12 },
    bar: { color: 'blue', size: 21 }
};
+++ yaml
---
foo:
  color: red
  size: 12
bar:
  color: blue
  size: 21

=== Empty Things
+++ javascript
hash = {
    map: {},
    sub: { seq: [] },
    str: '',
    none: null
};
+++ yaml
---
map: {}
sub:
  seq: []
str: ''
none: ~

=== Quoted Things
+++ javascript
hash = {
    tilde: '~',
    'curly brace': '{}',
    'square bracket': '[...]',
    pipe: '|',
    space1: ' foo',
    space2: 'bar  ',
    comment: '# I were here',
    empty: '',
    spaces: '   ',
    '   ': 'spaces',
    'true': 'true',
    'false': 'false',
    'null': 'null',
    'a: b': 'c: d'
}
+++ yaml
---
tilde: '~'
curly brace: '{}'
square bracket: '[...]'
pipe: '|'
space1: ' foo'
space2: 'bar  '
comment: '# I were here'
empty: ''
spaces: '   '
'   ': spaces
'true': 'true'
'false': 'false'
'null': 'null'
'a: b': 'c: d'

*/
