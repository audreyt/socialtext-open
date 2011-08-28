(function ($) {

var ST = window.ST = window.ST || {};

ST.Attachments = function () {}
var proto = ST.Attachments.prototype = new ST.Lightbox;

proto._newAttachmentList = [];
proto._attachmentList = [];

proto.resetNewAttachments = function () {
    this._newAttachmentList = Socialtext.new_attachments || [];
};

proto.addNewAttachment = function (file) {
    this._newAttachmentList.push(file);
    var doEmbed = Number($("#st-attachments-attach-embed").val());
    if (doEmbed && window.wikiwyg && wikiwyg.is_editing && wikiwyg.current_mode) {
        var type = file["content-type"].match(/image/) ? 'image' : 'file';
        var widget_text = type + ': ' + file.name;
        var widget_string = '{' + widget_text + '}';
        wikiwyg.current_mode.insert_widget(widget_string);
    }
};

proto.getNewAttachments = function () {
    return this._newAttachmentList;
};

proto.attachmentList = function () {
    return $.map(
        this._newAttachmentList,
        function (item) { return item.name }
    ).join(', ')
};

proto.deleteAttachments = function (list) {
    var file;
    while (file = list.pop()) {
        this.delAttachment(file.uri);
    }
    Page.refreshPageContent(true);
    this.refreshAttachments();
};

proto.deleteAllAttachments = function () {
    this.deleteAttachments(this._attachmentList);
};

proto.deleteNewAttachments = function (cb) {
    // Only delete temporary attachments, not new ones from a template.
    this.deleteAttachments($.grep(this._newAttachmentList, function(att){
        return(att.is_temporary ? true : false);
    }));
};

proto.refreshAttachments = function (cb) {
    var self = this;
    $.ajax({
        url: Page.pageUrl() + '/attachments?order=alpha_date;accept=application/json',
        cache: false,
        dataType: 'json',
        success: function (list) {
            $('#st-attachment-listing').html('');
            for (var i=0; i< list.length; i++) {
                var attachment = list[i];

                var repr = {
                    name: attachment.name,
                    id: attachment.id,
                    uploader: attachment.uploader,
                    uploader_name: attachment.uploader_name,
                    uploader_id: attachment.uploader_id,
                    upload_date: attachment.local_date,
                    uri: attachment.uri,
                    length: Page._format_bytes(attachment['content-length']),
                    extractable: attachment.name.match(/\.(zip|tar|tar.gz|tgz)$/)
                };

                var $item = $(
                    Jemplate.process('attachment-listing.tt2', {
                        wiki: Socialtext.wikiwyg_variables.wiki,
                        item: repr,
                        loc: loc
                    })
                );
                $item.find('.person.authorized')
                    .each(function() { new Avatar(this) });

                $('#st-attachment-listing').append($item);

                // Delete Attachments
                $('.delete_attachment', $item).unbind('click')
                    .click(function() {
                        self.showDeleteInterface(this);
                        return false;
                    });

                // Extract Archives
                $('.extract_attachment', $item).unbind('click')
                    .click(function() {
                        self.extractAttachment($(this).attr('name'));
                        return false;
                    });

                self._attachmentList.push(attachment);
            }
            if (cb) cb(list);
        }
    });
};

proto.extractAttachment = function (attach_id) {
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
            Page.refreshPageContent();
        }
    });
};

proto.delAttachment = function (url, refresh) {
    $.ajax({
        type: "DELETE",
        url: url,
        async: false
    });
    if (refresh) {
        this.refreshAttachments();
        Page.refreshPageContent(true);
    }
};

proto.onTargetLoad = function (iframe) {
    var self = this;
    var doc = iframe.contentDocument || iframe.contentWindow.document;

    var id = $('input', doc).val();

    $('#st-attachments-attach-uploadmessage').html(loc('file.upload-complete'));
    $('#st-attachments-attach-filename').attr('disabled', false).val('');
    $('#st-attachments-attach-closebutton').removeClass('disabled').removeClass('loading');

    this.refreshAttachments(function (list) {
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
    Page.refreshPageContent();
}

proto.refreshUploadedAttachmentsList = function (){
    var self = this;
    $('#st-attachments-attach-list')
        .show()
        .html('')
        .append(
            $('<span></span>')
                .attr('class', 'st-attachments-attach-listlabel')
                .html(loc('file.uploaded:') + 
                    '&nbsp;' + self.attachmentList()
                )
        );
}

proto.onChangeFilename = function () {
    var self = this;
    var filename = $('#st-attachments-attach-filename').val();
    if (!filename) {
        $('#st-attachments-attach-uploadmessage').html(
            loc("file.browse")
        );
        return false;
    }

    var filename = filename.replace(/^.*\\|\/:/, '');

    if (encodeURIComponent(filename).length > 255 ) {
        $('#st-attachments-attach-uploadmessage').html(
            loc("error.filename-too-long")
        );
        return false;
    }

    var basename = filename.match(/[^\\\/]+$/);

    $.getJSON(this.attachmentsURL(), function(attachments) {
        var matches = $.grep(attachments, function(a) {
            return a.name.toLowerCase() == filename.toLowerCase();
        });

        var upload = function() {
            $('#st-attachments-attach-uploadmessage').html(
                loc('file.uploading=name', basename)
            );

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
                    $(self.getNewAttachments()).each(function() {
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
        }
        else {
            upload.call();
        }
    });
}

proto.attachmentsURL = function () {
    return [
        "/data/workspaces",
        Socialtext.wiki_id,
        "pages",
        Socialtext.page_id,
        "attachments"
    ].join("/");
}

proto.showDeleteInterface = function (img) {
    var self = this;
    var href = $(img).prevAll('a[href!=#]').attr('href');
    
    $(Socialtext.attachments).each(function() {
        if ( href == this.uri ) {
            Socialtext.selected_attachment = this.name;
        }
    });

    $(self.getNewAttachments()).each(function() {
        if ( href == this.uri ) {
            Socialtext.selected_attachment = this.name;
        }
    });

    self.process('attachment.tt2');

    // We only process the popup once, so we'll only load the
    // selected_attachment that first time. After that, we need to manually
    // replace the value.
    var popup = $('#st-attachment-delete-confirm');
    popup.html(
        popup.html().replace(/'.*'/,
            "'" + Socialtext.selected_attachment + "'")
    );

    $('#st-attachment-delete').unbind('click').click(function() {
        var loader = $('<img>').attr('src','/static/skin/common/images/ajax-loader.gif');
        var buttons = $('#st-attachment-delete-buttons');
        var content = buttons.html();
        buttons.html(loader);
        self.delAttachment(href, true);
        $.hideLightbox();
        buttons.html(content);
    });

    $.showLightbox({
        content:'#st-attachment-delete-confirm',
        close:'#st-attachment-delete-cancel'
    })
}

proto.showUploadInterface = function () {
    var self = this;

    if (!$('#st-attachments-attachinterface').size()) {
        this.process('attachment.tt2');
        Attachments.refreshUploadedAttachmentsList();
    }
    
    // Make sure the duplicate attachment warnings are hidden.
    $("#st-attachments-duplicate-menu").hide();
    $("#st-attachments-duplicate-menu .more").hide();

    $('#st-attachments-attach-filename')
        .val('')
        .unbind('change')
        .bind('change', function () {
            self.onChangeFilename(this);
            return false;
        });

    $.showLightbox({
        content:'#st-attachments-attachinterface',
        close:'#st-attachments-attach-closebutton'
    });
};

proto.showDuplicateLightbox = function(files, upload_callback) {
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
}

// Backwards compat
proto.delete_new_attachments = proto.deleteNewAttachments;
proto.delete_all_attachments = proto.deleteAllAttachments;
proto.reset_new_attachments = proto.resetNewAttachments;
proto.get_new_attachments = proto.getNewAttachments;

})(jQuery);

window.Attachments = window.Attachments || new ST.Attachments;
