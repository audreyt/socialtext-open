/*
GuiEdit.js

COPYRIGHT NOTICE:
    Copyright (c) 2004-2005 Socialtext Corporation 
    235 Churchill Ave 
    Palo Alto, CA 94301 U.S.A.
    All rights reserved.
/*

/*
    Originally inspired by WikiEdit 
      by Roman "Kukutz" Ivanov <thingol@mail.ru>
      http://wackowiki.com/WikiEdit

*/

// XXX refactor this to include spacers so we can generate
// the toolbar from this info
var button_names = {
    "bold" : loc("Bold"),
    "italic" : loc("Italic"),
    "strike" : loc("Strikethrough"),
    "h1" : loc("Heading 1"),
    "h2" : loc("Heading 2"),
    "h3" : loc("Heading 3"),
    "ul" : loc("Bullets"),
    "ol" : loc("Numbering"),
    "indent" :  loc("Increase Indent"),
    "outdent" : loc("Decrease Indent"),
    "filew" : loc("Insert attachment"),
    "image" : loc("Insert image"),
    "wikilink" :  loc("Insert Socialtext link"),
    "createlink" :  loc("Insert web link"),
    "createtable" : loc("Insert table")
};

var table_markup = '* | *col b* | *col c* |\n| cell a1 | cell b1 | cell c1 |\n|         |         |         |\n'

var phrase_end_re = /[\s\.\:\;\,\!\?\(\)]/

var GuiEdit = function() {
    this.buttons = new Array()
}

GuiEdit.prototype = new GuiEdit()
GuiEdit.prototype.constructor = GuiEdit

GuiEdit.prototype.init = function(id, name, nameClass, imgPath) {
    if (!(Browser.runs_gui_toolbar)) return

    this.id = id
    this.area = document.getElementById(id)
    this.area._owner = this

    if (Browser.isIE) {
        this.area.addBehavior(nlw_make_s2_path('/javascript/sel.htc'))
    }

    this.imagesPath = (imgPath ? imgPath : "images/")
    this.editorName = name
    this.editorNameClass = nameClass
   
    this.addTestButtons()
    this.makeButton("bold")
    this.makeButton("italic")
    this.makeButton("strike")
    this.makeSpacer()
    this.makeButton("h1")
    this.makeButton("h2")
    this.makeButton("h3")
    this.makeSpacer()
    this.makeButton("ul")
    this.makeButton("ol")
    this.makeSpacer()
    this.makeButton("indent")
    this.makeButton("outdent")
    this.makeSpacer()
    this.makeButton("filew")
    this.makeButton("image")
    this.makeSpacer()
    this.makeButton("wikilink")
    this.makeButton("createlink")
    this.makeSpacer()
    this.makeButton("createtable")
   
    try {
        var toolbar = document.createElement("div")
        toolbar.id = "tb_" + this.id
        this.area.parentNode.insertBefore(toolbar, this.area)
        toolbar = document.getElementById("tb_" + this.id)
        toolbar.innerHTML = this.createToolbar(1)
    } 
    catch(e){}
}

GuiEdit.prototype.addTestButtons = function() {
}

GuiEdit.prototype.createToolbar = function (id, width, height, readOnly) {
    var html = '<table id="buttons_' + id + 
           '" cellpadding="1" cellspacing="0" class="toolbar">' + '  <tr>'
    if (this.editorName) 
        html += '<td class="' + this.editorNameClass + '">' + 
                this.editorName + '</td>'
 
    for (var i = 0; i<this.buttons.length; i++) {
        var btn = this.buttons[i]
        if (btn.name==" ")
            html += ' <td>&nbsp;</td>\n'
        else
            html += this.createButtonHTML(btn, id)
    }
    html += '</tr></table>\n'
 
    return html
}

GuiEdit.prototype.highlightImage = function (element) {
    element.style.borderTop = "thin solid white"
    element.style.borderRight = "thin solid gray"
    element.style.borderBottom = "thin solid gray"
    element.style.borderLeft = "thin solid white"
    return true
}

GuiEdit.prototype.indentImage = function (element) {
    element.style.borderTop = "thin solid gray"
    element.style.borderRight = "thin solid white"
    element.style.borderBottom = "thin solid white"
    element.style.borderLeft = "thin solid gray"
    return true
}

GuiEdit.prototype.cleanImage = function (element) {
    element.style.border = "thin solid white"
    return true
}

GuiEdit.prototype.createButtonHTML = function(button, id) {
    return ' <td><div id="'
           + button.name + '_' + id 
           + '" onmouseover="ge.highlightImage(this);" '
           + 'onmouseout="ge.cleanImage(this);" class="btn-" '
           + 'onclick="ge.indentImage(this);ge.' 
           + button.actionName + '()"><img src="' + this.imagesPath 
           + button.name + '.gif" ' 
           + ' alt="' + button.title + '" title="' + button.title 
           + '"></div></td>\n'
}

GuiEdit.prototype.makeSpacer = function() {
    var i = this.buttons.length
    this.buttons[i] = new Object()
    this.buttons[i].name = " "
}

GuiEdit.prototype.makeButton = function(name) {
    var i = this.buttons.length
    this.buttons[i] = new Object()
    this.buttons[i].name = name
    this.buttons[i].actionName = "do_" + name
    this.buttons[i].image = this.imagesPath + name + ".gif"
    this.buttons[i].title = this.name_to_title(name)
}

GuiEdit.prototype.name_to_title = function(name) {
    return button_names[name]
}

// XXX this is getting absurd
GuiEdit.prototype.find_left = function(t, selection_start, matcher) {
    var substring = t.substr(selection_start - 1, 1)
    var nextstring = t.substr(selection_start - 2, 1)
    if (selection_start == 0) 
        return selection_start
    if (substring.match(matcher)) {
        // special case for word.word
        if ((substring != '.') || (nextstring.match(/\s/))) 
            return selection_start
    }
    return this.find_left(t, selection_start - 1, matcher)
}  

GuiEdit.prototype.find_right = function(t, selection_end, matcher) {
    var substring = t.substr(selection_end, 1)
    var nextstring = t.substr(selection_end + 1, 1)
    if (selection_end >= t.length)
        return selection_end
    if (substring.match(matcher)) {
        // special case for word.word
        if ((substring != '.') || (nextstring.match(/\s/)))
            return selection_end
    }
    return this.find_right(t, selection_end + 1, matcher)
}

GuiEdit.prototype.getLines = function() {
    t = this.area
    var selection_start = t.selectionStart
    var selection_end = t.selectionEnd

    if (selection_start == null || selection_end == null)
        return false

    var our_text = t.value.replace(/\r/g, '')
    selection = our_text.substr(selection_start,
        selection_end - selection_start)

    selection_start = this.find_right(our_text, selection_start, /[^\r\n]/)
    selection_end = this.find_left(our_text, selection_end, /[^\r\n]/)

    this.selection_start = this.find_left(our_text, selection_start, /[\r\n]/)
    this.selection_end = this.find_right(our_text, selection_end, /[\r\n]/)
    t.setSelectionRange(selection_start, selection_end)
    t.focus()

    this.start = our_text.substr(0,this.selection_start)
    this.sel = our_text.substr(this.selection_start, this.selection_end -
        this.selection_start)
    this.finish = our_text.substr(this.selection_end, our_text.length)

    return true
}

GuiEdit.prototype.alarm_on = function() {
    var area = this.area
    var background = area.style.background
    area.style.background = '#f88'

    function alarm_off() {
        area.style.background = background
    }

    window.setTimeout(alarm_off, 250)
    area.focus()
}

GuiEdit.prototype.getWords = function() {
    function is_insane(selection) {
        return selection.match(/\r?\n(\r?\n|\*+ |\#+ |\^+ )/)
    }   

    t = this.area
    var selection_start = t.selectionStart
    var selection_end = t.selectionEnd
    if (selection_start == null || selection_end == null)
        return false
        
    var our_text = t.value.replace(/\r/g, '')
    selection = our_text.substr(selection_start,
        selection_end - selection_start)

    selection_start = this.find_right(our_text, selection_start, /(\S|\r?\n)/)
    if (selection_start > selection_end)
        selection_start = selection_end
    selection_end = this.find_left(our_text, selection_end, /(\S|\r?\n)/)
    if (selection_end < selection_start)
        selection_end = selection_start

    if (is_insane(selection)) {
        this.alarm_on()
        return false
    }

    this.selection_start =
        this.find_left(our_text, selection_start, phrase_end_re)
    this.selection_end =
        this.find_right(our_text, selection_end, phrase_end_re)

    t.setSelectionRange(this.selection_start, this.selection_end)
    t.focus()

    this.start = our_text.substr(0,this.selection_start)
    this.sel = our_text.substr(this.selection_start, this.selection_end -
        this.selection_start)
    this.finish = our_text.substr(this.selection_end, our_text.length)

    //this.report_info()

    return true
}

GuiEdit.prototype.report_info = function() {
    alert(loc("selection_start: [_1]", this.selection_start) + "\nselection_end: " +
      this.selection_end + "\nselection: " + this.sel)
}

GuiEdit.prototype.markup_is_on = function(start, finish) {
    return (this.sel.match(start) && this.sel.match(finish))
}

GuiEdit.prototype.clean_selection = function(start, finish) {
    this.sel = this.sel.replace(start, '')
    this.sel = this.sel.replace(finish, '')
}

GuiEdit.prototype.toggle_same_format = function(start, finish) {
    start = this.cleanRE(start)
    finish = this.cleanRE(finish)
    var start_re = new RegExp('^' + start)
    var finish_re = new RegExp(finish + '$')
    if (this.markup_is_on(start_re, finish_re)) {
        this.clean_selection(start_re, finish_re)
        return true
    }
    return false
}

GuiEdit.prototype.cleanRE = function(string) {
    string = string.replace(/([\^\*\[\]\{\}])/g, '\\' + "$1")
    return string
}

GuiEdit.prototype.setTextandSelection = function(text, start, end) {
    this.area.value = text
    this.area.setSelectionRange(start, end)
}

GuiEdit.prototype.addMarkupWords =
function(markup_start, markup_finish, example) {
    if (this.toggle_same_format(markup_start, markup_finish)) {
        this.selection_end = this.selection_end -
            (markup_start.length + markup_finish.length)
        markup_start = ''
        markup_finish = ''
    }
    if (this.sel.length == 0) {
        if (example)
            this.sel = example
        var text = this.start + markup_start +
            this.sel + markup_finish + this.finish
        var start = this.selection_start + markup_start.length
        var end = this.selection_end + markup_start.length + this.sel.length
        this.setTextandSelection(text, start, end)
    } else {
        var text = this.start + markup_start + this.sel +
            markup_finish + this.finish
        var start = this.selection_start
        var end = this.selection_end + markup_start.length +
            markup_finish.length
        this.setTextandSelection(text, start, end)
    }
    this.area.focus()
}

GuiEdit.prototype.addMarkupLines = function(markup_start) {
    var start_pattern = markup_start
    start_pattern = start_pattern.replace(/(\^+) /, '$1')
    var already_set_re = new RegExp("^" + this.cleanRE(start_pattern) + " *",
        'gm')
    var other_markup_re = /^(\^+ *|\* |# )/gm
    if (this.sel.match(already_set_re))
        this.sel = this.sel.replace(already_set_re, '')
    else if (this.sel.match(other_markup_re))
        this.sel = this.sel.replace(other_markup_re, markup_start)
    else if (this.sel.length > 0)
        this.sel = this.sel.replace(/^(.*\S+)/gm, markup_start + '$1')
    else
        this.sel = markup_start
    var text = this.start + this.sel + this.finish
    var start = this.selection_start
    var end = this.selection_start + this.sel.length
    this.setTextandSelection(text, start, end)
    this.area.focus()
}

GuiEdit.prototype.startline = function(markup_start) {
    var scroll_top = this.area.scrollTop
    if (this.getLines())
        this.addMarkupLines(markup_start + ' ')
    this.area.scrollTop = scroll_top
}

GuiEdit.prototype.boundword = function(markup_start, markup_finish, example) {
    var scroll_top = this.area.scrollTop
    // XXX: switching to 'undefined' breaks cleanRE
    if (markup_finish == undefined)
        markup_finish = markup_start
    if (this.getWords())
        this.addMarkupWords(markup_start, markup_finish, example)
    this.area.scrollTop = scroll_top
}


GuiEdit.prototype.do_bold = function() {
    this.boundword('*')
}

GuiEdit.prototype.do_italic = function() {
    this.boundword('_')
}

GuiEdit.prototype.do_strike = function() {
    this.boundword('-')
}

GuiEdit.prototype.do_h1 = function() {
    this.startline('^')
}

GuiEdit.prototype.do_h2 = function() {
    this.startline('^^')
}

GuiEdit.prototype.do_h3 = function() {
    this.startline('^^^')
}

GuiEdit.prototype.do_ol = function() {
    this.startline('#')
}

GuiEdit.prototype.do_ul = function() {
    this.startline('*')
}

GuiEdit.prototype.do_filew = function() {
    this.boundword('{file: ', '}', 'example.doc')
}

GuiEdit.prototype.do_image = function() {
    this.boundword('{image: ', '}', 'image.gif')
}

GuiEdit.prototype.do_wikilink = function() {
    this.boundword('[', ']', loc('type link text here'))
}

GuiEdit.prototype.do_createlink = function() {
    this.boundword('"', '"<http://...>')
}

GuiEdit.prototype.do_dent = function(method) {
    var scroll_top = this.area.scrollTop
    if (! this.getLines()) {
        this.area.scrollTop = scroll_top
        return
    }

    if (method(this)) {
        var text = this.start + this.sel + this.finish
        var start = this.selection_start
        var end = this.selection_start + this.sel.length
        this.setTextandSelection(text, start, end)
    }
    this.area.focus()
}

GuiEdit.prototype.do_indent = function() {
    this.do_dent(
        function(that) {
            if (that.sel == '') return false
            that.sel = that.sel.replace(/^(([\*\-\#])+(?=\s))/gm, '$2$1')
            that.sel = that.sel.replace(/^([\>\^])/gm, '$1$1')
            that.sel = that.sel.replace(/^([^\>\*\-\#\^\r\n])/gm, '> $1')
            that.sel = that.sel.replace(/^\^{7,}/gm, '^^^^^^')
            return true;
        }
    )
}

GuiEdit.prototype.do_outdent = function() {
    this.do_dent(
        function(that) {
            if (that.sel == '') return false
            that.sel = that.sel.replace(/^([\>\*\-\#\^] ?)/gm, '')
            return true;
        }
    )
}

GuiEdit.prototype.do_createtable = function() {
    var t = this.area
    var scroll_top = t.scrollTop
    var selection_start = t.selectionStart
    var text = t.value
    this.selection_start = this.find_right(text, selection_start, /\r?\n/)
    this.selection_end = this.selection_start
    t.setSelectionRange(this.selection_start, this.selection_start)
    t.focus()
    this.sel = 'col a'
    markup_start = '\n| *'
    markup_finish = table_markup

    this.start = t.value.substr(0, this.selection_start)
    this.finish = t.value.substr(this.selection_end, t.value.length)
    var text = this.start + markup_start + this.sel + markup_finish +
        this.finish
    var start = this.selection_start + markup_start.length
    var end = this.selection_end + markup_start.length + this.sel.length
    this.setTextandSelection(text, start, end)
    t.scrollTop = scroll_top
}
