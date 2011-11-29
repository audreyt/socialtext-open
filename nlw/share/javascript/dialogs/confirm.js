(function ($) {

socialtext.dialog.register('confirm', function(opts) {
    if (!$.isFunction(opts.onConfirm)) throw Error('onConfirm required');
    var dialog = socialtext.dialog.createDialog({
        html: socialtext.dialog.process('confirm.tt2', opts),
        title: opts.title,
        buttons: [
            {
                text: loc('do.yes'),
                id: 'st-confirm-yes',
                click: function() {
                    opts.onConfirm();
                    dialog.close();
                }
            },
            {
                text: loc('do.no'),
                id: 'st-confirm-no',
                click: function() { dialog.close() }
            }
        ]
    });
});

})(jQuery);
