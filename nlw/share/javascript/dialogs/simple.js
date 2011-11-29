(function ($) {

socialtext.dialog.register('simple', function(opts) {
    var dialog = socialtext.dialog.createDialog({
        html: socialtext.dialog.process('simple.tt2', opts),
        title: opts.title,
        buttons: opts.buttons || [
            {
                id: 'simple-close',
                text: loc('do.close'),
                click: function() {
                    if ($.isFunction(opts.onClose)) opts.onClose();
                    dialog.close();
                }
            }
        ]
    });
});

})(jQuery);
