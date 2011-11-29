(function($){
    $.fn.uiDisable = function(style) {
        this.each(function() {
            var $disabled = $('<div class="uiDisabled"></div>')
                .height('100%')
                .width('100%')
                .append(
                    '<div class="spinner"></div>',
                    '<div class="background"></div>'
                )
                .prependTo($(this));
            if (style) $disabled.find('.spinner').css(style);
            $(this).data('disabled', $disabled);
        });
        return this;
    };

    $.fn.uiEnable = function() {
        this.each(function() {
            var $disabled = $(this).data('disabled');
            if ($disabled) {
                $disabled.remove();
            }
        })
    };
})(jQuery);
