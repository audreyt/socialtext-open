Socialtext.prototype.dialog = (function($) {
    var dialogs = {};
    var loaded = {};

    var timestamp = (new Date).getTime();

    function _pageErrorString(data, new_title, button) {
        if (data.page_exists) {
            return loc('error.page-exists=title,button', new_title, button);
        }
        else if (data.page_title_bad) {
            return loc('error.invalid-page-name=title', new_title);
        }
        else if (data.page_title_too_long) {
            return loc('error.long-page-name=title', new_title);
        }
        else if (data.same_title) {
            return loc('error.same-page-name=title', new_title);
        }
    }

    // Socialtext adapter class for jQuery dialogs
    var Dialog = function(opts) {
        this.show(opts);
    };
    Dialog.prototype = {
        show: function(opts) {
            var self = this;
            // content
            var opts = typeof(opts) == 'string' ? { html: opts } : opts;
            self.node = opts.content
                ? $(content)
                : $('<div></div>').html(opts.html);

            self.node.dialog($.extend({
                width: 520,
                modal: true,
                close: function() { self.close() }
            }, opts));
        },
        close: function() {
            this.node.dialog('destroy').remove();
        },
        find: function(selector) { return this.node.find(selector) },
        showError: function(err) { this.node.find('.error').html(err) },
        disable: function() {
            this.node.parents('.ui-dialog').uiDisable();
        },
        enable: function() {
            this.node.parents('.ui-dialog').uiEnable();
        },

        submitPageForm: function(callback) {
            var self = this;
            self.disable();
            var button_title = self.node.dialog("option", "buttons")[0].text;
            $.ajax({
                url: st.page.web_uri(),
                data: self.find('form').serializeArray(),
                type: 'post',
                dataType: 'json',
                async: false,
                success: function (data) {
                    var title = self.find('input[name=new_title]').val();
                    var error = _pageErrorString(data, title, button_title);
                    if (error) {
                        self.find('input[name=clobber]').remove();
                        self.find('form').append(
                            $('<input name="clobber" type="hidden">')
                                .attr('value', title)
                        );
                        self.find('.error').html(error).show();
                        self.enable();
                    }
                    else {
                        if ($.isFunction(callback)) callback();
                    }
                },
                error: function (xhr, textStatus, errorThrown) {
                    self.find('.error').html(textStatus).show();
                    self.enable();
                }
            });
        }
    };

    return {
        createDialog: function(opts) {
            return new Dialog(opts);
        },

        show: function(name, args) {
            var self = this;
            if (loaded[name]) {
                self.callDialog(name, args);
            }
            else {
                loaded[name] = true;
                $.ajaxSettings.cache = true;
                $.ajax({
                    url: st.nlw_make_js_path('dialog-' + name + '.jgz'),
                    dataType: 'script',
                    success: function() {
                        self.callDialog(name, args)
                    },
                    error: function(jqXHR, textStatus, errorThrown) {
                        throw errorThrown;
                    }
                });
                $.ajaxSettings.cache = false;
            }
        },

        callDialog: function(name, args) {
            if (!dialogs[name]) throw new Error(name + " didn't register!");
            dialogs[name].call(this, args);
        },

        register: function(name, callback) {
            dialogs[name] = callback;
        },
        
        showResult: function (opts) {
            this.show('simple', {
                title: opts.title || loc('nav.result'),
                message: opts.message,
                width: 400,
                onClose: opts.onClose
            });
        },

        showError: function (message, onClose) {
            this.show('simple', {
                title: loc('nav.error'),
                message: '<div class="error">' + message + '</div>',
                width: 400,
                onClose: onClose
            });
        },

        process: function (template, vars) {
            vars = vars || {};
            vars.loc = loc;
            return Jemplate.process(template, vars);
        }
    };
})(jQuery);

// Compat
$.hideLightbox = function() { throw new Error('$.hideLightbox deprecated') }
$.showLightbox = function() { throw new Error('$.showLightbox deprecated') }
$.pauseLightbox = function() { throw new Error('$.pauseLightbox deprecated') }
$.resumeLightbox = function() { throw new Error('$.resumeLightbox deprecated') }

// Temporary compat
if (typeof(socialtext) == 'undefined') socialtext = {};
socialtext.dialog = Socialtext.prototype.dialog;
