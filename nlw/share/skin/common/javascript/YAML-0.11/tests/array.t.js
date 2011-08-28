var t = new Test.YAML();

var filters = {
    javascript: 'eval_dump_js',
};

t.plan(4);
t.filters(filters);
t.run_is('javascript', 'yaml');

/* Test
=== Simple array
+++ javascript
foo = [5, 9, 11]
+++ yaml
---
- 5
- 9
- 11

=== Array with a hash
+++ javascript
foo = [2, { x: 'y', y: 'x'}, 4]
+++ yaml
---
- 2
- x: y
  y: x
- 4

=== Array with an array
+++ javascript
foo = [2, [5, 4, 3], 4]
+++ yaml
---
- 2
- - 5
  - 4
  - 3
- 4

=== Hash with an arrays
+++ javascript
foo = { 
    foo: [2, [5, 3]], 
    bar: [ 
        {blah: 'baby', bah: 'maybe'},
        {
            duh: [
                {
                    dude: [ { blam: 99, bam: true}, 100 ],
                    dang: false
                },
                42,
                null,
                '~'
            ]
        }
    ]
}
+++ yaml
---
foo:
- 2
- - 5
  - 3
bar:
- blah: baby
  bah: maybe
- duh:
  - dude:
    - blam: 99
      bam: true
    - 100
    dang: false
  - 42
  - ~
  - '~'


*/
