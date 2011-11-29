st.dialog.register('page-email', function(opts) {
    var firstAdd = true;

    function clearEmails () {
        if (firstAdd) {
            $('#email_dest option').remove();
        }
    };
    function clearHelp() {
        clearEmails();
        firstAdd = false;
    };

    var full_uri = location.protocol + '//' + location.host
        + '/' + st.workspace.name + '/' + st.page.id;

    var dialog = st.dialog.createDialog({
        html: st.dialog.process('page-email.tt2', $.extend({full_uri:full_uri},st)),
        title: loc('info.email-page'),
        width: 580,
        buttons: [
            {
                id: 'email_send',
                text: loc('email.send'),
                click: function() { dialog.find('form').submit() }
            },
            {
                id: 'email_cancel',
                text: loc('do.cancel'),
                click: function() { dialog.close() }
            }
        ]
    });

    dialog.find('input[name="email_page_subject"]').select().focus();

    $('#email_remove').button().click(function () {
        $('#email_dest option:selected').remove();
        return false;
    });

    $('#email_all').button().click(function () {
        clearHelp();
        var startIndex = 0;
        var fetch_user_pageful = function () {
            $.getJSON('/data/workspaces/' + Socialtext.wiki_id + '/users?limit=100;startIndex=' + startIndex, function (data) {
                for (var i=0; i < data.entry.length; i++) {
                    $('<option />')
                        .html(data.entry[i].email)
                        .appendTo('#email_dest');
                    startIndex++;
                }
                if (startIndex < data.totalResults) {
                    fetch_user_pageful();
                }
            });
        }
        fetch_user_pageful();
        return false;
    });

    $('#email_none').button().click(function () {
        $('#email_dest option').remove();
        return false;
    });

    function acceptEmail(val) {
        clearHelp();
        dialog.find('.error').html('');
        var email = val.replace(/^.*<(.*)>$/, '$1');
        if (!val) {
            return false;
        }
        else if (!st.check_email(val)) {
            dialog.find('.error').html(loc('error.invalid=email', val))
            $('#email_page_add_one').focus();
            return false;
        }
        else {
            var matches = $.grep(
                $('#email_dest option'),
                function(opt) {
                    var val = opt.value.replace(/^.*<(.*)>$/, '$1');
                    return val == email;
                }
            );
            if (!matches.length) {
                $('<option />')
                    .val(email).text(val).appendTo('#email_dest');
            }
            return false;
        }
    }

    $('#email_recipient')
        .lookahead({
            url: '/data/workspaces/' + Socialtext.wiki_id + '/users',
            linkText: function (user) {
                return user.display_name
                     + ' <' + user.email_address +'>';
            },
            getEntryThumbnail: function(user) {
                return '/data/people/' + user.orig.user_id + '/small_photo';
            },
            displayAs: function (item) {
                return item.title;
            },
            onAccept: function(id, item) {
                acceptEmail(id);
                setTimeout(function() {
                    $('#email_recipient').val('');
                }, 0);
            }
        });

    $('#email_add').button().click(function () {
        acceptEmail($('#email_recipient').val());
        $('#email_recipient').val('');
    });

    dialog.find('form').submit(function () {
        dialog.find('.error').html('');

        var val = $('#email_recipient').val();
        var send_copy_checked = 
            dialog.find('input[name="email_page_send_copy"]').is(":checked");
        if ((val.length > 0) && (!firstAdd)) {
            $('#email_add').click();
        }
        if (($('#email_dest').get(0).length <= 0 || firstAdd) && (!send_copy_checked)) {
            dialog.find('.error').html(loc('error.no-recipient'));
            return false;
        }
        $('#email_dest option').attr('selected', true);
        $('#email_send').button('disable');
        clearEmails();
        var data = $(this).serialize();
        $.ajax({
            type: 'post',
            url: st.page.web_uri(),
            data: data,
            success: function (data) {
                dialog.close();
            },
            error: function() {
                dialog.find('.error').html(loc('error.send-failed'));
                $('#email_send').button('disable');
                $('#email_dest option').attr('selected', false);
            }
        })
        return false;
    });
});
