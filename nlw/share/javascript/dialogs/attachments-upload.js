(function($){

var AttachmentUpload = function(opts) {
    $.extend(this, opts);

    this._uploaded = [];
}

AttachmentUpload.prototype = {
    setup: function() { 
        var self = this;
        // Make sure the duplicate attachment warnings are hidden.
        self.dialog.find("#st-attachments-duplicate-menu").hide();
        self.dialog.find("#st-attachments-duplicate-menu .more").hide();

        self.dialog.find('#st-attachments-attach-filename')
            .val('')
            .unbind('change')
            .bind('change', function () {
                self.onChangeFilename(this);
                return false;
            });

        self.dialog.find('.chooser').buttonset();
    },

    addNewAttachment: function (file) {
        this._uploaded.push(file.name);
        st.attachments.add_new_attachment(file);

        var doEmbed = Number($("#st-attachments-attach-embed").val());
        if (doEmbed && window.wikiwyg && wikiwyg.is_editing && wikiwyg.current_mode) {
            var type = file["content-type"].match(/image/) ? 'image' : 'file';
            var widget_text = type + ': ' + file.name;
            var widget_string = '{' + widget_text + '}';
            wikiwyg.current_mode.insert_widget(widget_string);
        }
    },

    showMessage: function(msg, error) {
        if (!this._message) this._message = this.dialog.find('.message');

        if (error) {
            this._message.addClass('error').html(msg).show();
            this.dialog.enable();
        }
        else {
            this._message.removeClass('error').html(msg).show();
        }
    },

    onChangeFilename: function () {
        var self = this;

        self.dialog.disable();

        var filename = $('#st-attachments-attach-filename').val();
        if (!filename) {
            self.showMessage(loc("file.browse"), true);
            return false;
        }

        var filename = filename.replace(/^.*\\|\/:/, '');

        if (encodeURIComponent(filename).length > 255 ) {
            self.showMessage(loc("error.filename-too-long"), true);
            return false;
        }

        var basename = filename.match(/[^\\\/]+$/);

        $.getJSON(st.page.uri() + '/attachments', function(attachments) {
            var matches = $.grep(attachments, function(a) {
                return a.name.toLowerCase() == filename.toLowerCase();
            });

            var upload = function() {
                self.showMessage(loc('file.uploading=name', basename));

                $('#st-attachments-attach-formtarget').one('load', function () {
                    self.onTargetLoad(this)
                });

                $('#st-attachments-attach-form').submit();
                $('#st-attachments-attach-closebutton').addClass('disabled').addClass('loading');
                $('#st-attachments-attach-filename').attr('disabled', true);
            };

            if (matches.length) {
                $("#st-attachments-attach-embed").val(1); // Always embed the file wafl: {bz: 4412}

                var match = matches[0];
                var $menu = $("#st-attachments-duplicate-menu");

                if (matches.length > 1 ) {
                    $('.tip', $menu).html(
                        loc('file.add-or-replace=name?', filename)
                    );

                    $('.more p', $menu).html(
                        loc('file.replace=count,size,user,date', matches.length, match.size, match.uploader_name, match.local_date)
                    );
                    $('.more', $menu).show();
                }
                else {
                    $('.tip', $menu).html(
                        loc('file.add-or-replace=name,size,user,date?', filename, match.size, match.uploader_name, match.local_date)
                    );
                }

                // Add Handler
                $('.chooser .add', $menu).unbind('click').click(function() {
                    $('#st-attachments-attach-replace').val('0');
                    $menu.fadeOut('normal', upload);
                    return false;
                });

                // Replace Handler
                $('.chooser .replace', $menu).unbind('click').click(function() {
                    if (Socialtext.new_page) {
                        $(st.attachments.get_new_attachments()).each(function() {
                            if (this.name.toLowerCase() == filename.toLowerCase()) {
                                this.deleted = true;
                            }
                        });
                    }
                    $('#st-attachments-attach-replace').val('1');
                    $menu.fadeOut('normal', upload);
                    return false;
                });

                // Cancel Handler
                $('.chooser .cancel', $menu).unbind('click').click(function() {
                    $('#st-attachments-attach-filename').attr('value', '');
                    $menu.fadeOut();
                    return false;
                });

                $menu.show();
                self.dialog.enable();
            }
            else {
                upload.call();
            }
        });
    },

    onTargetLoad: function (iframe) {
        var self = this;
        var doc = iframe.contentDocument || iframe.contentWindow.document;

        var id = $('input', doc).val();

        self.dialog.enable();

        self.showMessage(loc('file.upload-complete'));

        st.attachments.refreshAttachments(function(list) {
            // Add the freshly-uploaded file to the
            // newAttachmentList queue.
            for (var i=0; i< list.length; i++) {
                var item = list[i];
                if (id == item.id) {
                    self.addNewAttachment(item);
                }
            }
            self.refreshUploadedAttachmentsList();
        });
        st.page.refreshPageContent();

        $('#st-attachments-attach-filename').attr('disabled', false);
    },

    refreshUploadedAttachmentsList: function() {
        var self = this;
        // XXX BAD L10N:
        self.showMessage(loc('file.uploaded:') + ' ' + self._uploaded);
    }
}

socialtext.dialog.register('attachments-upload', function(opts) {
    var dialog = socialtext.dialog.createDialog({
        html: socialtext.dialog.process('attachments-upload.tt2', opts),
        title: loc('file.upload'),
        buttons: [
            {
                text: loc('do.close'),
                id: 'st-attachments-attach-closebutton',
                click: function() { dialog.close() }
            }
        ]
    });

    var uploader = new AttachmentUpload({ dialog: dialog });
    uploader.setup();
});

})(jQuery);
