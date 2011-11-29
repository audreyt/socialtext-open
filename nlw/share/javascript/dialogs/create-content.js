(function ($) {

var CreateContentDialog = function() {};
var proto = CreateContentDialog.prototype = {
    visible_types: {
        xhtml: loc('page.type-xhtml')
    },
    type_radio: function (type) {
        return this.dialog.find("#"+type+"-radio")
    },

    from_blank_radio: function () { 
        return this.dialog.find('.from-blank input[type=radio]');
    },

    from_template_radio: function () { 
        return this.dialog.find('.from-template input[type=radio]');
    },

    from_template_select: function () { 
        return this.dialog.find('.from-template select');
    },

    from_page_radio: function () { 
        return this.dialog.find('.from-page input[type=radio]');
    },

    from_page_text: function () { 
        return this.dialog.find('.from-page input[type=text]');
    },
    choices: function () { return this.dialog.find('.choice input') },
    error: function () { return this.dialog.find$('.error') },

    get_from_page: function() {
        if (this.from_page_radio().is(':checked')) {
            return this.from_page_text().val();
        }
        else if (this.from_template_radio().is(':checked')) {
            return decodeURIComponent(this.from_template_select().val());
        }
        else {
            return;
        }
    },

    update_templates: function (template_tag) {
        var self = this;
        var type = this.selected_template_type();

        var template = template_tag || loc('tag.template');
        $.ajax({
            url: st.workspace.uri() + '/tags/' + template + '/pages?type=' + type,
            cache: false,
            dataType: 'json',
            success: function (pages) {
                self.from_template_select().html('');
                if (!pages.length) {
                    if (template_tag != 'template') {
                        // We don't have anything tagged as loc('tag.template') -
                        // fallback to look into pages tagged as literal "template".
                        return self.update_templates('template');
                    }

                    if (self.from_template_radio().is(':checked')) {
                        self.from_blank_radio().click();
                    }
                    self.from_template_radio().attr('disabled', 'disabled');
                    var error = loc(
                        "error.no-page=type,tag",
                        loc("page.type-"+type), template
                    );

                    self.from_template_select()
                        .html('<option selected="true">'+error+'</option>')
                        .attr('disabled', 'disabled')
                        .css({'font-style': 'italic'});
                }
                else {
                    self.from_template_radio().removeAttr('disabled');
                    self.from_template_select()
                        .removeAttr('disabled')
                        .css({'font-style': 'normal'});
                    if (self.from_template_radio().is(':checked')) {
                        self.from_template_select().removeAttr('disabled');
                    }
                    for (var i = 0,l=pages.length; i < l; i++) {
                        $('<option></option>')
                            .val(pages[i].page_id)
                            .html(pages[i].name)
                            .appendTo(self.from_template_select());
                    }
                    self.from_template_select()
                        .change(function() {
                            self.from_template_radio().attr('checked', 'true');
                        });
                }
            }
        });
    },

    create_page_lookahead: function () {
        var self = this;
        this.from_page_text().lookahead({
            url: function () {
                return st.workspace.uri() + '/pages?type=' +
                    self.selected_template_type();
            },
            params: { minimal_pages: 1 },
            linkText: function (i) { return i.name }
        });
    },

    selected_page_type: function () {
        var self = this;
        var page_type = 'xhtml';
        this.choices().each(function () {
            if ($(this).is(":checked")) {
                page_type = $(this).val();
                var label = $('label[for='+this.id+']');
                self.visible_types[page_type] = loc(label.html());
            }
        });
        return page_type;
    },

    selected_visible_type: function () {
        var type = this.selected_page_type();
        return this.visible_types[type] || type;
    },

    // Treat wiki templates and copied pages the same as xhtml
    selected_template_type: function() {
        var type = this.selected_page_type();
        if (type == 'xhtml') type = 'wiki,xhtml';
        return type;
    },

    show: function (opts) {
        var self = this;

        this.dialog = st.dialog.createDialog({
            html: st.dialog.process('create-content.tt2', $.extend({
                content_types: st.content_types
            }, opts)),
            title: loc('page.create'),
            buttons: [
                {
                    id: 'st-create-content-savelink',
                    text: loc('do.create'),
                    click: function() { self.dialog.find('form').submit() }
                },
                {
                    id: 'st-create-content-cancellink',
                    text: loc('do.cancel'),
                    click: function() { self.dialog.close() }
                }
            ]
        });

        self.from_blank_radio().focus();

        // Clear errors from the previous time around: {bz: 1039}
        self.dialog.find('.error').html('');

        // Bind radio buttons
        self.from_blank_radio().unbind('click').click(function () {
        });
        self.from_template_radio().unbind('click').click(function () {
            self.from_template_select();
        });
        self.from_page_radio().unbind('click').click(function () {
            self.from_page_text().val('');
            self.from_page_text().unbind('focus').focus().select();
            self.from_page_text().unbind('focus').focus(function () {
                self.from_page_radio().click();
            });
        });
        self.choices().unbind('click').click(function () {
            self.update_templates();
            self.create_page_lookahead();
        });
        self.from_template_select().unbind('click').click(function () {
            self.from_template_radio().click();
        });
        self.from_template_select().unbind('click').click(function () {
            self.from_template_radio().click();
        });
        self.from_page_text().unbind('focus').focus(function () {
            self.from_page_radio().click();
        });

        var default_from_page_text = loc('page.prompt-name');
        self.from_page_text()
            .val(default_from_page_text)
            .unbind('click').click(function () {
                if ($(this).val() == default_from_page_text) {
                    $(this).val('');
                }
            })

        // Set the defaults
        if (self.type_radio('xhtml').length) {
            self.type_radio('xhtml').click();
        }
        else {
            self.update_templates();
        }
        self.from_blank_radio().click();
        self.create_page_lookahead();

        self.dialog.find('#st-create-content-form')
            .unbind('submit')
            .submit(function () { self.create_new_page(); return false });

        $('#st-create-content-lightbox .submit').click(function () {
            $(this).parents('form').submit();
        });
    },

    create_new_page: function () {
        var self = this;
        try {
            var url = this.create_url();
            if (url) document.location = url;    
        }
        catch (e) {
            this.error().show().html(e.message).show();
        }
    },

    set_incipient_title: function (title) {
        this._incipient_title = title;
    },

    create_url: function () {
        var self = this;
        var type = this.selected_page_type();
        var url;
        if (this._incipient_title) {
            url = "?action=display;is_incipient=1;page_name="
                + encodeURIComponent(this._incipient_title)
        }
        else {
            url = "?action=new_page";
        }
        url += ";page_type=" + type;

        var template = this.get_from_page();
        if (template) {
            url += ';template=' + nlw_name_to_id(template);

            $.ajax({
                url: st.workspace.uri() + '/pages/' + nlw_name_to_id(template),
                async: false,
                dataType: 'json',
                success: function (page) {
                    if (page.type != type) {
                        throw new Error(loc(
                            "error.type-mismatch=template,type",
                            template,
                            self.selected_visible_type()
                        ));
                    }
                },
                error: function () {
                    throw new Error(loc("error.no-page=template", template));
                }
            });
        }
        return url;
    }
};

st.dialog.register('create-content', function(opts) {
    var cc = new CreateContentDialog();
    if (opts && opts.incipient_title) {
        cc.set_incipient_title(opts.incipient_title);
    }
    cc.show();
});

})(jQuery);
