Socialtext.prototype.attachments = (function($) {
    var _newAttachmentList = [];
    var _attachmentList = [];

    return {
        delete_new_attachments: function() {
            // XXX console.log('delete_new_attachments unimplemented');
        },
        reset_new_attachments: function() {
            _newAttachmentList = [];
        },
        get_new_attachments: function() {
            return _newAttachmentList;
        },
        add_new_attachment: function(file) {
            _newAttachmentList.push(file);
        },

        renderAttachments: function() {
            var self = this;

            var html = Jemplate.process('page/attachments.tt2', {
                attachments: st.page.attachments,
                static_path: st.static_path
            });
            $('#st-attachment-listing').html(html);

            $('#st-attachment-listing .person.authorized')
                .each(function() { new Avatar(this) });

            // Delete Attachments
            $('#st-attachment-listing .delete_icon').unbind('click')
                .click(function() {
                    socialtext.dialog.show('attachments-delete', {
                        href: $(this).attr('href'),
                        filename: $(this).data('filename')
                    });
                    return false;
                });

            // Extract Archives
            $('#st-attachment-listing .extract_attachment').unbind('click')
                .click(function() {
                    self.extractAttachment($(this).attr('name'));
                    return false;
                });
        },

        refreshAttachments: function (cb) {
            var self = this;
            var url = st.page.uri()
                    + '/attachments?order=alpha_date;accept=application/json';
            $.ajax({
                url: url,
                cache: false,
                dataType: 'json',
                success: function (list) {
                    st.page.attachments = list;
                    st.attachments.renderAttachments();
                    if ($.isFunction(cb)) cb(list);
                }
            });
        },

        extractAttachment: function (attach_id) {
            var self = this;
            $.ajax({
                type: "POST",
                url: location.pathname,
                cache: false,
                data: {
                    action: 'attachments_extract',
                    page_id: Socialtext.page_id,
                    attachment_id: attach_id
                },
                complete: function () {
                    self.refreshAttachments();
                    st.page.refreshPageContent();
                }
            });
        },

        delAttachment: function (url, refresh) {
            $.ajax({
                type: "DELETE",
                url: url,
                async: false
            });
            if (refresh) {
                this.refreshAttachments();
                st.page.refreshPageContent(true);
            }
        },

        showDuplicateLightbox: function(files, upload_callback) {
            var html = Jemplate.process('duplicate_files', {
                loc: loc,
                files: files
            });
            $.showLightbox({
                title: loc('file.duplicate-files'),
                html: html
            });

            $('#lightbox .warning').each(function(_, warning) {
                var name = $(this).find('input[name=filename]').val();
                var file = $.grep(files, function(f) { return f.name == name })[0];

                $(warning).find('.cancel').click(function() {
                    $(warning).remove();
                    if (!$('#lightbox .warning').size()) $.hideLightbox();
                    return false;
                });

                $(warning).find('.add').click(function() {
                    $(warning).remove();
                    upload_callback(file, 0);
                    if (!$('#lightbox .warning').size()) $.hideLightbox();
                    return false;
                });

                $(warning).find('.replace').click(function() {
                    $(warning).remove();
                    upload_callback(file, 1);
                    if (!$('#lightbox .warning').size()) $.hideLightbox();
                    return false;
                });
            });
        },

        prepare_before_save: function() {
            var self = this;
            var files = self.get_new_attachments();

            $.each(files, function () {
                if (this.deleted) return;
                $('<input type="hidden" name="attachment" />')
                    .val(this['id'] + ':' + this['page-id'])
                    .appendTo('#st-page-editing-files');
            });
        }

    }
})(jQuery);
