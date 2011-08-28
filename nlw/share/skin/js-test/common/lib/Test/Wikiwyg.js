(function() {

var proto = Test.Base.newSubclass('Test.Wikiwyg');

proto.run_roundtrip = function(section_name, section_name2) {
    if ( Wikiwyg.is_safari ) {
        this.skip("Skip roundtrip tests on Safari");
        return;
    }

    var self = this;

    var t = 10000;
    var id = this.builder.beginAsync(t + 1000);

    setTimeout(function() {
        if (!iframe_loaded)
            return setTimeout(arguments.callee, 300);

        self.run_roundtrip_sync(section_name, section_name2);
        self.builder.endAsync(id)
    }, 300);
}

proto.run_roundtrip_sync = function(section_name, section_name2) {
    try {
        this.compile();
        var blocks =  this.state.blocks;
        for (var i = 0; i < blocks.length; i++) {
            var block = blocks[i];
            if (! this.verify_block(block, section_name)) continue;

            var wikitext = block.data[section_name];
            var wikitext2 = this.do_roundtrip(wikitext);
            if (section_name2)
                wikitext = block.data[section_name2];
                
            this.is(
                wikitext2.replace(/\r/g, ''),
                wikitext.replace(/\r/g, ''),
                block.name
            );

        }
    }
    catch(e) {
        // alert(e);
        throw(e);
    }
}

proto.do_roundtrip = function(wikitext) {
    var html = Test.Wikiwyg.Filter.prototype.wikitext_to_html(wikitext);
    
    if (!this._wysiwyg_object) {
        this._wysiwyg_object = this.create_wysiwyg_object();
    }

    var wysiwygObject = this._wysiwyg_object;
    var html2 = wysiwygObject.fromHtml(html);

    var wikitextObject = new Wikiwyg.Wikitext();
    wikitextObject.wikiwyg = wysiwygObject.wikiwyg;
    wikitextObject.set_config();
    wikitextObject.initializeObject();
    return wikitextObject.convert_html_to_wikitext(html2);
}

proto.create_wysiwyg_object = function(html) {
    var wikiwyg = new Wikiwyg();
    wikiwyg.set_config();
    var wysiwyg = new Wikiwyg.Wysiwyg();
    wysiwyg.show_messages = function() {};
    wysiwyg.config.iframeId = "wikiwyg_iframe";
    wysiwyg.wikiwyg = wikiwyg;
    wysiwyg.initializeObject();
    return wysiwyg;
}


proto.run_like = function(x, y) {
    try {
        this.compile();
        var blocks =  this.state.blocks;
        for (var i = 0; i < blocks.length; i++) {
            var block = blocks[i];
            if (! this.verify_block(block, x, y)) continue;
            this.like(block.data[x], block.data[y], block.name);
        }
    }
    catch(e) {
        // alert(e);
        throw(e);
    }
}



var proto = Test.Wikiwyg.Filter.prototype;

function _make_wrappers (base, methods) {
    for (var idx in methods) {
        (function(name, method){
            proto[name] = function(content) {
                var object = new (eval(base))();
                if (object && object[method]) {
                    return object[method](content);
                }
            };
        })(idx, methods[idx] || idx);
    }
};

_make_wrappers(
    'Wikiwyg.Wysiwyg',
    { replace_p_with_br: null }
);
_make_wrappers(
    'Wikiwyg.Wikitext',
    { html_to_wikitext: 'convert_html_to_wikitext' }
);

proto.wikitext_to_html = function(wikitext) {
    var url = '/admin/index.cgi';
    var postdata = 'action=wikiwyg_wikitext_to_html;content=' +
        encodeURIComponent(wikitext);

    return Ajax.post(
        url,
        postdata,
        null,
        {
            userid: 'devnull1@socialtext.com',
            passwd: 'd3vnu11l'
        }
    );
}

proto.wikitext_to_html_js = function(wikitext) {
    return ((new Document.Parser.Wikitext()).parse(wikitext, new Document.Emitter.HTML()) + "\n");
}

proto.template_vars = function(content) {
    return content.replace(
        /\[\%BASE_URL\%\]/g,
        (window.location + '').replace(/\/static\/.*/, '/')
    ).replace(
        /\[\%THIS_URL\%\]/g,
        window.location
    );
}

proto.dom_sanitize  = function(content) {
    var html = content;
    var dom = document.createElement('div');
    dom.innerHTML = html;
    (new Wikiwyg.Wikitext()).normalizeDomStructure(dom);
    var html2 = dom.innerHTML;
    if (! html2.match(/\n$/))
        html2 += '\n';
    return html2;
}

proto.trim = function(content, block) {
    var result = content.replace(/^\s*\n/, '');
    result = result.replace(/\n\s*$/, '\n').replace(new RegExp(String.fromCharCode(0x2424), 'g'), '\n');
    return result;
}


})();
