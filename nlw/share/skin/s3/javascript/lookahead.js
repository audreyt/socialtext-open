(function($){
    var SELECTED_COLOR = '#CCC';
    var BG_COLOR = '#EEE';
    var lookaheads = [];

    var hastyped = false;

    var DEFAULTS = {
        count: 10,
        filterName: 'filter',
        filterType: 'sql',
        requireMatch: false,
        params: { 
            order: 'alpha',
            count: 30, // for fetching
            minimal: 1
        }
    };

    var FILTER_TYPES = {
        plain: '$1',
        sql: '\\b$1',
        solr: '$1* OR $1'
    };

    var KEYCODES = {
        DOWN: 40,
        UP: 38,
        ENTER: 13,
        SHIFT: 16,
        ESC: 27,
        TAB: 9
    };

    Lookahead = function (input, opts) {
        if (!input) throw new Error("Missing input element");
        if (!opts.url) throw new Error("url missing");
        if (!opts.linkText) throw new Error("linkText missing");

        var targetWindow = opts.getWindow && opts.getWindow();
        if (targetWindow) {
            this.window = targetWindow;
            this.$ = targetWindow.jQuery;
        }
        else {
            this.window = window;
            this.$ = jQuery;
        }

        this._items = [];
        this.input = input;
        this.opts = $.extend(true, {}, DEFAULTS, opts); // deep extend
        var self = this;

        if (this.opts.clickCurrentButton) {
            this.opts.clickCurrentButton.unbind('click').click(function() {
                self.clickCurrent();
                return false;
            });
        }

        $(this.input)
            .attr('autocomplete', 'off')
            .unbind('keyup')
            .keyup(function(e) {
                if (e.keyCode == KEYCODES.ESC) {
                    $(input).val('').blur();
                    self.clearLookahead();
                }
                else if (e.keyCode == KEYCODES.ENTER) {
                    if (self.opts.requireMatch) {
                        if (self._items.length) {
                            self.clickCurrent();
                        }
                    }
                    else {
                        self.acceptInputValue();
                    }
                }
                else if (e.keyCode == KEYCODES.DOWN) {
                    self.selectDown();
                }
                else if (e.keyCode == KEYCODES.UP) {
                    self.selectUp();
                }
                else if (e.keyCode != KEYCODES.TAB && e.keyCode != KEYCODES.SHIFT) {
                    self.onchange();
                }
                return false;
            })
            .unbind('keydown')
            .keydown(function(e) {
                if (!self.hastyped) {
                    self.hastyped=true;
                    if (self.opts.onFirstType) {
                        self.opts.onFirstType($(self.input));
                    }
                }
                if (self.lookahead && self.lookahead.is(':visible')) {
                    if (e.keyCode == KEYCODES.TAB) {
                        // tab complete rather than select
                        self.selectDown();
                        return false;
                    }
                    else if (e.keyCode == KEYCODES.ENTER) {
                        return false;
                    }
                }
            })
            .unbind('blur')
            .blur(function(e) {
                setTimeout(function() {
                    if (self._accepting) {
                        self._accepting = false;
                        $(self.input).focus();
                    }
                    else {
                        self.clearLookahead();
                        if ($.isFunction(self.opts.onBlur)) {
                            self.opts.onBlur(action);
                        }
                    }
                }, 50);
            });

        this.allowMouseClicks();
    }

    $.fn.lookahead = function(opts) {
        this.each(function(){
            this.lookahead = new Lookahead(this, opts); 
            lookaheads.push(this.lookahead);
        });

        return this;
    };

    $.fn.abortLookahead = function() {
        this.each(function() {
            this.lookahead.abort();
        });
    }

    Lookahead.prototype = {
        'window': window,
        '$': window.$
    };

    Lookahead.prototype.allowMouseClicks = function() { 
        var self = this;

        var elements = [ this.getLookahead() ];
        if (this.opts.allowMouseClicks)
            elements.push(this.opts.allowMouseClicks);

        $.each(elements, function () {
            $(this).unbind('mousedown').mousedown(function() {
                // IE: Use _accepting to prevent onBlur
                if ($.browser.msie) self._accepting = true;
                $(self.input).focus();
                // Firefox: This works because this is called before blur
                return false;
            });
        });
    };

    Lookahead.prototype.clearLookahead = function () {
        this._cache = {};
        this._items = [];
        this.hide();
    };

    Lookahead.prototype.getLookahead = function () {
        /* Subract the offsets of all absolutely positioned parents
         * so that we can position the lookahead directly below the
         * input element. I think jQuery's offset function should do
         * this for you, but maybe they'll fix it eventually...
         */
        var left = $(this.input).offset().left;
        var top = $(this.input).offset().top + $(this.input).height() + 10;

        if (this.window !== window) {
            // XXX: container specific
            var offset = this.$('iframe[name='+window.name+']').offset();
            if (offset) {
                left += offset.left;
                top += offset.top;
            }

            // Map unload to remove the lookahead, otherwise it can hang
            // around after we move a widget
            var self = this;
            $(window).unload(function() {
                self.lookahead.remove();
            });
        }

        if (!this.lookahead) {
            this.lookahead = this.$('<div></div>')
                .hide()
                .css({
                    textAlign: 'left',
                    zIndex: 3001,
                    position: 'absolute',
                    display: 'none', // Safari needs this explicitly: {bz: 2431}
                    background: BG_COLOR,
                    border: '1px solid black',
                    padding: '0px'
                })
                .prependTo('body');

            this.$('<ul></ul>')
                .css({
                    listStyle: 'none',
                    padding: '0',
                    margin: '0'
                })
                .appendTo(this.lookahead);

        }

        this.lookahead.css({
            left: left + 'px',
            top: top + 'px'
        });

        return this.lookahead;
    };

    Lookahead.prototype.getLookaheadList = function () {
        return this.$('ul', this.getLookahead());
    };

    Lookahead.prototype.linkTitle = function (item) {
        var lt = this.opts.linkText(item);
        return typeof (lt) == 'string' ? lt : lt[0];
    };

    Lookahead.prototype.linkDesc = function (item) {
        var lt = this.opts.linkText(item);
        return typeof (lt) == 'string' ? '' : lt[2];
    };

    Lookahead.prototype.linkValue = function (item) {
        var lt = this.opts.linkText(item);
        return typeof (lt) == 'string' ? lt : lt[1];
    };

    Lookahead.prototype.filterRE = function (val) {
        var pattern = '(' + val + ')';

        if (/^\w/.test(val)) {
            pattern = "\\b" + pattern;
        }

        return new RegExp(pattern, 'ig');
    };
    
    Lookahead.prototype.filterData = function (val, data) {
        var self = this;

        var filtered = [];
        var re = this.filterRE(val);

        $.each(data, function(i, item) {
            if (filtered.length >= self.opts.count) {
                if (self.opts.showAll) {
                    filtered.push({
                        title: loc("lookahead.all-results"),
                        displayAs: val,
                        noThumbnail: true,
                        onAccept: function() {
                            self.opts.showAll(val)
                        }
                    });
                    return false; // Break out of the $.each loop
                }
                return;
            }

            var title = self.linkTitle(item);
            var desc = self.linkDesc(item) || '';

            if (title.match(re) || desc.match(re)) {
                if (self.opts.grep && !self.opts.grep(item)) return;

                /* Add <b></b> and escape < and > in original text */
                var _Mark_ = String.fromCharCode(0xFFFC);
                var _Done_ = String.fromCharCode(0xFFFD);

                filtered.push({
                    bolded_title: title.replace(re, _Mark_ + '$1' + _Done_)
                        .replace(/</g, "&lt;")
                        .replace(/>/g, "&gt;")
                        .replace(new RegExp(_Mark_, 'g'), '<b>')
                        .replace(new RegExp(_Done_, 'g'), '</b>'),
                    title: title,
                    bolded_desc: desc.replace(re, _Mark_ + '$1' + _Done_)
                        .replace(/</g, "&lt;")
                        .replace(/>/g, "&gt;")
                        .replace(new RegExp(_Mark_, 'g'), '<b>')
                        .replace(new RegExp(_Done_, 'g'), '</b>'),
                    desc: desc,
                    value: self.linkValue(item),
                    orig: item
                });
            }
        });

        return filtered;
    };

    Lookahead.prototype.displayData = function (data) {
        var self = this;
        this._items = data;
        var lookaheadList = this.getLookaheadList();
        lookaheadList.html('');

        if (data.length) {
            $.each(data, function (i) {
                var item = this || {};
                var li = self.$('<li></li>')
                    .css({
                        padding: '3px 5px',
                        height: '15px', // overridden when there are thumbnails
                        lineHeight: '15px',
                        'float': 'left',
                        'clear': 'both'
                    })
                    .appendTo(lookaheadList);
                if (self.opts.getEntryThumbnail && !item.noThumbnail) {
                    // lookaheads with thumbnails are taller
                    li.height(30);
                    if (!item.desc) li.css('line-height', '30px');

                    var src = self.opts.getEntryThumbnail(item); 
                    self.$('<img/>')
                        .css({
                            'vertical-align': 'middle',
                            'marginRight': '5px',
                            'border': '1px solid #666',
                            'cursor': 'pointer',
                            'float': 'left',
                            'width': '27px',
                            'height': '27px'
                        })
                        .click(function() {
                            self.accept(i);
                            return false;
                        })
                        .attr('src', src)
                        .appendTo(li);
                }
                self.itemNode(item, i).appendTo(li);
            });
            this.show();
        }
        else {
            lookaheadList.html('<li></li>');
            $('li', lookaheadList)
                .text(loc("error.no-match=lookahead", $(this.input).val()))
                .css({padding: '3px 5px'});
            this.show();
        }
    };

    Lookahead.prototype.itemNode = function(item, index) {
        var self = this;
        var $node = self.$('<div class="lookaheadItem"></div>')
            .css({ 'float': 'left' });

        $node.append(
            self.$('<a href="#"></a>')
                .css({ whiteSpace: 'nowrap' })
                .html(item.bolded_title || item.title)
                .attr('value', index)
                .click(function() {
                    self.accept(index);
                    return false;
                })
        );

        if (item.desc) {
            $node.append(
                self.$('<div></div>')
                    .html(item.bolded_desc)
                    .css('whiteSpace', 'nowrap')
            );
        }
        return $node
    };

    Lookahead.prototype.show = function () {
        var self = this;

        var lookahead = this.getLookahead();
        if (!lookahead.is(':visible')) {
            lookahead.fadeIn(function() {
                self.allowMouseClicks();
                if ($.isFunction(self.opts.onShow)) {
                    self.opts.onShow();
                }
            });
        }

        // IE6 iframe hack:
        // Enabling the select overlap breaks clicking on the lookahead if the
        // lookahead is inserted into a different window.
        // NOTE: We cannot have "zIndex:" here, otherwise elements in the
        // lookahead become unclickable and causes {bz: 2597}.
        if (window === this.window)
            this.lookahead.createSelectOverlap({ padding: 1 });
    };

    Lookahead.prototype.hide = function () {
        var lookahead = this.getLookahead();
        if (lookahead.is(':visible')) {
            lookahead.fadeOut();
        }
    };

    Lookahead.prototype.acceptInputValue = function() {
        var value = $(this.input).val();
        this.clearLookahead();

        if (this.opts.onAccept) {
            this.opts.onAccept.call(this.input, value, {});
        }
    };

    Lookahead.prototype.accept = function (i) {
        if (!i) i = 0; // treat undefined as 0
        var item;
        if (arguments.length) {
            item = this._items[i];
            this.select(item);
        }
        else if (this._selected) {
            // Check if we are displaying the last selected value
            if (this.displayAs(this._selected) == $(this.input).val()) {
                item = this._selected;
            }
        }

        var value = item ? item.value : $(this.input).val();

        this.clearLookahead();

        if (item.onAccept) {
            item.onAccept.call(this.input, value, item);
        }
        else if (this.opts.onAccept) {
            this.opts.onAccept.call(this.input, value, item);
        }
    }

    Lookahead.prototype.displayAs = function (item) {
        if (item && item.displayAs) {
            return item.displayAs;
        }
        else if ($.isFunction(this.opts.displayAs)) {
            return this.opts.displayAs(item);
        }
        else if (item) {
            return item.value;
        }
        else {
            return $(this.input).val();
        }
    }

    Lookahead.prototype.select = function (item, provisional) {
        this._selected = item;
        if (!provisional) {
            $(this.input).val(this.displayAs(item));
        }
    }
    
    Lookahead.prototype._highlight_element = function (el) {
        jQuery('li.selected', this.lookahead)
            .removeClass('selected')
            .css({ background: '' });
        el.addClass('selected').css({ background: SELECTED_COLOR });
    }

    Lookahead.prototype.select_element = function (el, provisional) {
        this._highlight_element(el);
        var value = el.find('a').attr('value');
        var item = this._items[value];
        this.select(item, provisional);
    }

    Lookahead.prototype.selectDown = function () {
        if (!this.lookahead) return;
        var el;
        if (jQuery('li.selected', this.lookahead).length) {
            el = jQuery('li.selected', this.lookahead).next('li');
        }
        if (! (el && el.length) ) {
            el = jQuery('li:first', this.lookahead);
        }
        this.select_element(el, false);
    };

    Lookahead.prototype.selectUp = function () {
        if (!this.lookahead) return;
        var el;
        if (jQuery('li.selected', this.lookahead).length) {
            el = jQuery('li.selected', this.lookahead).prev('li');
        }
        if (! (el && el.length) ) {
            el = jQuery('li:last', this.lookahead);
        }
        this.select_element(el, false);
    };

    Lookahead.prototype.clickCurrent = function () {
        if (!this.opts.requireMatch) {
            this.acceptInputValue();
        }
        else if (this._items.length) {
            var selitem = jQuery('li.selected a', this.lookahead);
            if (selitem.length && selitem.attr('value')) {
                this.accept(selitem.attr('value'));
            }
            else if (this._items.length == 1) {
                // Only one candidate - accept it
                this.accept(0);
            }
            else {
                var val = $(this.input).val();
                var fullMatchIndex = null;

                $.each(this._items, function(i) {
                    var item = this || {};
                    if (item.bolded_title == ('<b>'+item.title.replace(/</g, "&lt;").replace(/>/g, "&gt;") +'</b>')) {
                        if (fullMatchIndex) {
                            // Two or more full matches - do nothing
                            return;
                        }
                        fullMatchIndex = i;
                    }
                });

                // Only one full match - accept it
                if (fullMatchIndex != null) {
                    this.accept(fullMatchIndex);
                }
            }
        }
    };

    Lookahead.prototype.storeCache = function (val, data) {
        this._cache = this._cache || {};
        this._cache[val] = data;
        this._prevVal = val;
    }

    Lookahead.prototype.getCached = function (val) {
        this._cache = this._cache || {};

        if (this._cache[val]) {
            // We've already done this query, so just return this data
            return this.filterData(val, this._cache[val])
        }
        else if (this._prevVal) {
            var re = this.filterRE(this._prevVal);
            if (val.match(re)) {
                // filter the previous data, but only return if we still
                // have at least the minimum or if filtering the data made
                // no difference
                var cached = this._cache[this._prevVal];
                if (cached) {
                    filtered = this.filterData(val, cached)
                    var use_cache = cached.length == filtered.length
                                 || filtered.length >= this.opts.count;
                    if (use_cache) {
                        // save this for next time
                        this.storeCache(val, cached);
                        return filtered;
                    }
                }
            }
        }
        return [];
    };

    Lookahead.prototype.abort = function () {
        if (this.request) this.request.abort();
    };

    Lookahead.prototype.createFilterValue = function (val) {
        if (this.opts.filterValue) {
            return this.opts.filterValue(val);
        }
        else {
            var filter = FILTER_TYPES[this.opts.filterType];
            if (!filter) {
                throw new Error('invalid filterType: ' + this.opts.filterType);
            }
            return val.replace(/^(.*)$/, filter);
        }
    };

    Lookahead.prototype.onchange = function () {
        var self = this;
        if (this._loading_lookahead) {
            this._change_queued = true;
            return;
        }

        this._change_queued = false;

        var val = $(this.input).val();
        if (!val) {
            this.clearLookahead()
            return;
        }

        var cached = this.getCached(val);
        if (cached.length) {
            this.displayData(cached);
            return;
        }

        var url = typeof(this.opts.url) == 'function'
                ? this.opts.url() : this.opts.url;

        var params = this.opts.params;

        if (this.opts.fetchAll) {
            delete params.count;
        }
        else {
            params[this.opts.filterName] = this.createFilterValue(val);
        }

        this._loading_lookahead = true;
        this.request = $.ajax({
            url: url,
            data: params,
            cache: false,
            dataType: 'json',
            success: function (data) {
                self.storeCache(val, data);
                self._loading_lookahead = false;
                if (self._change_queued) {
                    self.onchange();
                    return;
                }
                self.displayData(
                    self.filterData(val, data)
                );
            },
            error: function (xhr, textStatus, errorThrown) {
                self._loading_lookahead = false;
                if (self._change_queued) {
                    self.onchange();
                    return;
                }
                var $error = self.$('<span></span>')
                    .addClass("st-suggestion-warning");
                self.$('<li></li>')
                    .append($error)
                    .appendTo(self.getLookaheadList());

                if (textStatus == 'parsererror') {
                    $error.html(loc("error.parsing-data"));
                }
                else if (self.opts.onError) {
                    var errorHandler = self.opts.onError[xhr.status]
                                    || self.opts.onError['default'];
                    if (errorHandler) {
                        if ($.isFunction(errorHandler)) {
                            $error.html(
                                errorHandler(xhr, textStatus, errorThrown)
                            );
                        }
                        else {
                            $error.html(errorHandler);
                        }
                    }
                }
                else {
                    $error.html(textStatus);
                }
                self.show();
            }
        });
    };

})(jQuery);
