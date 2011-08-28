(function($){
    var opts;

    var _getPageScroll = function() { 
        var xScroll, yScroll;
        
        if (self.pageYOffset) {
          yScroll = self.pageYOffset;
          xScroll = self.pageXOffset;
        }
        else if (document.documentElement && document.documentElement.scrollTop) {  // Explorer 6 Strict.
          yScroll = document.documentElement.scrollTop;
          xScroll = document.documentElement.scrollLeft;
        }
        else if (document.body) {// All other Explorers.
          yScroll = document.body.scrollTop;
          xScroll = document.body.scrollLeft;
        }

        pageScroll = { left: xScroll, top: yScroll };
        return pageScroll;
    };

    $.hideLightbox = function() {
        this.fn.hideLightbox();
    };

    $.showLightbox = function(args) {
        // Allow $.showLightbox(string) and $.showLightbox(options)
        opts = typeof(args) == 'string' ? { html: args } : args;
        this.fn.showLightbox();
    };

    $.pauseLightbox = function() {
        var src = nlw_make_static_path('/skin/common/images/ajax-loader.gif');
        var $cover = $('<div class="cover"></div>')
            .css({
                width: '100%',
                opacity: "0.8",
                filter: "alpha(opacity=80)",
                position: 'absolute',
                top: 0,
                backgroundColor: '#DDD'
            })
            .height($('#lightbox').height())
            .appendTo('#lightbox');
        $('<img/>')
            .attr('src', src)
            .css({
                position: 'absolute',
                left: '50%',
                top: '50%'
            })
            .appendTo('#lightbox .cover');
    };

    $.resumeLightbox = function() {
        $('#lightbox .cover').remove();
    };

    $.fn.showLightbox = function() {
        if (!$('#lightbox').size()) {
            $('<div id="lightbox" />')
                .css('zIndex', 2002)
                .appendTo('body');
        }

        var pageScroll = _getPageScroll();

        if ( opts.overlayBackground == null )
            opts.overlayBackground = "#000";

        if (opts.speed == null)
            opts.speed = 500;

        if (!$('#overlay').size()) {
            $('<div id="overlay"></div>')
                .click(function () { $.hideLightbox() })
                .css({
                    display: 'none',
                    position: 'absolute',
                    background: opts.overlayBackground,
                    opacity: "0.5",
                    filter: "alpha(opacity=50)",
                    zIndex: 2001,
                    padding: 0,
                    margin: 0
                })
                .appendTo('body');

            $('#overlay').createSelectOverlap({zIndex: 2000});
        }

        var arrayPageScroll = _getPageScroll();

        if (opts.html) {
            opts.html = '<div style="display:block" class="lightbox">'
                      + opts.html
                      + '</div>';
        }

        $('#lightbox')
            .css('width', opts.width || '520px')
            .css('height', '') // Reset height set by scrollable code below
            .append(opts.html || $(opts.content).show());
        
        if ($(window).height() < $('#lightbox').height()) {
            // Window is too short for our lightbox; make it scrollable.
            $('#lightbox').css({
                width:    30 + $('#lightbox').width() + 'px',
                height:   $(window).height(),
                overflow: 'auto'
            });
        }
        else {
            // Window's height is sufficient for lightbox; hide overflows.
            $('#lightbox')
                .css('overflow', 'hidden');
        }

        opts._originalHTMLOverflow = $('html').css('overflow') || 'visible';
        opts._originalBodyOverflow = $('body').css('overflow') || 'visible';

        if (opts.close) {
            $(opts.close).click(function () {
                $.hideLightbox();
                return false;
            });
        }

        $(window)
            .resize(function() {
                $('#lightbox')
                    .css({
                        left: (pageScroll.left + (($(window).width() -
                                $('#lightbox').width()) / 2)) + 'px',
                        top:  (pageScroll.top + (($(window).height() -
                                $('#lightbox').height()) / 4)) + 'px'
                    });

                var $body = $(document.body);
                var $win = $(window);
                var width = $body.width() > $win.width()
                    ? $body.width() : $win.width();
                var height = $body.height() > $win.height()
                    ? $body.height() : $win.height();

                $('#overlay, #overlay iframe.hack').css({
                    top: 0,
                    left: 0,
                    width: width + 'px',
                    height: height + 'px'
                })
            })
            .resize();

        // {bz: 4923}: Hide Flash objects before displaying lightbox, since we
        // have no control over its original wmode. (Flash objects with wmode
        // set to non-transparent will always overlap with the lightbox on Windows.)
        $('div.wiki iframe:visible, div.wiki object:visible, div.wiki embed:visible')
            .addClass('st-lightbox-hidden')
            .css('visibility', 'hidden');

        $('#overlay')
            .fadeIn(opts.speed, function () {
                $('#lightbox').fadeIn(function() {
                    $(opts.focus).focus();
                    if ($.isFunction(opts.callback))
                        opts.callback();

                    $('#lightbox').trigger('lightbox-load');
                })
            });
    };

    $.fn.hideLightbox = function() {
        if (opts) {
            if (opts.content)
                $(opts.content).hide().appendTo('body');
            $('#overlay').fadeOut(opts.speed);
            $('#lightbox').html('').hide();
            $('html').css('overflow', opts._originalHTMLOverflow);
            $('body').css('overflow', opts._originalBodyOverflow);

            $('div.wiki iframe.st-lightbox-hidden, div.wiki object.st-lightbox-hidden, div.wiki embed.st-lightbox-hidden')
                .removeClass('st-lightbox-hidden')
                .css('visibility', 'visible');

            $('#lightbox').trigger('lightbox-unload');
        }
    };
})(jQuery);
