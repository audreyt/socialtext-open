(function ($) {

st.dialog.register('page-duplicate', function(opts) {
    var dialog = st.dialog.createDialog({
        html: st.dialog.process('page-duplicate.tt2', st),
        title: loc('page.duplicate=title', st.page.title),
        buttons: [
            {
                id: 'st-duplicate-savelink',
                text: loc('do.duplicate'),
                click: function() { dialog.find('form').submit() }
            },
            {
                id: 'st-duplicate-cancellink',
                text: loc('do.cancel'),
                click: function() { dialog.close() }
            }
        ]
    });
    $("#st-duplicate-newname").val(
        loc('page.duplicate=title', st.page.title)
    );
    $("#st-duplicate-newname").select().focus();

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
