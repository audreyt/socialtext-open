(function ($) {

var ST = window.ST = window.ST || {};

ST.CreateContent = function () {}
var proto = ST.CreateContent.prototype = new ST.Lightbox;

proto.visible_types = {
    wiki: loc('page.type-wiki')
};

proto.type_radio = function (type) {
    return $("#st-create-content-lightbox #"+type+"-radio")
}

proto.from_blank_radio = function () { 
    return $('#create-content-from-blank input[type=radio]');
}

proto.from_template_radio = function () { 
    return $('#create-content-from-template input[type=radio]');
}

proto.from_template_select = function () { 
    return $('#create-content-from-template select');
}

proto.from_page_radio = function () { 
    return $('#create-content-from-page input[type=radio]');
}

proto.from_page_text = function () { 
    return $('#create-content-from-page input[type=text]');
}

proto.choices = function () {
    return $('#st-create-content-lightbox .choice input');
}

proto.error = function () {
    return $('#st-create-content-lightbox .error');
}

proto.get_from_page = function() {
    if (this.from_page_radio().is(':checked')) {
        return this.from_page_text().val();
    }
    else if (this.from_template_radio().is(':checked')) {
        return decodeURIComponent(this.from_template_select().val());
    }
    else {
        return;
    }
}

proto.update_templates = function (template_tag) {
    var self = this;
    var type = this.selected_page_type();
    var template = template_tag || loc('tag.template');
    $.ajax({
        url: Page.workspaceUrl() + '/tags/' + template + '/pages?type=' + type,
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
                self.from_template_radio().attr('disabled', '');
                self.from_template_select()
                    .attr('disabled', '')
                    .css({'font-style': 'normal'});
                if (self.from_template_radio().is(':checked')) {
                    self.from_template_select().attr('disabled', '');
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
}

proto.create_page_lookahead = function () {
    var self = this;
    var workspace_url = Page.workspaceUrl();
    this.from_page_text().lookahead({
        url: function () {
            return workspace_url + '/pages?type=' +
                self.selected_page_type();
        },
        params: { minimal_pages: 1 },
        linkText: function (i) { return i.name }
    });
}

proto.selected_page_type = function () {
    var self = this;
    var page_type = 'wiki';
    this.choices().each(function () {
        if ($(this).is(":checked")) {
            page_type = $(this).val();
            var label = $('label[for='+this.id+']');
            self.visible_types[page_type] = loc(label.html());
        }
    });
    return page_type;
}

proto.selected_visible_type = function () {
    var type = this.selected_page_type();
    return this.visible_types[type] || type;
}

proto.show = function () {
    var self = this;

    this.process('create_content.tt2');

    // Clear errors from the previous time around: {bz: 1039}
    $('#st-create-content-lightbox .error').html('');

    // Bind radio buttons
    this.from_blank_radio().unbind('click').click(function () {
    });
    this.from_template_radio().unbind('click').click(function () {
        self.from_template_select();
    });
    this.from_page_radio().unbind('click').click(function () {
        self.from_page_text().val('');
        self.from_page_text().unbind('focus').focus().select();
        self.from_page_text().unbind('focus').focus(function () {
            self.from_page_radio().click();
        });
    });
    this.choices().unbind('click').click(function () {
        self.update_templates();
        self.create_page_lookahead();
    });
    this.from_template_select().unbind('click').click(function () {
        self.from_template_radio().click();
    });
    this.from_template_select().unbind('click').click(function () {
        self.from_template_radio().click();
    });
    this.from_page_text().unbind('focus').focus(function () {
        self.from_page_radio().click();
    });

    var default_from_page_text = loc('page.prompt-name');
    this.from_page_text()
        .val(default_from_page_text)
        .unbind('click').click(function () {
            if ($(this).val() == default_from_page_text) {
                $(this).val('');
            }
        })

    // Set the defaults
    this.type_radio('wiki').click();
    this.from_blank_radio().click();
    this.update_templates();
    this.create_page_lookahead();

    $('#st-create-content-lightbox #st-create-content-form')
        .unbind('submit')
        .submit(function () { self.create_new_page(); return false });

    $('#st-create-content-lightbox .submit').click(function () {
        $(this).parents('form').submit();
    });

    $.showLightbox({
        content:'#st-create-content-lightbox',
        close:'#st-create-content-lightbox .close',
        callback: function() {
            self.from_blank_radio().focus();
        }
    });
}

proto.create_new_page = function () {
    var self = this;
    try {
        var url = this.create_url();
        if (url) document.location = url;    
    }
    catch (e) {
        this.error().show().html(e.message).show();
    }
}

proto.set_incipient_title = function (title) {
    this._incipient_title = title;
}

proto.create_url = function () {
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
            url: Page.workspaceUrl() + '/pages/' + nlw_name_to_id(template),
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

})(jQuery);
