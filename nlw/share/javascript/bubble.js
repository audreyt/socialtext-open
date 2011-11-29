(function($){

Bubble = function (opts) {
    var self = this;
    $.extend(self, {}, self.defaults, opts);
    $(this.node)
        .unbind('mouseover')
        .unbind('mouseout')
        .mouseover(function(){ self.mouseOver() })
        .mouseout(function(){ self.mouseOut() });

    if (self.isTouchDevice()) {
        $(self.node).click(function(){
            self.mouseOver();
            return false;
        });
    }

    // Help mobile signals hide bubbles
    $(window).scroll(function(){
        $(self.node).mouseout();
    });
};

Bubble.prototype = {
    defaults: {
        topOffset: 28,
        bottomOffset: 25,
        hoverTimeout: 500
    },

    isTouchDevice: function() {
        try {
            document.createEvent("TouchEvent");
            return true;
        } catch (e) {
            return false;
        }
    },

    mouseOver: function() {
        this._state = 'showing';
        var self = this;
        setTimeout(function(){
            if (self._state == 'showing') {
                if (!self.popup) {
                    self.createPopup();
                    self.onFirstShow();
                }
                else {
                    self.show();
                }
                self._state = 'shown';
            }
        }, this.hoverTimeout);
    },

    mouseOut: function() {
        this._state = 'hiding';
        var self = this;
        setTimeout(function(){
            if (self._state == 'hiding') {
                self.hide();
                self._state = 'hidden';
            }
        }, this.hoverTimeout);
    },

    isVisible: function() {
        return this.popup && this.popup.is(':visible');
    },

    createPopup: function() {
        var self = this;
        this.contentNode = $('<div></div>')
            .addClass('bubble');

        this.popup = $('<div></div>')
            .addClass('bubbleWrap')
            .mouseover(function() { self.mouseOver() })
            .mouseout(function() { self.mouseOut() })
            .appendTo('body');

        this.popup.append(this.contentNode)

        if (!$.browser.msie || ($.browser.msie && $.browser.version > 6)) {
            this.popup.append('<div class="before"></div>');
            this.popup.append('<div class="after"></div>');
        }

        this.popup.append('<div class="clear"></div>');
    },

    html: function(html) {
        this.contentNode.html(html);
    },

    append: function(html) {
        this.contentNode.append(html);
    },

    show: function() {
        // top was calculated based on $node's top, but if there was an
        // avatar image, we want to position off of the avatar's top
        var $img = $(this.node).find('img');
        var $node = $img.size() ? $img : $(this.node);
        var offset = $node.offset();

        var winOffset = $.browser.msie ? document.documentElement.scrollTop 
                                       : window.pageYOffset;

        this.popup.removeClass('top').removeClass('left');
        var pop_offset = { left: offset.left - 43 };

        // Figure out whether to show the avatar above or below
        if ((offset.top - winOffset) > ($(window).height() / 2)) {
            // Above
            pop_offset.top
                = offset.top - this.popup.height() - this.bottomOffset;
        }
        else {
            // Below
            this.popup.addClass('top')
            pop_offset.top =  offset.top + $node.height() + this.topOffset;
        }

        // Now check if the bubble goes off the page to the right
        if (pop_offset.left + this.popup.width() > $(window).width()) {
            // Move the bubble over to the left
            pop_offset.left
                = offset.left + $node.width() - this.popup.width() + 4;
            this.popup.addClass('left')
            if (this.popup.hasClass('top')) {
                pop_offset.top -= 12;
            }
            else {
                pop_offset.top += 12;
            }
        }
        
        this.popup.css(pop_offset);

        if ($.browser.msie && this.popup.is(':hidden')) {
            // XXX
            var $vcard = $('.vcard', this.contentNode);
            this.popup.fadeIn('def', function() {
                // min-height: 62px
                if ($.browser.msie && $vcard.height() < 65) {
                    $vcard.height(65);
                }
            });
        }
        else {
            this.popup.fadeIn();
        }
    },

    hide: function() {
        if (this.popup) this.popup.fadeOut();
    }

};

})(jQuery);
