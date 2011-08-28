/*==============================================================================
YAML - YAML Data Serialization for JavaScript

DESCRIPTION:

This library defines the YAML.dump function which can be used to serialize
JavaScript nodes in YAML.

AUTHORS:

    Ingy döt Net <ingy@cpan.org>

COPYRIGHT:

Copyright Ingy döt Net 2007. All rights reserved.

YAML.js is free software. 

This library is free software; you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation; either version 2.1 of the License, or (at
your option) any later version.

This library is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser
General Public License for more details.

    http://www.gnu.org/copyleft/lesser.txt

 =============================================================================*/

if (! this.YAML) {
    this.YAML = function() {
        this.init();
    }
}

YAML.VERSION = '0.10';

YAML.dump = function() {
    var yaml = new YAML();
    for (var i = 0; i < arguments.length; i++) {
        yaml.dump(arguments[i]);
    }
    return yaml.stream;
}

proto = YAML.prototype;

proto.init = function() {
    this.stream = '';
    this.indent_level = -1;
    this.noindent = false;
}

proto.dump = function(node) {
    this.stream += '---';
    if (!(node instanceof Object))
        this.stream += ' ';
    this.dump_node(node);
}

proto.dump_node = function(node) {
    this.indent_level++;
    if (node instanceof Object) {
        if (! this.noindent)
            this.stream += '\n';
        if (node instanceof Array) {
            this.dump_seq(node);
        }
        else {
            this.dump_map(node);
        }
    }
    else {
        this.dump_scalar(node);
        this.stream += '\n';
    }
    this.indent_level--;
}

proto.dump_map = function(node) {
    try { for (var k in node) throw(null); throw('empty') }
    catch(e) { if (e) return this.dump_map_empty() }
    for (var k in node) {
        this.print_indent();
        this.dump_scalar(k);
        this.stream += ':';
        if (!(node[k] instanceof Object))
            this.stream += ' ';
        if (node[k] instanceof Array) {
            this.indent_level--;
            this.dump_node(node[k]);
            this.indent_level++;
        }
        else
            this.dump_node(node[k]);
    }
}

proto.dump_map_empty = function() {
    this.stream = this.stream.replace(/\n$/, '');
    this.stream += ' {}\n';
    this.noindent = false;
    return;
}

proto.dump_seq = function(node) {
    if (node.length == 0)
        return this.dump_seq_empty();
    for (var e = 0; e < node.length; e++) {
        this.print_indent_array();
        if (!(node[e] instanceof Object))
        this.stream += ' ';
        if ((node[e] instanceof Object))
            this.noindent = true;
        this.dump_node(node[e]);
    }
}

proto.dump_seq_empty = function() {
    this.stream = this.stream.replace(/\n$/, '');
    this.stream += ' []\n';
    this.noindent = false;
    return;
}

proto.dump_scalar = function(node) {
    if ((node == null) || (typeof(node) == 'undefined'))
        return this.dump_scalar_null();
    if (typeof(node) == 'boolean')
        return this.dump_scalar_plain(node);
    var str = node.toString();
    if (str.match(/\n/) ||
        (str.match(/[\xa0]/))
    ) return this.dump_scalar_double(str);
    if (
        (str.length == 0) ||
        (str.match(/(^[ !@#%&*|\{\[]| $)/)) ||
        (str.match(/^(~|true|false|null)$/)) ||
        (str.match(/: /))
    ) return this.dump_scalar_single(str);
    this.dump_scalar_plain(node);
}

proto.dump_scalar_plain = function(node) {
    this.stream += node.toString();
}

proto.dump_scalar_double = function(str) {
    str = str.
        replace(/\n/g, '\\n').
        replace(/"/g, '\\"').
        replace(/\xa0/g, '\\xa0');
    this.stream += '"' + str + '"';
}

proto.dump_scalar_single = function(str) {
    str = str.
        replace(/'/g, "''");
    this.stream += "'" + str + "'";
}

proto.dump_scalar_null = function(str) {
    this.stream += '~';
}

proto.print_indent = function() {
    if (this.noindent) {
        this.stream += ' ';
        this.noindent = false;
        return;
    }
    var n = this.indent_level;
    for (var i = 0; i < n; i++) {
        this.stream += '  ';
    }
}

proto.print_indent_array = function() {
    if (this.noindent) {
        this.stream += ' -';
        this.noindent = false;
        return;
    }
    var n = this.indent_level;
    for (var i = 0; i < n; i++) {
        this.stream += '  ';
    }
    this.stream += '-';
}

this.yyy = function() {
    return YAML.dump.apply(YAML, arguments);
}

this.YYY = function(obj) {
    XXX(yyy.apply(this, arguments));
    return obj;
}

