st.dialog.register('attachments-duplicate', function(opts) {
    var dialog = st.dialog.createDialog({
        title: loc('file.duplicate-files'),
        html: st.dialog.process('attachments-duplicate.tt2', opts)
    });

    dialog.find('.chooser').buttonset();

    dialog.find('.warning').each(function(_, warning) {
        var name = $(this).find('input[name=filename]').val();
        var file = $.grep(opts.files, function(f) { return f.name == name })[0];

        $(warning).find('.cancel').click(function() {
            $(warning).remove();
            if (!$('#lightbox .warning').size()) $.hideLightbox();
            return false;
        });

        $(warning).find('.add').click(function() {
            $(warning).remove();
            opts.callback(file, 0);
            dialog.close();
            return false;
        });

        $(warning).find('.replace').click(function() {
            $(warning).remove();
            opts.callback(file, 1);
            dialog.close();
            return false;
        });
    });
});
