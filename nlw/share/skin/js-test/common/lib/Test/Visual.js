(function($) { 

var proto = Test.Base.newSubclass('Test.Visual');

proto.init = function() {
    Test.Base.prototype.init.call(this);
    this.block_class = 'Test.Visual.Block';
    this.doc = window.document;
    this.asyncId = 0;
}

// This vicious hack replaces the guts of the Test.Harness. For some reason
// this fixture gets the Harness iframe to have its location messed up.
// We do not know why yet, but this is a workaround for now.
if (window.top.Test.Harness && ! window.top.Test.Harness.viciously_hacked) {
    window.top.Test.Harness.viciously_hacked = true;
    var runTest = window.top.Test.Harness.Browser.prototype.runTest;
    var path = '';
    window.top.Test.Harness.Browser.prototype.runTest =
        function (file, buffer) {
            if (! path)
                path = buffer.location.pathname.replace(/(.*)\/.*/, '$1');
            file = path + '/' + file;
            if (/\.html$/.test(file)) {
                buffer.location.replace(file);
            } else {
                runTest.apply([this, arguments]);
            }
        }
}

// Move to Test.Base
proto.diag = function() {
    this.builder.diag.apply(this.builder, arguments);
}

proto.runAsync = function(steps, timeout) {
    this.asyncSteps = steps;
    this.asyncStep = 0;

    this.beginAsync(this.nextStep(), timeout); 
}

proto.nextStep = function(delay) {
    var step = this.asyncSteps[this.asyncStep++];

    if (delay) {
        var self = this;
        return function() {
            setTimeout(step, delay);
        }
    }
    else {
        return step;
    }
}

proto.callNextStep = function(delay) {
    if (delay) {
        var self = this;
        setTimeout(function(){
            self.callNextStep();
        }, delay);
    }
    else {
        this.call_callback(this.nextStep());
    }
}

proto.is_no_harness = function() {
    if (window.top.Test.Harness) {
        this.builder.diag(
            "Can't run test " + (this.builder.CurrTest + 1) + " in the harness"
        );
        this.builder.skip(arguments[2]);
    }
    else
        this.is.apply(this, arguments);
}

proto.ok_no_harness = function() {
    if (window.top.Test.Harness) {
        this.builder.diag(
            "Can't run test " + (this.builder.CurrTest + 1) + " in the harness"
        );
        this.builder.skip(arguments[2]);
    }
    else
        this.ok.apply(this, arguments);
}


proto.create_user = function(params, callback) {
    var self = this;

    var add_to_workspace = function() {
        $.ajax({
            url: "/data/workspaces/" + params.workspace + '/users',
            type: 'POST',
            contentType: 'application/json',
            data: JSON.stringify({
                username: params.username,
                role_name: "member",
                send_confirmation_invitation: 0
            }),
            success: function() {
                self.call_callback(callback);
            }
        });
    }

    var callback2 = params.workspace
        ? add_to_workspace
        : callback;

    $.ajax({
        url: "/data/users",
        type: 'POST',
        contentType: 'application/json',
        data: JSON.stringify({
            username: params.username,
            password: params.password,
            email_address: params.email_address
        }),
        success: function() {
            self.call_callback(callback2);
        }
    });
}

proto.put_page = function(params) {
    var self = this;

    var workspace = params.workspace;
    var page_name = encodeURIComponent(params.page_name);

    $.ajax({
        url: "/data/workspaces/" + workspace + "/pages/" + page_name +
            '?http_method=PUT',
        type: 'POST',
        contentType: 'text/x.socialtext-wiki',
        dataType: 'text',
        data: params.content, 
        tags: params.tags || [], 
        success: function() {
            if( $.isFunction(params.callback) )
                self.call_callback(params.callback);
        },
        error: function(x) {
            XXX(x.statusText + '\nstatus: ' + x.status);
        }
    });
}

proto.login = function(params, callback) {
    var username = (params.username || 'devnull1@socialtext.com');
    var password = (params.password || 'd3vnu11l');

    var self = this;
    $.ajax({
        url: "/nlw/submit/logout",
        complete: function() {
            $.ajax({
                url: "/nlw/submit/login",
                type: 'POST',
                data: {
                    'username': username,
                    'password': password
                },
                success: function() {
                    if (callback)
                        self.call_callback(callback);
                }

            });
        }
    });
}

proto.test_iframe_html = 
    '<div class="iframe_info" style="padding-bottom: 5px">' +
    '<b>Size: <span>100 x 100</span> &nbsp;&nbsp;&nbsp;' + 
    'URL: <input style="width:400px" class="iframe_location" value="/" />' +
    '</b></div>'

proto.open_iframe = function(url, callback, options) {
    if (! (url && callback))
        throw("usage: open_iframe(url, callback, [options])");
    if (! options)
        options = {};

    if (!this.iframe) {
        this.iframe = $("<iframe />").prependTo("body").get(0);
        $(this.test_iframe_html).prependTo("body");
    }
    this.iframe.contentWindow.location = url;
    var $iframe = $(this.iframe);

    $iframe.height(options.h || 200);
    $iframe.width(options.w || "100%");

    $("div.iframe_info span").html($iframe.width() + "x" + $iframe.height());
    $("input.iframe_location").val(url);

    var self = this;
    $iframe.one("load", function() {
        self.doc = self.iframe.contentDocument
                || self.iframe.contentWindow.document;
        self.win = self.iframe.contentWindow;
        self.$ = self.iframe.contentWindow.jQuery;
        
        self.call_callback(callback);
    });
}

proto.poll = function(test, callback, interval, maximum) {
    if (! (test && callback)) {
        throw("usage: jQuery.poll(test_func, callback [, interval_ms, maximum_ms])");
    }
    if (! interval) interval = 250;
    if (! maximum) maximum = 30000;

    setTimeout(
        function() {
            if (id) {
                clearInterval(id);
                throw("jQuery.poll failed");
            }
        }, maximum
    );

    var id = setInterval(function() {
        if (test()) {
            clearInterval(id);
            id = 0;
            callback();
        }
    }, interval);
};

proto.setup_one_widget = function(params, callback) {
    var name = typeof(params) == 'string' ? params : params.name;
    if (typeof(params) == 'string') params = {};
    var self = this;

    $.ajax({
        url: "/?action=clear_widgets",
        async: false
    });


    var setup_widget = function() {
        $(self.iframe).one("load", function() {
            self.doc = self.iframe.contentDocument
                    || self.iframe.contentWindow.document;
            self.win = self.iframe.contentWindow;
            self.$ = self.iframe.contentWindow.jQuery;

            var widget = self._get_widget();
            if (params.noPoll) {
                self.call_callback(callback, [widget]);
                return;
            }

            self.poll(
                function() { return Boolean(widget.win.gadgets.loaded) },
                function() { self.call_callback(callback, [widget])}
            );

        });

        var $anchor = self.$('div.title:contains(' + name + ')').nextAll('ul.widgetButton').find('a');
        var url = $anchor.attr('href').replace( /^\/*/, '/st/dashboard' );

        self.iframe.contentWindow.location = url;
        $("input.iframe_location").val(url);
    }

    self.open_iframe("/st/dashboard?gallery=1", setup_widget);
}

proto.getWidget = function(widget_name, callback) {
    var widget = this._get_widget(widget_name);
    var self = this;
    this.$.poll(
        function() { return Boolean(widget.win.gadgets.loaded) },
        function() { self.call_callback(callback, [widget])}
    );
}

proto._get_widget = function(widget_name) {
    var iframe;
    if (widget_name) {
        iframe = this.$('.widgetHeaderTitle span[title=' + widget_name + ']')
                     .parents('div.widgetHeader').next('div.widgetContent')
                     .find('iframe.widgetWindow').get(0);
    }
    else {
        iframe = this.$('iframe').get(0);
    }
    if (! iframe) throw("getWidget failed");
    var widget = {
        'iframe': iframe,
        'win': iframe.contentWindow,
        '$': iframe.contentWindow.jQuery
    };
    return widget;
}

proto.create_anonymous_user_and_login = function(params, callback) {
    if (!params.password) params.password = 'd3vnu11l';

    var ts = (new Date()).getTime();
    this.anonymous_username = 'user' + ts + '@example.com';
    var email_address = 'email' + ts + '@example.com';

    if (!params.username) params.username = this.anonymous_username;
    if (!params.email_address) params.email_address = email_address;

    var self = this;
    this.create_user(
        params,
        function() {
            self.login(params, callback);
        }
    );
}

proto.call_callback = function(callback, args) {
    if (!args) args = [];
    if (! this.asyncId)
        throw("You forgot to call beginAsync()");
    callback.apply(this, args);
}

proto.beginAsync = function(callback, timeout) {
    if (!timeout) timeout = 60000;
    if (this.asyncId)
        throw("beginAsync already called");
    this.asyncId = this.builder.beginAsync(timeout);
    var self = this;
    setTimeout(
        function() {
            if (self.asyncId)
                throw("Test timed out. Did you forget to call endAsync?");
        },
        timeout
    );
    if (callback)
        this.call_callback(callback);
}

proto.endAsync = function() {
    if (! this.asyncId)
        throw("endAsync called out of order");

    this._savePage(function() {
        this.builder.endAsync(this.asyncId);
        this.asyncId = 0;
    });
}

proto.scrollTo = function(vertical, horizontal) {
    if (!horizontal) horizontal = 0;
    this.iframe.contentWindow.scrollTo(horizontal, vertical);
}

proto.bindLoad = function(cb) {
    var self = this;
    $(this.iframe).bind("load", function() {
        $(this.contentDocument).ready(function() {
            cb.apply(self);
        });
    });
}

// Maybe extend jQuery with this.
// Uses hairy jQuery internals cargo culting.
proto.callEventHandler = function(query, event) {
    var elem = this.$(query)[0];
    var handle = this.$.data(elem, "handle");
    var data = this.$.makeArray();
    data.unshift({
        type: event,
        target: elem,
        preventDefault: function(){},
        stopPropagation: function(){},
        timeStamp: null
    });

    if (handle)
        var val = handle.apply( elem, data );

    return val;
}

proto.elements_do_not_overlap = function(selector1, selector2, name) {
    var $e1 = $(this._get_selector_element(selector1));
    var $e2 = $(this._get_selector_element(selector2));

    var r1 = $e1.offset();
    r1.bottom = r1.top + $e1.height();
    r1.right = r1.left + $e1.width();

    var r2 = $e2.offset();
    r2.bottom = r2.top + $e2.height();
    r2.right = r2.left + $e2.width();

    if ((r1.bottom > r2.top) &&
        (r1.top < r2.bottom) &&
        (r1.right > r2.left) &&
        (r1.left < r2.right))
    {
        this.fail(name);
        return;
    }

    this.pass(name);
}

proto._get_selector_element = function(selector) {
    var $result = $(selector, this.doc);
    if ($result.length <= 0)
        throw("Nothing found for selector: '" + selector + "'");
    if ($result.length >= 2) {
        throw(String($result.length) + " elements found for selector: '" +
            selector + "'"
        );
    }
    return $result.get(0);
}

proto.checkRichTextSupport = function () {
    if (jQuery.browser.safari) {
        this.skipAll("This test requires Rich Text editing, which is not supported for your browser.");
    }
}

proto.wikiwyg_started = function () {
    return (this.win && this.win.wikiwyg && this.win.wikiwyg.is_editing);
}

proto.richtextModeIsReady = function () {
    return (
        (this.win && this.win.wikiwyg && this.win.wikiwyg.current_mode.classtype == 'wysiwyg') &&
        $(
            this.$('#st-page-editing-wysiwyg').get(0)
             .contentWindow.document.documentElement
        ).find('div.wiki').is(':visible')
    );
};

proto.wikitextModeIsReady = function () {
    return (
        (this.win && this.win.wikiwyg && this.win.wikiwyg.current_mode.classtype == 'wikitext') &&
        this.$('#wikiwyg_wikitext_textarea').is(':visible')
    );
}

proto._doEdit = function(check, button, mode_name) {
    var t = this;
    return function() {
        if (mode_name) {
            t.win.Cookie.set('first_wikiwyg_mode', mode_name);
        }
        t.$('#st-edit-button-link').click();
        t.poll(
            function() { return t.wikiwyg_started() },
            function() {
                if (check.apply(t)) {
                    t.callNextStep(1000);
                    return;
                }
                t.$(button).click();
                t.poll(function() { return check.apply(t) }, function() { t.callNextStep(1500) });
            }
        );
    };
};

proto.click = function(selector) {
    this.$(selector).click();
};

proto.doPreview = function() {
    var t = this;
    return function() {
        t.$('#st-preview-button-link').click();
        t.poll(
            function() { return t.$('#st-page-preview').is(':visible') },
            function() { t.callNextStep(500) }
        );
    };
};

proto.doRichtextEdit = function() {
    this.checkRichTextSupport();
    return this._doEdit(this.richtextModeIsReady, '#st-mode-wysiwyg-button', 'Wikiwyg.Wysiwyg');
};

proto.doWikitextEdit = function() {
    return this._doEdit(this.wikitextModeIsReady, '#st-mode-wikitext-button', 'Wikiwyg.Wikitext');
};

proto.doCreatePage = function(content, opts) {
    var t = this;
    var name = t.gensym();
    return function() {
        t.put_page({
            workspace: 'admin',
            page_name: name,
            content: content || "\n"+name+"\n",
            callback: function() {
                t.open_iframe( "/admin/?" + name, t.nextStep(), opts );
            }
        });
    };
};

proto.doSavePage = function() {
    var t = this;
    return function() {
        t._savePage(function() { t.callNextStep(1000) });
    };
};

proto.callNextStepOn = function(selector, prop, cb) {
    var t = this;
    if (!cb) cb = function() { t.callNextStep() };
    if (!prop) prop = ':visible';
    t.poll( function() {
        return t.$(selector, t.win.document).is(prop)
    }, cb);
};

proto._savePage = function(cb) {
    var t = this;
    if (!t.wikiwyg_started()) {
        return cb.call(t);
    }

    var doit = function() {
        t.$('#st-save-button-link').click();
        t.poll(
            function() { 
                return($('#st-display-mode-container', t.win.document).is(':visible'));
            },
            function() {
                // saving page refresh the iframe.
                // On IE: without doing these it shows:  Can't execute code from a freed script 
                t.win = t.iframe.contentWindow;
                t.doc = t.iframe.contentDocument || t.win.document;
                t.$ = t.win.jQuery;

                return cb.call(t)
            }
        );
    };

    if (jQuery.browser.safari || t.richtextModeIsReady()) {
        doit();
    }
    else {
        t.$('#st-mode-wysiwyg-button').click();
        t.poll(function(){ return t.richtextModeIsReady() }, doit);
    }
};

proto.now = function() {
    if (Date.now) {
        return Date.now();
    }
    return (new Date()).getTime();
}

proto._gensym_serial = 0;

proto.gensym = function() {
    proto._gensym_serial++;
    return location.href.replace(/.*\//, '')
                        .replace(/\..*/, '')
                        .replace(/\W/g, '_')
            + '_' + this.now() + '_' + proto._gensym_serial;
}

})(jQuery);

// XXX Local patch to make diagnostic output render correctly
// Eventually move this back up into Test.Builder

Test.Builder.prototype._setupOutput = function () {
    if (Test.PLATFORM == 'browser') {
        var top = Test.Builder.globalScope;
        var doc = top.document;
        var writer = function (msg) {
            // I'm sure that there must be a more efficient way to do this,
            // but if I store the node in a variable outside of this function
            // and refer to it via the closure, then things don't work right
            // --the order of output can become all screwed up (see
            // buffer.html).  I have no idea why this is.
            var body = doc.body || doc.getElementsByTagName("body")[0];
            var node = doc.getElementById('test_output')
                || doc.getElementById('test');
            if (!node) {
                node = document.createElement('pre');
                node.id = 'test_output';
                body.appendChild(node);
            }

            // This approach is neater, but causes buffering problems when
            // mixed with document.write. See tests/buffer.html.

            if (node.childNodes.length) {
                var span = document.createElement('span');
                span.innerHTML = msg;
                node.appendChild(span);
                return;
            }

            // If there was no text node, add one.
            node.appendChild(doc.createTextNode(msg));
            top.scrollTo(0, body.offsetHeight || body.scrollHeight);
            return;
        };

        this.output(writer);
        this.failureOutput(function (msg) {
            msg = msg
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;');
            writer('<span style="color: red; font-weight: bold">'
                   + msg + '</span>')
        });
        this.todoOutput(writer);
        this.endOutput(writer);

        if (top.alert.apply) {
            this.warnOutput(top.alert, top);
        } else {
            this.warnOutput(function (msg) { top.alert(msg); });
        }

    } else if (Test.PLATFORM == 'director') {
        // Macromedia-Adobe:Director MX 2004 Support
        // XXX Is _player a definitive enough object?
        // There may be an even more explicitly Director object.
        /*global trace */
        this.output(trace);       
        this.failureOutput(trace);
        this.todoOutput(trace);
        this.warnOutput(trace);

    } else if (Test.PLATFORM == 'wsh') {
        // Windows Scripting Host Support
        var printer = function (msg) {
			WScript.StdOut.writeline(msg);
		}
		this.output(printer);
		this.failureOutput(printer);
		this.todoOutput(printer);
		this.warnOutput(printer);

    } else if (Test.PLATFORM == 'interp') {
        // Command-line interpeter.
        var out = function (toOut) { print( toOut.replace(/\n$/, '') ); };
        this.output(out);
        this.failureOutput(out);
        this.todoOutput(out);
        this.warnOutput(out);
	}
    return this;
};
