(function ($) {

socialtext.dialog.register('groups-leave', function(opts) {
    var dialog = socialtext.dialog.createDialog({
        html: socialtext.dialog.process('groups-leave.tt2', $.extend({
            selfJoin: gadgets.container.group.permission_set == 'self-join'
        }, opts)),
        title: loc('groups.leave'),
        buttons: [
            {
                text: loc('do.leave'),
                id: 'st-lightbox-leave-group',
                click: function() {
                    dialog.disable();

                    var group = new Socialtext.Group({
                        group_id: gadgets.container.group.id,
                        permission_set: gadgets.container.group.permission_set
                    });

                    var group_data = [ {user_id: st.viewer.user_id} ];
                    group.removeMembers(group_data, function(data) {
                        if (data.errors) {
                            dialog.find('.error').text(data.errors[0]);
                            dialog.enable();
                            return false;
                        }
                        else if (group.permission_set == 'self-join') {
                            location = '/st/group/' + group.group_id
                                + '?_=just-visiting';
                        }
                        else {
                            location = '/st/dashboard';
                        }
                    });
                }
            },
            {
                text: loc('do.cancel'),
                id: 'st-lightbox-cancel-leave-group',
                click: function() {
                    dialog.close();
                }
            }
        ]
    });
});

})(jQuery);
