(function($){
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

    $.fn.lookahead = function(opts) {
        opts = $.extend(true, {}, DEFAULTS, opts); // deep extend

        if (!opts.url) throw new Error("url missing");
        if (!opts.linkText) throw new Error("linkText missing");

        function linkTitle (item) {
            var lt = opts.linkText(item);
            return typeof (lt) == 'string' ? lt : lt[0] || '';
        }

        function linkValue (item) {
            var lt = opts.linkText(item);
            return typeof (lt) == 'string' ? lt : lt[1];
        }

        function displayAs (item) {
            if (item && item.displayAs) {
                return item.displayAs;
            }
            else if ($.isFunction(opts.displayAs)) {
                return opts.displayAs(item);
            }
            else {
                return linkValue(item);
            }
        }

        function linkDesc (item) {
            var lt = opts.linkText(item);
            return typeof (lt) == 'string' ? '' : lt[2] || '';
        };

        function createFilterValue (val) {
            if (opts.filterValue) {
                return opts.filterValue(val);
            }
            else {
                var filter = FILTER_TYPES[opts.filterType];
                if (!filter) {
                    throw new Error('invalid filterType: ' + opts.filterType);
                }
                return val.replace(/^(.*)$/, filter);
            }
        }

        // For the autocomplete to show the right value, we've set value to be
        // the displayAs parameter rather than the real value. But before
        // passing our data back to the app, we need to change value back to
        // the real value so everything works properly. Maybe there's a better
        // way of doing this... who knows.
        function withRealValue (item) {
            return $.extend({}, item, { value: item.real_value });
        }

        // When we are in an iframe, create a floating place in the parent 
        // window where we can put the autocomplete
        var options = {
            appendTo: 'body'
        };

        var targetWindow = opts.getWindow && opts.getWindow();
        if (targetWindow && targetWindow !== window && window.name) {
            var $j = window.parent.$;
            var offset = $j('iframe[name='+window.name+']').offset();
            options.appendTo = $j('body');
            options.position = {
                offset: [offset.left, offset.top].join(' ')
            };
        }

        var $input = this;
        this.autocomplete($.extend(options, {
            source: function(request, response) {
                var url = $.isFunction(opts.url) ? opts.url() : opts.url;
                if (url === false) return;

                var params = opts.params;
                if (opts.fetchAll) {
                    delete params.count;
                }
                else {
                    params[opts.filterName] = createFilterValue(request.term);
                }

                $.ajax({
                    url: url,
                    data: params,
                    cache: false,
                    dataType: 'json',
                    success: function (data) {
                        var results = [];

                        // No results entry
                        if (!data.length) {
                            response([{
                                error: loc(
                                    "error.no-match=lookahead", request.term
                                )
                            }]);
                            return;
                        }

                        $.each(data, function(i, item) {
                            if (results.length >= opts.count) {
                                if (opts.showAll) {
                                    results.push({
                                        title: loc("lookahead.show-all-results"),
                                        label: loc('lookahead.show-all-results'),
                                        noThumbnail: true,
                                        onAccept: function() {
                                            opts.showAll(request.term)
                                        }
                                    });
                                    return false // Break out of $.each
                                }
                            }

                            // Add result
                            var title = linkTitle(item);
                            results.push({
                                label: title,
                                title: title, // compat
                                desc: linkDesc(item),
                                value: displayAs(item),
                                real_value: linkValue(item),
                                orig: item
                            });
                        });
                        response(results);
                    }
                });
            },
            select: function(event, ui) {
                if (ui.item.onAccept) {
                    ui.item.onAccept();
                }
                else if (opts.onAccept) {
                    var item = withRealValue(ui.item);
                    opts.onAccept(item.value, item);
                }
                $input.val('');
            },
            change: function(event, ui) {
                if ($.isFunction(opts.onChange)) opts.onChange(event, ui);
            },
            close: function(event, ui) {
                if ($.isFunction(opts.onBlur)) opts.onBlur();
            }
        }));

        $input.keydown(function(event) {
            if (opts.requireMatch) return;
            switch (event.keyCode) {
                case $.ui.keyCode.ENTER:
                case $.ui.keyCode.NUMPAD_ENTER:
                    // Accept the typed value
                    if ($input.val() && opts.onAccept) {
                        var currentVal = $input.val();
                        $input.val('');
                        opts.onAccept(currentVal);
                        $input.autocomplete('close');
                        event.preventDefault();
                        event.stopPropagation();
                    }
                    return;
                default:
                    return
            }
        });

        // Overload _renderItem to support icons and descriptions
        var autocompleter = this.data("autocomplete") || {};
        autocompleter._renderItem = function (ul, item) {
            if (item.error) {
                $('<li class="ui-autocomplete-error">' + item.error + '</li>')
                    .appendTo(ul);
                return;
            }

            var $node = $('<li></li>')
                .data("item.autocomplete", item)
                .append('<a>' + item.label + '</a>')
                .appendTo(ul);

            var margin = 0;
            if ($.isFunction(opts.getEntryThumbnail)) {
                var src = opts.getEntryThumbnail( withRealValue(item) );
                $node.find('a').prepend('<img src="' + src + '"/>');
                margin = 30;
            }
            if (item.desc) {
                $('<div class="description"></div>')
                    .text(item.desc)
                    .width(this.element.width() - margin)
                    .css('margin-left', margin + 'px')
                    .appendTo($node.find('a'));
            }
        }

        return this;
    };

})(jQuery);
