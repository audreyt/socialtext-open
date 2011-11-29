(function($){
    
    function width_height (node, opts) {
        var w = $(node).width();
        var h = $(node).height();
        if (!opts.noPadding) {
            w += 2;
            h += 2;
        }
        return {width:  w, height: h};
    }

    $.fn.createSelectOverlap = function() {
        var opts = {};
        if (arguments.length) opts = arguments[0];
        if ($.browser.msie && $.browser.version < 7) {
            this.each(function(){
                var $iframe = $('iframe.iframeHack', this);
                if ($iframe.size() == 0) {
                    $iframe = $('<iframe src="/static/html/blank.html"></iframe>')
                        .addClass('iframeHack')
                        .css({
                            position: 'absolute',
                            filter: "alpha(opacity=0)",
                            top:    opts.noPadding ? 0 : -1,
                            left:   opts.noPadding ? 0 : -1,
                            zIndex: opts.zIndex || -1
                        })
                        .appendTo(this);
                }

                $(this).mouseover(function() {
                    $iframe.css(width_height(this, opts));
                });
                $iframe.css(width_height(this, opts));
            });
        }
        return this;
    };
})(jQuery);
