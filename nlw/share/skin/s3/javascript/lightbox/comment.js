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

var table_markup = '* | *col b* | *col c* |\n| cell a1 | cell b1 | cell c1 |\n|         |         |         |\n'
var phrase_end_re = /[\s\.\:\;\,\!\?\(\)]/

var GuiEdit = function(args) {
    args = args || {};
    this.workspace = args.workspace || Socialtext.wiki_id;
    this.page_id = args.page_id || Socialtext.page_id;
    this.oncomplete = args.oncomplete;
    this.onclose = args.onclose;
    this.id = args.id;
    if (!this.id)
        throw new Error ('GuiEdit requires an id!');
    this.container = jQuery('#'+this.id);
    if (!this.container.size())
        throw new Error ('No elements found with id='+this.id);
}

GuiEdit.prototype = {};

GuiEdit.prototype.show = function () {
    var self = this;

    Socialtext.loc = loc;
    Socialtext.s2_path = nlw_make_s2_path;

    this.container.append(
        Jemplate.process('comment.tt2', Socialtext)
    );

    jQuery('.commentWrapper', this.container).bind('dblclick', function () {
        return false;
    });

    jQuery('.comment_button')
        .css({
            'cursor': 'pointer',
            'border': 'thin solid white'
        })
        .mouseover(function () {
            jQuery(this).css({
                borderTop: "thin solid white",
                borderRight: "thin solid gray",
                borderBottom: "thin solid gray",
                borderLeft: "thin solid white"
            });
        })
        .mouseout(function () {
            jQuery(this).css('border', 'thin solid white');
        })
        .click(function () { self['do_'+this.name].call(self) })

    jQuery('.saveButton', this.container).click(function () {
        var $saveButton = $(this);
        if ($saveButton.parent().is('.disabled')) { return; }
        $saveButton.parent().addClass('disabled').addClass('loading');

        var doSignal = $('#st-comment-st-edit-summary-signal-checkbox').is(':checked');
        jQuery.ajax({
            url: '/' + self.workspace + '/index.cgi?action=submit_comment',
            type: 'POST',
            data: {
                action: 'submit_comment',
                page_name: self.page_id,
                comment: jQuery('textarea', self.container).val(),
                signal_comment_to_network: doSignal ? $('#st-comment-st-edit-summary-signal-to').val() : ''
            },
            success: function () {
                if (self.oncomplete) {
                    self.oncomplete.call(self);
                }
                self.close();
            },
            error: function() {
                alert(loc("error.save-failed"));
                $saveButton.parent().removeClass('disabled').removeClass('loading');
            }
        });
        return false;
    });

    jQuery('.cancelButton', this.container).click(function () {
        self.close();
        return false;
    });

    jQuery('textarea', this.container).val('');
    this.area = jQuery('textarea', this.container).get(0);

    if (this.area.addBehavior) {
        this.area.addBehavior(nlw_make_s3_path('/javascript/Selection.htc'));
    }

    if ($('#st-comment-signal_network').size() > 0) {
        Socialtext.show_signal_network_dropdown('st-comment-', '200px');
    }

    this.scrollTo(function () {
        jQuery('.comment', self.container).fadeIn(
            'normal',
            function() {
                jQuery('textarea', self.container).focus();
            }
        );
    });
}

GuiEdit.prototype.close = function () {
    var self = this;
    jQuery('.comment', this.container).fadeOut(function () {
        jQuery('.commentWrapper', self.container).remove();

        if (self.onclose) {
            self.onclose.call(self);
        }
    });
}

GuiEdit.prototype.scrollTo = function (callback) {
    // Scroll the window so that the middle of .commentWrapper is in the
    // middle of the screen
    var wrapper = jQuery('.commentWrapper', this.container);
    var offset = wrapper.offset().top;

    // Workaround jQuery+IE bug in {bz: 5265}; may revisit later with jQuery 1.6
    if ($.browser.msie && $('div.syntaxhighlighter').length) {
        document.body.scrollTop = offset;
        callback();
    }
    else {
        $('html,body').animate({scrollTop: offset}, 'normal', 'linear', callback);
    }
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

GuiEdit.prototype.report_info = function() {
    alert("selection_start: " + this.selection_start + "\nselection_end: " +
      this.selection_end + "\nselection: " + this.sel)
}

GuiEdit.prototype.markup_is_on = function(start, finish) {
    return (this.sel.match(start) && this.sel.match(finish))
}

GuiEdit.prototype.setTextandSelection = function(text, start, end) {
    this.area.value = text;

    if (this.area.createTextRange) {
        var range = this.area.createTextRange();

        range.moveEnd("textedit", -1);
        range.moveEnd("character", end);
        range.moveStart("character", start);
        range.select();
    }
    else if (this.area.setSelectionRange) {
        this.area.setSelectionRange(start, end)
    }
}

GuiEdit.prototype.cleanRE = function(string) {
    string = string.replace(/([\^\*\[\]\{\}])/g, '\\' + "$1")
    return string
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

GuiEdit.prototype.clean_selection = function(start, finish) {
    this.sel = this.sel.replace(start, '');
    this.sel = this.sel.replace(finish, '');
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

GuiEdit.prototype.boundword = function(markup_start, markup_finish, example) {
    var scroll_top = this.area.scrollTop
    // XXX: switching to 'undefined' breaks cleanRE
    if (markup_finish == undefined)
        markup_finish = markup_start
    if (this.getWords())
        this.addMarkupWords(markup_start, markup_finish, example)
    this.area.scrollTop = scroll_top
}

GuiEdit.prototype.getWords = function() {
    function is_insane(selection) {
        return selection.match(/\r?\n(\r?\n|\*+ |\#+ |\^+ )/)
    }   

    t = this.area
    var selection_start = t.selectionStart
    var selection_end = t.selectionEnd

    if (selection_start == null && selection_end != null)
        selection_start = selection_end;

    else if (selection_start == null || selection_end == null)
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


GuiEdit.prototype.find_right = function(t, selection_end, matcher) {
    if (selection_end < 0 || !selection_end) return 0;

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
    this.boundword('[', ']', loc('comment.type-link'))
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
    var selection_start = t.selectionStart || t.selectionEnd;
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

    if (jQuery.browser.msie) {
        var offset = this.start.match(/\r/g);
        offset = offset ? offset.length : 0;
        start -= offset;
        end -= offset;
    }

    this.setTextandSelection(text, start, end)
    t.scrollTop = scroll_top
}

