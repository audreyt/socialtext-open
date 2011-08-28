function XXX(val) {
    if (
        typeof(console) != 'undefined' &&
        typeof(console.log) != 'undefined'
    ) {
        console.log.apply(this, arguments);
    }
    else {
        var msg = '';
        for (var i = 0, l = arguments.length; i < l; i++) {
            msg += arguments[0] + '\n';
        }
        if (confirm(msg) == false)
            throw("Execution cancelled");
    }
    return val;
}

function jjj(obj) {
    return JSON.stringify(obj).replace(/[:,][\{\[]/g, ':\n{');
}

function JJJ(obj) {
    XXX(jjj(obj));
    return obj;
}

function CYYY(obj) {
    return YYY(copyDom(obj));
}

// Copy a dom element into a YAML dumpable structure
copyDom = function(element) {
    var node = new Object;

    node.nodeName = element.nodeName;
    var types = [
        'is_widget', 'widget_on_widget', 'wikitext', 'top_level_block'
    ];
    for (var i = 0; i < types.length; i++) {
        var type = types[i];
        if (typeof(element[type]) != 'undefined')
            node[type] = element[type];
    }

    node.nodeType = element.nodeType;
    if (element.nodeType == 1) {
        var alt = element.getAttribute('alt');
        if (alt)
            node.alt = alt;
        var style = element.getAttribute('style');
        if (style)
            node.style = style;
        var className = element.className;
        if (className)
            node.className = className;
        if (style)
            node.style = style;
        var widget = element.getAttribute('widget');
        if (widget)
            node.widget = widget;
        if (element.nodeName == 'A') {
            node.innerHTML = element.innerHTML;
            node.href = element.getAttribute('href');
        }
    }
    else if (element.nodeType == 3 || element.nodeType == 8) {
        node.nodeValue = element.nodeValue;
        if (element.nodeType == 8)
            node.data = node.nodeValue;
    }

    for (var part = element.firstChild; part; part = part.nextSibling) {
        if (part.nodeType == 3) {
            if (!(part.nodeValue.match(/[^\n]/) &&
                ! part.nodeValue.match(/^\n[\n\ \t]*$/)
               )) continue;
        }
        if (! node.children)
            node.children = [];
        var copy = copyDom(part);
        node.children.push(copy);
    }
    return node;
}
;
