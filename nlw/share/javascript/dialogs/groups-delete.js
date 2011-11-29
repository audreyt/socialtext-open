(function ($) {

socialtext.dialog.register('groups-delete', function(opts) {
    var dialog = socialtext.dialog.createDialog({
        html: socialtext.dialog.process('groups-delete.tt2', opts),
        title: loc('groups.delete=name', opts.group_name),
        buttons: [
            {
                text: loc('do.delete'),
                id: 'st-lightbox-group-delete',
                click: function() {
                    dialog.disable();
                    var group = new Socialtext.Group({
                        group_id: opts.group_id
                    });
                    group.remove(function(res) {
                        if (res.errors && res.errors.length) {
                            dialog.find('.error').html(res.errors[0]);
                            dialog.enable();
                        }
                        else {
                            dialog.close();
                            location = '/st/dashboard';
                        }
                    });
                }
            },
            {
                text: loc('do.cancel'),
                id: 'st-lightbox-group-delete-cancel',
                click: function() {
                    dialog.close();
                }
            }
        ]
    });
});

})(jQuery);

