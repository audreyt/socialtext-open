(function ($) {

socialtext.dialog.register('groups-create-workspace', function(opts) {
    var dialog = socialtext.dialog.createDialog({
        html: socialtext.dialog.process('groups-create-workspace.tt2', opts),
        title: loc('wiki.create'),
        height: 350,
        buttons: [
            {
                text: loc('do.next'),
                id: 'new-workspace-next',
                click: function() {
                    dialog.find('.error').text('').hide();
                    var title = dialog.find('#new_workspace_title').val();
                    try {
                        Socialtext.Workspace.AssertValidTitle(title);
                        var name  = Socialtext.Workspace.TitleToName(title)
                        dialog.find('#new_workspace_title2').text(title);
                        dialog.find('#new_workspace_name').val(name);
                        dialog.find('.page1').hide();
                        dialog.find('.page2').show();
                        $('#new-workspace-next').hide();
                        $('#new-workspace-create').show();
                    }
                    catch (e) {
                        dialog.find('.error').text(e.message).show();
                        gadgets.rpc.call('', 'resumeLightbox');
                    }
                    return false;
                }
            },
            {
                text: loc('do.create'),
                id: 'new-workspace-create',
                click: function() {
                    dialog.find('.error').text('').hide();
                    dialog.disable();
                    var title = dialog.find('#new_workspace_title').val();
                    var name = dialog.find('#new_workspace_name').val();
                    var err = loc("groups.wiki-with-that-name-already-exists");
                    try {
                        Socialtext.Workspace.AssertValidName(name);
                        Socialtext.Workspace.CheckExists(name,function(exists){
                            if (exists) {
                                dialog.find('.error').text(err).show();
                                dialog.enable();
                            }
                            else {
                                if ($.isFunction(opts.callback))
                                    opts.callback(name, title);
                                dialog.close();
                            }
                        });
                    }
                    catch (e) {
                        dialog.find('.error').text(e.message).show();
                        dialog.enable();
                    }
                    return false;
                }
            },
            {
                text: loc('do.cancel'),
                id: 'new-workspace-cancel',
                click: function() { dialog.close() }
            }
        ]
    });

    $('#new-workspace-create').hide();

    dialog.find('form').submit(function() {
        if (dialog.find('.page1').is(':visible')) {
            $('#new-workspace-next').click();
        }
        else {
            $('#new-workspace-create').click();
        }
        return false;
    });
});

})(jQuery);
