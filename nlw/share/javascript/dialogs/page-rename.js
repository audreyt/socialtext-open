(function ($) {

st.dialog.register('page-rename', function(opts) {
    var dialog = st.dialog.createDialog({
        html: st.dialog.process('page-rename.tt2', st),
        title: loc('page.rename'),
        buttons: [
            {
                id: 'st-rename-savelink',
                text: loc('do.rename'),
                click: function() { dialog.find('form').submit() }
            },
            {
                id: 'st-rename-cancellink',
                text: loc('do.cancel'),
                click: function() { dialog.close() }
            }
        ]
    });
    $("#st-rename-newname").select().focus();

    dialog.find('form').submit(function () {
        dialog.submitPageForm(function() {
            var title = dialog.find('input[name=new_title]').val();
            window.location = '/' + st.workspace.name + '/' + title;
            dialog.close();
        });
        return false;
    });
});

})(jQuery);
