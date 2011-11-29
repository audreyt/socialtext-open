st.dialog.register('page-delete', function(opts) {
    var dialog = st.dialog.createDialog({
        html: st.dialog.process('page-delete.tt2', { page_title: st.page.title }),
        title: loc('page.delete'),
        buttons: [
            {
                id: 'st-delete-deletelink',
                text: loc('do.delete'),
                click: function() { dialog.find('form').submit() }
            },
            {
                id: 'st-delete-cancellink',
                text: loc('do.cancel'),
                click: function() { dialog.close() }
            }
        ]
    });
});

