// namespace placeholder
if (typeof ST == 'undefined') {
    ST = {};
}

ST.isRelative = function(node) {
    return node.style.position == 'relative' || node.style.position == 'absolute' || node.style.position == 'fixed';
}

ST.getRadioValue = function(name) {
    var nodes = document.getElementsByName(name);
    for (var i=0; i < nodes.length; i++)
        if (nodes[i].checked)
            return nodes[i].value;
    return '';
}

ST.setRadioValue = function(name, value) {
    var nodes = document.getElementsByName(name);
    for (var i=0; i < nodes.length; i++) {
        if (nodes[i].value == value) {
            nodes[i].checked = true;
            return;
        }
    }
}

// Function from Javascript: The Definitive Guide
ST.getDocumentX = function(e, is_relative) {
    var x = 0;
    while (e) {
        x+= e.offsetLeft;
        e = e.offsetParent;
        if (e && is_relative && ST.isRelative(e))
            e = null;
    }
    return x;
}

ST.getDocumentY = function(e, is_relative) {
    var y = 0;
    while (e) {
        y += e.offsetTop;
        e = e.offsetParent;
        if (e && is_relative && ST.isRelative(e))
            e = null;
    }
    return y;
}

/**
 * A function used to extend one class with another
 *
 * @author Kevin Lindsey
 * @version 1.0
 *
 * copyright 2006, Kevin Lindsey
 *
 *
 * @param {Object} subClass
 * 		The inheriting class, or subclass
 * @param {Object} baseClass
 * 		The class from which to inherit
 */
ST.extend = function(subClass, baseClass) {
   function inheritance() {}
   inheritance.prototype = baseClass.prototype;

   subClass.prototype = new inheritance();
   subClass.prototype.constructor = subClass;
   subClass.baseConstructor = baseClass;
   subClass.superClass = baseClass.prototype;
}

function help_popup(url, width, height, left, top) {
    if (!width) width = 520;
    if (!height) height = 300;
    if (!left) left = 400-width/2;
    if (!top) top = 280-height/2;
    window.open(url, '_blank', 'toolbar=no, location=no, directories=no, status=no, menubar=no, titlebar=no, scrollbars=yes, resizable=yes, width=' + width + ', height=' + height + ', left=' + left + ', top=' + top);
}

function trim(value) {
    var ltrim = /\s*((\s*\S+)*)/;
    var rtrim = /((\s*\S+)*)\s*/;
    return value.replace(rtrim, "$1").replace(ltrim, "$1");
};

function is_reserved_pagename(pagename) {
    if (pagename && pagename.length > 0) {
        var name = nlw_name_to_id(trim(pagename));
        var untitled = nlw_name_to_id(loc('Untitled Page'))
        return name == untitled;
    }
    else {
        return false;
    }
}

