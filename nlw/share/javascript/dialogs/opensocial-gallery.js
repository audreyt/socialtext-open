(function ($) {

var gallery = {
    hidden: {},

    show: function (args) {
        var self = this;
        $.extend(self, args);

        self.dialog = st.dialog.createDialog({
            title: loc('widget.insert'),
            width: 640,
            minWidth: 550,
            height: 400,
            html: '<div id="st-widget-opensocial-gallery-loading" style="width: 100%; height: 100%; overflow: auto"><img src="/static/images/ajax-loader.gif" style="padding-top: 150px; padding-left: 300px" /></div>',
            close: function() {
                $('#st-widget-opensocial-gallery-loading').remove();
            }
        });
        self.loadAccountGallery(function(gadgets) {
            $('#st-widget-opensocial-gallery-loading').html(
                st.dialog.process('opensocial-gallery.tt2', {
                    gadgets: gadgets
                })
            );
            self.bindHandlers();
        });
    },

    bindHandlers: function() {
        var self = this;
        self.dialog.find("a.add-now").click(function(){
            var $button = $(this);
            var src = $button.siblings('input[name=src]').val();
            if (self.onAddWidget) {
                self.dialog.close();
                self.onAddWidget(src);
                return false;
            }
            var gadget_id = $button.siblings('input[name=gadget_id]').val();
            gadgets.container.add_gadget({
                col: 2,
                row: 0,
                gadget_id: gadget_id
            });
            self.dialog.close();
            return false;
        });
    },

    loadAccountGallery: function (callback) {
        var self = this;
        if (typeof(self.account_id) == 'undefined')
            throw new Error("account_id is required");
        if (typeof(self.view) == 'undefined')
            throw new Error("view is required");
        $.ajax({
            url: '/data/accounts/' + self.account_id + '/gadgets',
            dataType: 'json',
            success: function(gadgets) {
                var tables = [
                    { gadgets: [], title: loc('widget.socialtext') },
                    { gadgets: [], title: loc('widget.third-party') }
                ];
                $.each(gadgets, function(_, g){
                    var hidden = !g.src || g.removed || (
                        g.container_types
                        && $.inArray(self.view, g.container_types) == -1
                    );
                    if (hidden) return;

                    tables[(g.socialtext == true) ? 0 : 1].gadgets.push(g);
                });

                callback(tables);
            }
        });
    }
};

socialtext.dialog.register('opensocial-gallery', function(args) {
    gallery.show(args);
});

})(jQuery);
