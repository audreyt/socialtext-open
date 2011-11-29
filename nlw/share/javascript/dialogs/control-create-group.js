(function ($) {

socialtext.dialog.register('control-create-group', function(opts) {

    opts = typeof(opts) == 'undefined' ? {} : opts;

    Socialtext.Group.GetDrivers(function(drivers) {
        opts.ldap_drivers = $.grep(drivers, function (item) {
            return item.driver_key.match(/^LDAP/);
        });

        var dialog = socialtext.dialog.createDialog({
            html: socialtext.dialog.process('control-create-group.tt2', opts),
            title: loc('control.create-a-group'),
            buttons: [
                {
                    text: loc('do.create'),
                    id: 'st-group-create-submit',
                    click: function() {
                        dialog.find('#createGroup').submit();
                    }
                },
                {
                    text: loc('do.cancel'),
                    id: 'st-group-create-cancel',
                    click: function() {
                        if ($.isFunction(opts.onClose)) opts.onClose();
                        dialog.close()
                    }
                }
            ]
        });

        dialog.find('#createGroup').submit(function() {
            dialog.find('.error').text('').hide();
            dialog.disable();

            var args = { account_id: opts.account_id };
            try {
                var on = dialog.find('input[name=driver_class]:checked');

                if (on && on.val() == 'LDAP') {
                    args.ldap_dn = dialog.find('select[name=ldap_group]').val();
                }
                else {
                    args.permission_set = dialog.find('input[name=permission_set]:checked').val();
                    args.name = dialog.find('input[name=name]').val();
                }

                Socialtext.Group.Create(args, function(group) {
                    if (group.errors) {
                        dialog.enable();
                        dialog.find('.error').text(group.errors[0]).show();
                        return;
                    }

                    var url = '/nlw/control/group/' + group.group_id;
                    document.location = url;
                });
            }
            catch (e) {
                dialog.enable();
                dialog.find('.error').text(e.message).show();
            }

            return false;
        });

       dialog.find('input[name=driver_class]').change(function() {
            var on = dialog.find('input[name=driver_class]:checked');

            if (on.val() == 'Default') {
                dialog.find('.ldap_option').attr('disabled', true);
                dialog.find('.default_option').attr('disabled', false);
            }
            else {
                dialog.find('.ldap_option').attr('disabled', false);
                dialog.find('.default_option').attr('disabled', true);
            }
        });

        dialog.find('select[name=ldap_driver]').change(function() {
            var select = $('#st-select-ldap-group');
            select.find('option').remove();

            if (! $(this).val()) { return; }

            Socialtext.Group.GetDriverGroups($(this).val(), function(groups) {
                $.each(groups, function(i, group) {
                    $('<option></option>')
                        .val(group.driver_unique_id)
                        .text(group.driver_group_name)
                        .appendTo(select);
                });
            });
        });
    });
});

})(jQuery);
