(function($) {
    $.fn.blockFade = function(value) {
        if (value) this.fadeIsBlocked = value;
        return this;
    };


    $.fn.guardedFade = function(onBlock) {
        if (this.fadeIsBlocked) {
            if ($.isFunction(onBlock)) onBlock(this);
        }
        else {
            $(this).fadeOut();
        }
        return this;
    };

    $.browserHasReverseBlurMousedownOrder = function() {
        return $.browser.msie;
    }

    // IE uses a different call order for onBlur and onMouseDown.
    // We need the onMouseDown event to fire before onBlur. So we add a flag
    // and use a timer to get the sequence to work out in IE and Safari.
    $.fn.holdFocus = function() {
        var $popup = this;

        $popup.unbind('mousedown').mousedown(function(e) {
            $popup.clickedInPopup = true;
        });

        $(':input', $popup)
            .unbind('mousedown')
            .mousedown(function () {
                $popup.clickedInInput = true;
            })
            .unbind('keydown')
            .keydown(function(e) {
               if (e.keyCode == 9) $popup.tabPressed = true;
            })
            .unbind('blur')
            .blur(function(e) {
                var $element = $(this);
                // tab has been pressed, do default behaviour
                if ($popup.tabPressed) {
                    $popup.tabPressed = false;
                    return true;
                }

                // Use the timeout to sequence events 'properly'
                setTimeout(function() {
                    if ($popup.clickedInPopup || $popup.clickedInInput) {
                        if (!$popup.clickedInInput) $element.focus();
                        $popup.clickedInPopup = false;
                        $popup.clickedInInput = false;
                    }
                    else {
                        $popup.guardedFade();
                    }
                }, 50);
            });
    };
})(jQuery);
