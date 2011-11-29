(function($) {

if (typeof(Activities) == 'undefined') Activities = {};

Activities.Base = function() {}

Activities.Base.prototype = {
    toString: function() { return 'Activities.Base' },

    extend: function(values) {
        var defaults = $.isFunction(this._defaults)
            ? this._defaults()
            : this._defaults;
        $.extend(true, this, defaults, values);
    },

    requires: function(requires) {
        var self = this;
        requires = requires.concat([
            'prefix', 'node'
        ]);
        $.each(requires, function(i, require) {
            if (typeof self[require] == 'undefined') {
                var err = self + ' requires ' + require;
                self.showError(err);
                throw new Error(err);
            }
        });
    },

    findId: function(id) {
        var win = arguments.length > 1 ? arguments[1] : window
        return $('#' + this.prefix + id);
    },

    hasTemplate: function(tmpl) {
        return Jemplate.templateMap[tmpl] ? true : false;
    },

    processTemplate: function(template, vars) {
        var self = this;
        var template_vars = {
            'this': self,
            'loc': loc,
            'id': function(rest) { return self.prefix + rest }
        };
        if (vars) $.extend(template_vars, vars);
        return Jemplate.process(template, template_vars);
    },

    makeRequest: function(uri, callback, force, vars) {
        var self = this;
        var params = {};
        params[gadgets.io.RequestParameters.CONTENT_TYPE] = 
            gadgets.io.ContentType.JSON;
        params[gadgets.io.RequestParameters.REFRESH_INTERVAL]
            = force ? 0 : 30;
        if (vars) $.extend(params, vars);
        gadgets.io.makeRequest(uri, function(data) {
            if (data.rc == 503) {
                // do it again in a second
                setTimeout(function() {
                    self.makeRequest(uri, callback, force);
                }, 1000);
            }
            else {
                callback(data);
            }
        }, params);
    },

    makePutRequest: function(uri, callback) {
        var params = {};
        params[gadgets.io.RequestParameters.METHOD]
            = gadgets.io.MethodType.PUT;
        this.makeRequest(uri, callback, true, params);
    },

    makeDeleteRequest: function(uri, callback) {
        var params = {};
        params[gadgets.io.RequestParameters.METHOD]
            = gadgets.io.MethodType.DELETE;
        this.makeRequest(uri, callback, true, params);
    },

    adjustHeight: function() {
        if (gadgets.window && gadgets.window.adjustHeight)
            gadgets.window.adjustHeight();
    },

    showMessageNotice: function (opts) {
        var $msg = this.addMessage({
            className: opts.className,
            onCancel: opts.onCancel,
            html: this.processTemplate(
                'activities/message_notice.tt2', opts
            )
        });
        if (opts.links) {
            $.each(opts.links, function(selector, onclick) {
                $msg.find(selector).click(onclick);
            });
        }
        this.adjustHeight();
        return $msg;
    },

    addMessage: function(opts) {
        // Don't show duplicate message types
        this.clearMessages(opts.className);

        var $msg = $('<div class="message"></div>')
            .addClass(opts.className)
            .html(opts.html)
            .prependTo(this.findId('messages'));

        // if there's an onCancel handler, add a [x] button
        if (opts.onCancel) {
            $msg.append(
                '[',
                $('<a href="#" class="cancel">x</a>')
                    .click(opts.onCancel),
                ']'
            );
        }

        this.adjustHeight();

        return $msg;
    },

    clearMessages: function() {
        var self = this;
        $.each(arguments, function(i, className) {
            self.findId('messages .' + className).remove();
        });
        this.adjustHeight();
    },

    showError: function(err) {
        if (err instanceof Error) err = err.message;
        if (this.findId('messages').size()) {
            this.addMessage({ className: 'error', html: err });
        }
        else {
            $(".error", this.node).remove();
            $(this.node).prepend("<span class='error'>"+err+"</span>");
        }
    },

    clearErrors: function() {
        if (!this.findId('messages').size()) {
            $(".error", this.node).remove();
        }
    },

    scrollTo: function($element) {
        $('html,body').animate({ scrollTop: $element.offset().top});
    },

    round: function(i) {
        return Math.round(i);
    },

    minutes_ago: function(at) {
        if (!at) return;
        var now = new Date();
        var then = new Date();
        then.setISO8601(at);
        return Math.round(
            (now.getTime() - then.getTime()) / 60000
        );
    }
};

})(jQuery);
