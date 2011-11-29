(function($) {

socialtext.dialog.register('save-layout', function() {
    var dialog = socialtext.dialog.createDialog({
        title: loc('dashboard.save-confirmation'),
        html: socialtext.dialog.process('save-layout.tt2', {
            type: gadgets.container.type,
            gadget_titles: $.makeArray(
                $('.push-widget:checked').map(function() { return this.name })
            )
        }),
        buttons: [
            {
                text: loc('do.save'),
                id: 'save-layout-save',
                click: function() {
                    gadgets.container.saveAdminLayout({
                        purge: dialog.find('#force-update').is(':checked'),
                        success: function() {
                            dialog.close();
                            gadgets.container.leaveEditMode();
                            $('#st-wiki-subnav-link-invite').show();
                        }
                    });
                }
            },
            {
                id: 'save-layout-cancel',
                text: loc('do.cancel'),
                click: function() {
                    dialog.close();
                }
            }
        ]
    });
});

})(jQuery);

