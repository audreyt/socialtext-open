(function ($) {

socialtext.dialog.register('control-create-workspace', function(opts) {
    var dialog = socialtext.dialog.createDialog({
        html: socialtext.dialog.process('control-create-workspace.tt2', opts),
        title: loc('control.create-new-wiki'),
        height: 175,
        buttons: [
            {
                text: loc('do.next'),
                id: 'new-workspace-next',
                click: function() {
                    dialog.find('form').submit();
                }
            },
            {
                text: loc('do.cancel'),
                id: 'new-workspace-cancel',
                click: function() {
                    if ($.isFunction(opts.onClose)) opts.onClose();
                    dialog.close();
                }
            }
        ]
    });

    dialog.find('#create-workspace').submit(function() {
        dialog.find('.error').text('').hide();
        if ($('.page1').is(':visible')) {
            var title = dialog.find('#new_workspace_title').val();
            try {
                Socialtext.Workspace.AssertValidTitle(title);
                var name  = Socialtext.Workspace.TitleToName(title)
                dialog.find('#new_workspace_title2').text(title);
                dialog.find('#new_workspace_name').val(name);
                dialog.find('.page1').hide();
                dialog.find('.page2').show();
                dialog.find('#new-workspace-next').val(loc('do.create'));
            }
            catch (e) {
                dialog.find('#title-error').text(e.message).show();
            }
        }
        else {
            var args = {
                title: dialog.find('#new_workspace_title').val(),
                name: dialog.find('#new_workspace_name').val(),
                members: opts.members
            };

            if (opts.group) {
                args.permission_set = opts.group.permission_set == 'private'
                    ? 'member-only'
                    : opts.group.permission_set;
            }

            if (opts.account_id) {
                args.account_id = opts.account_id;
            }

            dialog.disable();
            Socialtext.Workspace.Create(args, function(ws) {
                if (ws.error) {
                    dialog.enable();
                    dialog.find('.error').text(ws.error).show();
                    return;
                }

                ws.load(function() {
                    var url = '/nlw/control/workspace/' + ws.workspace_id;
                    document.location = url;
                });
            });
        }


        return false;
    });

});

})(jQuery);
