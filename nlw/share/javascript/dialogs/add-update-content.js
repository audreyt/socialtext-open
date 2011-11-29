(function ($) {

var addContent = {
    opts: {},
    show: function (opts) {
        var self = this;
        self.opts = opts;
        self.dialog = socialtext.dialog.createDialog({
            html: socialtext.dialog.process('add-update-content.tt2', {
                update: self.opts.gadget_id ? true : false,
                gadget_id: self.opts.gadget_id,
                src: /^urn:/.test(self.opts.src) ? null : self.opts.src,
                hasXML: self.opts.hasXML
            }),
            title: self.opts.gadget_id
                ? loc('widgets.update-widget')
                : loc('widgets.add-widget'),
            buttons: [
                {
                    text: self.opts.gadget_id
                        ? loc('widgets.about-update')
                        : loc('widgets.add'),
                    id: 'st-add-widget',
                    click: function() {
                        self.dialog.find('form').submit();
                    }
                },
                {
                    id: 'add-update-content-cancel',
                    text: loc('do.cancel'),
                    click: function() { self.dialog.close() }
                }
            ]
        });
        self.setup();
        return self.dialog;
    },

    setup: function () {
        var self = this;
        // Select the appropriate checkbox when either file of url inputs are
        // clicked
        self.dialog.find('input[name=url],input[name=file],input[name=editor]')
            .click(function() {
                var name = $(this).attr('name');
                self.dialog.find('input[name=method][value='+name+']').click();
            });
        
        self.bindFormTarget();

        self.dialog.find('form').submit(function() {
            self.dialog.disable();
            if (self.dialog.find('input[value=editor]').is(':checked')) {
                var url = '/st/widget?account_id=' + self.opts.account_id;
                if (self.opts.gadget_id)
                    url += '&widget_id=' + self.opts.gadget_id;
                window.location = url;
                return false;
            }
        });
    },

    bindFormTarget: function() {
        var self = this;
        self.dialog.find('iframe').load(function () {
            var doc = this.contentDocument || this.contentWindow.document;
            if (!doc) throw new Error("Can't find iframe");

            var content = $('body', doc).text();

            var result;
            try { result = $.secureEvalJSON(content) } catch(e){};

            if (!result) {
                self.showError(content);
            }
            else if (result.error) {
                self.showError(result.error);
            }
            else {
                if (self.opts.gadget_id) {
                    self.opts.onSuccess();
                    self.dialog.close();
                }
                else {
                    self.addGadgetToGallery(result.gadget_id);
                }
            }
        });
    },

    showError: function(error) {
        this.dialog.enable();
        this.dialog.find('.error').html(error);
    },

    addGadgetToGallery: function (gadget_id) {
        var self = this;
        $.ajax({
            url: '/data/accounts/' + self.opts.account_id
                + '/gadgets/' + gadget_id,
            type: 'PUT',
            success: function() {
                self.opts.onSuccess();
                self.dialog.close();
            },
            error: function (response) {
                self.showError(response.responseText);
            }
        });
    }
};

socialtext.dialog.register('add-update-content', function(args) {
    addContent.show(args);
});

})(jQuery);
