(function($){

$.fn.extend({
    dropdown: function(options) {
        var self = this;

        var mobile = /(Blackberry|iPad|iPod|iPhone|Android)/
            .test(navigator.userAgent);

        if (mobile || (window.st && window.st.UA_is_Selenium)) {
            if (options && options.select) {
                self.change(function() {
                    options.select(self, self.find('option:selected').get(0));
                });
            }
            return self;
        }

        self.selectmenu($.extend({
            wrapperElement: '<span />',
            style: 'dropdown',
            width: 'auto'
        }, options));

        // Get the menu
        var $menu = self.next()

        // Change the arrow icon to be a triangle rather than an image
        $menu.find('.ui-selectmenu-icon').html('&nbsp;<small>&#9660;</small>');
        
        // Focusing the link puts a weird border around it, so let's
        // not allow that
        $menu.focus(function() { $(this).blur(); return false });

        return self;
    },
    dropdownSelectValue: function(value) {
        this.find('option').removeAttr('selected');
        this.find('option[value="'+value+'"]')
            .attr('selected', 'selected')
            .click();
    }
});
})(jQuery);
