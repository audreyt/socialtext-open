(function($){

socialtext.dialog.register('attachments-delete', function(opts) {
    var dialog = socialtext.dialog.createDialog({
        html: socialtext.dialog.process('attachments-delete.tt2', opts),
        title: loc('file.delete'),
        buttons: [
            {
                id: "st-attachment-delete",
                text: loc('do.delete'),
                click: function() {
                    st.attachments.delAttachment(opts.href, true);
                    dialog.close();
                }
            },
            {
                id: 'st-attachments-delete-cancel',
                text: loc('do.close'),
                click: function() { dialog.close() }
            }
        ]
    });
});

})(jQuery);
