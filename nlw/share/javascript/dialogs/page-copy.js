(function ($) {

st.dialog.register('page-copy', function(opts) {
    var dialog = st.dialog.createDialog({
        html: st.dialog.process('page-copy.tt2', st),
        title: loc('page.copy=title?', st.page.title),
        buttons: [
            {
                id: "st-copy-savelink",
                text: loc('do.copy'),
                click: function() { dialog.find('form').submit() }
            },
            {
                id: "st-copy-cancellink",
                text: loc('do.cancel'),
                click: function() { dialog.close() }
            }
        ]
    });

    dialog.find('form').submit(function () {
        dialog.submitPageForm(function() {
            var title = dialog.find('input[name=new_title]').val();
            var ws = dialog.find('select option:selected').data('name');
            window.location = '/' + ws + '/' + title;
            dialog.close();
        });
        return false;
    });
});

})(jQuery);
