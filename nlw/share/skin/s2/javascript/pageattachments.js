if (typeof ST == 'undefined') {
    ST = {};
}

// ST.Attachments class
ST.Attachments = function (args) {
    this._uploaded_list = [];
    $H(args).each(this._applyArgument.bind(this));

    var self = this;
    jQuery(function() {
        self._loadInterface();
    })

};

function sort_filesize(a,b) {
    var aunit = a.charAt(a.length-1);
    var bunit = b.charAt(b.length-1);
    if (aunit != bunit) {
        if (aunit < bunit) {
            return -1;
        } else if ( aunit > bunit ) {
            return 1;
        } else {
            return 0;
        }
    } else {
        var asize = parseFloat(a.slice(0,-1));
        var bsize = parseFloat(b.slice(0,-1));
        if (asize < bsize) {
            return -1;
        } else if ( asize > bsize ) {
            return 1;
        } else {
            return 0;
        }
    }
};

ST.Attachments.prototype = {
    attachments: null,
    _uploaded_list: [],
    _attachWaiter: '',
    _table_sorter: null,
    _newAttachments: {},

    element: {
        attachmentInterface:   'st-attachments-attachinterface',
        manageInterface:       'st-attachments-manageinterface',

        listTemplate:          'st-attachments-listtemplate',
        manageTableTemplate:   'st-attachments-managetable',

        uploadButton:          'st-attachments-uploadbutton',
        manageButton:          'st-attachments-managebutton',

        editUploadButton:      'st-edit-mode-uploadbutton',

        attachForm:            'st-attachments-attach-form',
        attachEditMode:        'st-attachments-attach-editmode',
        attachCloseButton:     'st-attachments-attach-closebutton',
        attachFilename:        'st-attachments-attach-filename',
        attachFileError:       'st-attachments-attach-error',
        attachFileList:        'st-attachments-attach-list',
        attachMessage:         'st-attachments-attach-message',
        attachUploadMessage:   'st-attachments-attach-uploadmessage',

        manageTableRows:       'st-attachments-manage-body',
        manageCloseButton:     'st-attachments-manage-closebutton',
        manageDeleteButton:    'st-attachments-manage-deletebutton',
        manageDeleteMessage:   'st-attachments-manage-deletemessage',
        manageSelectAll:       'st-attachments-manage-selectall',
        manageTable:           'st-attachments-manage-filelisting'
    },

    jst: {
        list: '',
        manageTable: ''
    },

    delete_new_attachments: function (cb) {
        if (this.attachments == null) return;
        // Delete all attachments from _newAttachments
        try {
            for (var i=0; i < this.attachments.length; i++) {
                var file = this.attachments[i];
                if (this._newAttachments[file.id]) {
                    this._delete_attachment(file.uri);
                    this.attachments.splice(i--,1); // i has a new value, so recheck
                }
            }
            this._newAttachments = {};
            this._refresh_attachment_list();
        }
        catch(e) { 
            alert(String(e));
        }
    },

    reset_new_attachments: function () {
        this._newAttachments = {};
    },

    get_new_attachments: function () {
        if (this.attachments == null)
            return [];
        return this.attachments.grep((function(file) {
            return this._newAttachments[file.id];
        }).bind(this));
    },

    extract: function (id) {
        var self = this;
        Jemplate.Ajax.post(
            location.pathname,
            'action=attachments_extract' +
            ';page_id=' + Page.page_id +
            ';attachment_id=' + id,
            function () {
                self._pullAttachmentList(
                    self._refresh_manage_table.bind(self)
                );
                self._reload = true;;
            }
        );
    },

    _applyArgument: function (arg) {
        if (typeof this[arg.key] != 'undefined') {
            this[arg.key] = arg.value;
        }
    },

    _parseFiles: function (node) {
        var inputs = node.getElementsByTagName('input');
        var new_files = {};
        for (var i=0; i<inputs.length; i++) {
            var file_id = inputs[i].value;
            this._newAttachments[file_id] = 1;
            new_files[file_id] = 1;
        }
        return new_files;
    },

    _attach_status_check: function () {
        var doc = null;
        Try.these(
            function () { doc = $('st-attachments-attach-formtarget').contentWindow.document; },
            function () { doc = $('st-attachments-attach-formtarget').contentDocument; }
        );

        if (!doc) return;
        if (!doc.getElementById('attachments')) return;
        clearInterval(this._attach_waiter);

        var files = this._parseFiles(doc);

        $(this.element.attachUploadMessage).style.display = 'none';
        Element.update(this.element.attachUploadMessage, '');
        this._is_uploading_file = false;
        $(this.element.attachCloseButton).style.display = 'block';
        $(this.element.attachFilename).disabled = false;

        var err = doc.getElementById('error');
        if (err) {
            var msg = err.innerHTML;
            this._show_attach_error(msg);
        }
        else {
            var self = this;
            this._update_uploaded_list($(this.element.attachFilename).value);
            this._pullAttachmentList(
                function() {
                    if (!(window.wikiwyg && wikiwyg.is_editing)) {
                        if (Socialtext.page_type == 'wiki')
                            Page.refresh_page_content(true);
                    }
                    else {
                        try {
                            for (var i=0; i<self.attachments.length; i++) {
                                var file = self.attachments[i];
                                if (files[file.id]) {
                                    self._insert_widget(file);
                                }
                            }
                        }
                        catch (e) {
                            alert(String(e));
                        }
                    }
                }
            );
        }

        doc.location = '/static/html/blank.html';

        Try.these(
            (function() {
                $(this.element.attachFilename).value = '';
                if ($(this.element.attachFilename).value) {
                    throw new Error ("Failed to clear value");
                }
            }).bind(this)
        );
        $(this.element.attachFilename).focus();
        setTimeout(this._hide_attach_error.bind(this), 5 * 1000);
    },

    _insert_widget: function (file) {
        var type = file["content-type"].match(/image/) ? 'image' : 'file';
        var widget_text = type + ': ' + file.name;
        var widget_string = '{' + widget_text + '}';
        wikiwyg.current_mode.insert_widget(widget_string);
    },

    _attach_file_form_submit: function () {
        var filenameField = $(this.element.attachFilename);
        if (! filenameField.value) {
            this._show_attach_error(loc("Please click browse and select a file to upload."));
            return false;
        }

        var filename = filenameField.value.replace(/^.*\\|\/:/, '');

        if (encodeURIComponent(filename).length > 255 ) {
            this._show_attach_error(loc("Filename is too long after URL encoding."));
            return false;
        }

        this._update_ui_for_upload(filenameField.value);
        $(this.element.attachCloseButton).style.display = 'none';

        $(this.element.attachForm).submit();
        $(this.element.attachFilename).disabled = true;

        this._attach_waiter = setInterval(this._attach_status_check.bind(this), 3 * 1000);

        if (window.event)
            window.event.returnValue = false;

        this._reload = true;;

        return false;
    },

    _update_ui_for_upload: function (filename) {
        Element.update(this.element.attachUploadMessage, 
                       loc('Uploading [_1]...', filename.match(/[^\\\/]+$/))
                      );

        this._is_uploading_file = true;

        $(this.element.attachUploadMessage).style.display = 'block';

        this._hide_attach_error();
    },

    _clear_uploaded_list: function () {
        this._uploaded_list = [];
        this._refresh_uploaded_list();
    },

    _delete_attachment: function (uri) {
        var ar = new Ajax.Request( uri, {
            method: 'post',
            requestHeaders: ['X-Http-Method','DELETE'],
            asynchronous: false
        });
    },

    _delete_selected_attachments: function () {
        var to_delete = [];
        $A($(this.element.manageTableRows).getElementsByTagName('tr')).each(function (node) {
            if (node.getElementsByTagName('input')[0].checked) {
                Element.hide(node);
                to_delete.push(node.getElementsByTagName('input')[0].value);
            }
        });
        if (to_delete.length == 0)
            return false;

        for (i = 0; i < to_delete.length; i++) {
            this._delete_attachment(to_delete[i]);
        }

        this._pullAttachmentList();
        
        if (Socialtext.page_type == 'wiki')
            Page.refresh_page_content(true);

        this._reload = true;

        return false;
    },

    _display_attach_interface: function () {
        $(this.element.attachEditMode).value = (
            window.wikiwyg && wikiwyg.is_editing
        ) ? '1' : '0';
        field = $(this.element.attachFilename);
        Try.these(function () {
            field.value = '';
        });

        jQuery.showLightbox({
            content: '#st-attachments-attach-interface',
            focus: '#this.element.attachFilename'
        });
        return false;
    },

    _display_manage_interface: function () {
        $(this.element.manageSelectAll).checked = false;
        this._refresh_manage_table();
        jQuery.showLightbox({
            content: '#st-attachments-manage-interface'
        });

        this._table_sorter = new Widget.SortableTable( {
            "tableId": this.element.manageTable,
            "initialSortColumn": 1,
            "columnSpecs": [
              { skip: true },
              { sort: "text" },
              { sort: "text" },
              { sort: "date" },
              { sort: sort_filesize}
            ]
          } );
        return false;
    },

    _hide_attach_error: function () {
        $(this.element.attachFileError).style.display = 'none';
    },

    _check_reload: function() {
        if (
            !(window.wikiwyg && wikiwyg.is_editing)
            && this._reload
        ) {
            jQuery(window).trigger("reload");
            location.reload();
        }
    },

    _hide_attach_file_interface: function () {
        if (!this._is_uploading_file) {
            jQuery.hideLightbox();
            this._clear_uploaded_list();
            this._check_reload();
        }
        return false;
    },

    _hide_manage_file_interface: function () {
        jQuery.hideLightbox();
        this._check_reload();
        return false;
    },

    _pullAttachmentList: function (cb) {
        if (this.attachments == null) {
            this.attachments = Socialtext.attachments;
            if (cb) cb();
        }
        else {
            new Ajax.Request(
                Page.AttachmentListUri(),
                {
                    method: 'get',
                    requestHeaders: ['Accept', 'application/json'],
                    onComplete: (function (req) {
                        this.attachments = JSON.parse(req.responseText);
                        this._refresh_attachment_list();
                        if (cb) cb();
                    }).bind(this)
                }
            );
        }
        this._refresh_attachment_list();
    },

    _refresh_attachment_list: function () {
        if (this.attachments && this.attachments.length > 0) {
            var data = {};
            data.attachments = this.attachments;
            this.jst.list.update(data);
        } else {
            this.jst.list.clear();
        }
        return false;
    },

    _refresh_manage_table: function () {
        if (this.attachments && this.attachments.length > 0) {
            var data = {};
            data.attachments = this.attachments;
            var i;
            for (i=0; i< data.attachments.length; i++) {
                var filesize = data.attachments[i]['content-length'];
                var n = 0;
                var unit = '';
                if (filesize < 1024) {
                    unit = 'B';
                    n = filesize;
                } else if (filesize < 1024*1024) {
                    unit = 'K';
                    n = filesize/1024;
                    if (n < 10)
                        n = n.toPrecision(2);
                    else
                        n = n.toPrecision(3);
                } else {
                    unit = 'M';
                    n = filesize/(1024*1024);
                    if (n < 10) {
                        n = n.toPrecision(2);
                    } else if ( n < 1000) {
                        n = n.toPrecision(3);
                    } else {
                        n = n.toFixed(0);
                    }
                }
                data.attachments[i].displaylength = n + unit;
            }
            data.page_name = Page.page_id;
            data.workspace = Page.wiki_id;
            Try.these(
                (function () {
                    this.jst.manageTable.update(data);
                }).bind(this),
                (function () { /* http://www.ericvasilik.com/2006/07/code-karma.html */
                    var temp = document.createElement('div');
                    temp.innerHTML = '<table><tbody id="' + this.element.manageTableRows + '-temp">' +
                                     this.jst.manageTable.html(data) + '</tbody></table>';
                    $(this.element.manageTableRows).parentNode.replaceChild(
                        temp.childNodes[0].childNodes[0],
                        $(this.element.manageTableRows)
                    );
                    $(this.element.manageTableRows + '-temp').id = this.element.manageTableRows;
                }).bind(this)
            );
        } else {
            Try.these(
                (function () {
                    this.jst.manageTable.clear();
                }).bind(this),
                (function () { /* http://www.ericvasilik.com/2006/07/code-karma.html */
                    var temp = document.createElement('div');
                    temp.innerHTML = '<table><tbody id="' + this.element.manageTableRows + '-temp"></tbody></table>';
                    $(this.element.manageTableRows).parentNode.replaceChild(
                        temp.childNodes[0].childNodes[0],
                        $(this.element.manageTableRows)
                    );
                    $(this.element.manageTableRows + '-temp').id = this.element.manageTableRows;
                }).bind(this)
            );
        }
        return false;
    },

    _refresh_uploaded_list: function () {
        if (this._uploaded_list.length > 0) {
            Element.update(this.element.attachFileList, '<span class="st-attachments-attach-listlabel">' + loc('Uploaded files:') + ' </span>' + this._uploaded_list.join(', '));
            $(this.element.attachFileList).style.display = 'block';
        }
        else {
            $(this.element.attachFileList).style.display = 'none';
            Element.update(this.element.attachFileList, '');
        }
    },

    _show_attach_error: function (msg) {
        if (!msg)
            msg = '&nbsp;';
        Element.update(this.element.attachFileError, msg);
        $(this.element.attachFileError).style.display = 'block';
    },

    _toggle_all_attachments: function () {
        var checkbox = $(this.element.manageSelectAll);

        $A($(this.element.manageTableRows).getElementsByTagName('tr')).each(
            function (node) {
                node.getElementsByTagName('input')[0].checked = checkbox.checked;
            }
        );
    },

    _update_uploaded_list: function (filename) {
        var match = filename.match(/^.+[\\\/]([^\\\/]+)$/);
        this._uploaded_list.push(match == null ? filename : match[1]);
        this._refresh_uploaded_list();
    },

    _loadInterface: function () {
        var self = this;
        this.jst.list = new ST.TemplateField(this.element.listTemplate, 'st-attachments-listing');
        this.jst.manageTable = new ST.TemplateField(this.element.manageTableTemplate, this.element.manageTableRows);

        if ($(this.element.attachFilename)) {
            Event.observe(this.element.attachFilename, 'change', this._attach_file_form_submit.bind(this));
        }

        jQuery("#" + this.element.uploadButton).click(function() {
            self._display_attach_interface();
        });

        if ($(this.element.editUploadButton)) {
            Event.observe(this.element.editUploadButton,       'click',  this._display_attach_interface.bind(this));
        }

        jQuery("#" + this.element.manageButton).click(function() {
            self._display_manage_interface();
        });

        if ($(this.element.manageCloseButton)) {
            Event.observe(this.element.manageCloseButton,  'click',  this._hide_manage_file_interface.bind(this));
        }
        if ($(this.element.manageDeleteButton)) {
            Event.observe(this.element.manageDeleteButton, 'click',  this._delete_selected_attachments.bind(this));
        }
        if ($(this.element.manageSelectAll)) {
            Event.observe(this.element.manageSelectAll,    'click',  this._toggle_all_attachments.bind(this));
        }
        if ($(this.element.attachCloseButton)) {
            Event.observe(this.element.attachCloseButton,  'click',  this._hide_attach_file_interface.bind(this));
        }

        this._pullAttachmentList();
    }
};
