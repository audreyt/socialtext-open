/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements. See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership. The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License. You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

var gadgets = gadgets || {};

gadgets.container = (function() {

var container = {}
container.gadgets_ = {};
container.parentUrl_ = 'http://' + document.location.host;
container.country_ = 'ALL';
container.language_ = 'ALL';
container.view_ = 'default';
container.nocache_ = 1;
container.base_url = location.pathname;
container.onSetPreferences = $.noop;
container.pendingChanges = {};
container.template = 'widget/element.tt2';
container.viewer = {};

// signed max int
container.maxheight_ = 0x7FFFFFFF;

container.setup = function(options) {
    if (options) $.extend(this, options);
    this.updateIframeNames();
    this.registerServices();
    this.fixGadgetTitles();
    this.showNotice(false);
}

container.updateIframeNames = function() {
    // Set window names to be the frame number
    var self = this;
    self.nodes_ = {};
    var relay = this.base_url + "/nlw/plugin/widgets/rpc_relay.html";
    $.each(window.frames, function(i) {
        var name;
        try { name = this.name } // This will fail cross domain
        catch(e) { return }
        var $frame = $('.widget iframe.widgetWindow[name='+name+']');
        if (!$frame.size()) return;
        frames[name] = this;
        gadgets.rpc.setRelayUrl(name, relay);
        self.nodes_[name] = $frame.parents('.widget:first');
    });
};

container.fixGadgetTitles = function () {
    /* This function dynamically calculates size of widget titles. */
    var fn = function () {
        try {
            jQuery('.widgetContent').each(function() {
                var $widget = jQuery(this).parents('.widget');
                var size = $widget.width() - 100;
                // Admin mode adds an extra icon we need to adjust for
                if ($widget.find('.fix').size()) size -=15;
                jQuery('.widgetHeaderTitle', $widget).width(size);
            });
        } catch (e) {}
    };
    jQuery(fn);
    jQuery(window).bind('resize', fn);
}

container.registerServices = function () {
    var self = this;
    var services = [
        'resize_iframe', 'set_pref', 'set_title', 'requestNavigateTo'
    ];

    $.each(services, function(i, handler) {
        gadgets.rpc.register(handler, function (){
            self.rpc = this;
            return self[handler].apply(self, arguments)
        });
    });

    this.initializePubsub();
}

container.initializePubsub = function () {
    if (typeof(gadgets.pubsubrouter) != 'undefined') {
        var i=1;
        gadgets.pubsubrouter.init(function() {return i++});
    }
};

container.widgetNode = function() {
    var self = this;
    var from = this.rpc.f;
    if (!from) {
        throw new Error("RPC destination is undefined");
    }
    var $widgetNode = this.nodes_[from];
    if (!$widgetNode || !$widgetNode.size()) {
        throw new Error("Can't find widget " + from);
    }
    return $widgetNode;
}

container.resize_iframe = function(height) {
    if (height > gadgets.container.maxheight_) {
        height = gadgets.container.maxheight_;
    }
    // No animation here as it makes focus lost inside iframe: {bz: 1756}
    $('iframe', this.widgetNode()).height(height).triggerHandler('resize');
};

container.set_title = function(title) {
    if (title.length >= 40 ) {
      title = title.substr(0,37); // same as template
      title = title + ' ...';
    }
    $('.widgetTitle h1', this.widgetNode()).html(
        title.replace(/&/g, '&amp;').replace(/</g, '&lt;')
    );
};

container._getParamsFromForm = function(id) {
    var $form = $('#gadget-' + id + '-preferences form');

    var urlParams = {};
    $.each($form.serializeArray(), function(i, input) {
        if (typeof input.value == 'boolean') {
            urlParams['up_' + input.name] = input.value ? '1' : '';
        }
        else {
            urlParams['up_' + input.name] = input.value;
        }
    });

    // Explicitly set false booleans
    $form.find('input[type=checkbox]:not(:checked)').each(function() {
        urlParams[$(this).attr('name')] = 'false';
    });

    return urlParams;
};

container.widgetUrl = function(id) {
    var self = this;
    var $iframe = $('#gadget-' + id + ' iframe');
    var win = $iframe.get(0).contentWindow;
    
    try {
        var urlParams = win.gadgets.util.getUrlParameters();
    } catch (e) {
        // Must be a x-domain iframe. just return its url.
        return $iframe[0].src;
    }

    $.extend(urlParams, self._getParamsFromForm(id));
    
    // Set a time variable to get around caching
    urlParams['time'] = Math.round(new Date().getTime() / 1000);

    var url = $.param(urlParams);

    return String(win.location.href).replace(
        /^(.*?\?).*(\#.*)?/, '$1' + url + '$2'
    );
};

container.setPreferences = function(instance_id, prefHash, callback) {
    this.onSetPreferences(prefHash);

    if (this._in_edit_mode || this.view == 'page') {
        // Strip off up_ from preference names when we aren't passing the
        // preference as a cgi parameter
        var prefs = {};
        $.each(prefHash, function(key, val) {
            prefs[ key.replace(/^up_/, '') ] = val;
        });
        if (!this.pendingChanges[instance_id])
            this.pendingChanges[instance_id] = {};
        this.pendingChanges[instance_id].preferences = prefs;

        callback();
    }
    else {
        // Update the form to match our new preferences
        $.each(prefHash, function(key, val) {
            jQuery('gadget-' + instance_id + ' input[name='+key+']').val(val);
        });

        var base = this.base_url + '/gadgets/' + instance_id;

        jQuery.ajax({
            type: 'PUT',
            url:  base + '/prefs',
            data: $.param(prefHash),
            complete: callback
        });
    }
};

container.setupPreferenceLookaheads = function($node) {
    if (!$.fn.autocomplete) { return }

    /* Add handlers and stuff to settings sections */
    $node.find('.page_setting').each(function() {
        var form = this.form;
        $(this).lookahead({
            url: function () {
                var ws = $('.workspace_setting', form).val() ||
                         Socialtext.wiki_id;
                return '/data/workspaces/' + ws + '/pages';
            },
            params: { minimal_pages: 1 },
            linkText: function (i) { return i.name },
            onError: {
                404: function () {
                    var ws = $('.workspace_setting', form).val() ||
                             Socialtext.wiki_id;
                    return(
                        '<span class="st-suggestion-warning">'
                        + loc('error.no-wiki-on-server=wiki', ws)
                        + '</span>'
                    );
                }
            }
        });
    });

    $node.find('.spreadsheet_setting').each(function() {
        var form = this.form;
        $(this).lookahead({
            url: function () {
                var ws = $('.workspace_setting', form).val() ||
                         Socialtext.wiki_id;
                return '/data/workspaces/' + ws + '/pages?type=spreadsheet';
            },
            params: { minimal_pages: 1 },
            linkText: function (i) { return i.name },
            onError: {
                404: function () {
                    var ws = $('.workspace_setting', form).val() ||
                             Socialtext.wiki_id;
                    return(
                        '<span class="st-suggestion-warning">'
                        + loc('error.no-wiki-on-server=wiki', ws)
                        + '</span>'
                    );
                }
            }
        });
    });

    $node.find('.workspace_setting').each(function() {
        var $workspace = $(this);
        var $account = $('.account_setting', this.form);
        if ($account.size()) {
            $account.change(function() {
                $('option', $workspace).each(function(_,opt) {
                    var account = $(opt).attr('account')
                    if (!account || account == $account.val()) {
                        $(opt).removeClass('hidden').removeAttr('disabled');
                    }
                    else {
                        $(opt).addClass('hidden').attr('disabled', 'disabled');
                    }
                });
                if ($('option:selected', $workspace).hasClass('hidden')) {
                    $workspace.val(
                        $workspace.find("option:not(:disabled):first").val()
                    );
                }
            }).change();
        }
    });
}

/**
 * Sets one or more user preferences
 * @param {String} editToken
 * @param {String} name Name of user preference
 * @param {String} value Value of user preference
 * More names and values may follow
 */
container.set_pref = function(authToken) {
    var self = this;

    var instance_id = self.widgetNode().find('input[name=instance_id]').val();
    var prefHash = self._getParamsFromForm(instance_id);

    for (var i = 1, j = arguments.length; i < j; i += 2) {
        prefHash[ 'up_' + arguments[i] ] = arguments[i + 1];
    }

    var win = self.widgetNode().find('iframe').get(0).contentWindow;
    self.setPreferences(instance_id, prefHash, function() {
        var url = self.widgetUrl(instance_id);
        $(win).data('new_iframe_src', url);
    });
};

// Save called from preference form
container.save = function (instance_id, gadget_id, form) {
    var self = this;
    var prefHash = self._getParamsFromForm(instance_id);

    $('#gadget-'+instance_id+'-preferences').hide();
    self.setPreferences(instance_id, prefHash, function() {
        self.refreshWidget(instance_id, gadget_id);
    });
};

container.allParams = function(instance_id, additional_params) {
    var params = {};
    $.each(this.env||{}, function(k, v) { params['env_'+k] = v });
    params.instance_id = instance_id;
    params.view = this.view;
    return $.extend(params, additional_params);
};

container.refreshWidget = function(instance_id, gadget_id) {
    var self = this;
    var $li = jQuery('#gadget-' + instance_id);
    var $iframe = $li.find('#' + instance_id + '-iframe');
    if ($iframe.size()) {
        var url = this.widgetUrl(instance_id);

        // Show the widget again once it has loaded.
        $iframe.attr('src', url);
        self.hideSetup(instance_id);
    }
    else {
        // Show the widget again once it has loaded.
        var url = '/data/gadgets/' + gadget_id;
        $.ajax({
            url: url,
            type: 'get',
            data: self.allParams(
                instance_id, self._getParamsFromForm(instance_id)
            ),
            dataType: 'json',
            success: function(data) {
                $li.find("#gadget-" + instance_id + "-content").children(".inlineWidget").html(data.content||data);
                self.hideSetup(instance_id);
            }
        });
    }
};

/**
 * Navigates the page to a new url based on a gadgets requested view and
 * parameters.
 */
container.requestNavigateTo = function(view, opt_params) {
    var self = this;
    if (self._suspendWarningForRequestNavigateTo) return;
    self._suspendWarningForRequestNavigateTo = true;
    alert(loc('error.feature-not-supported-in-dashboard'));
    setTimeout(function(){
        self._suspendWarningForRequestNavigateTo = false;
    }, 1000);


    /*
    var url = this.getUrlForView(view);

    if (opt_params) {
        var paramStr = JSON.stringify(opt_params);
        if (paramStr.length > 0) {
            url += '&appParams=' + encodeURIComponent(paramStr);
        }
    }

    if (url && document.location.href.indexOf(url) == -1) {
        document.location.href = url;
    }
    */
};

container.minimize = function (id, isInitialCall) {
    var $setup = $('#gadget-'+id+'-preferences');
    var $content = $('#gadget-'+id+'-content')
    var $widget = $('#gadget-'+id+' .widget');

    if ($widget.hasClass('minimized')) {
        function _adjustHeight () {
            var iframe = jQuery('#'+id+'-iframe');
            if (iframe.size()) {
                var gadgets = iframe.get(0).contentWindow.gadgets;
                if (gadgets) {
                    if (iframe.height() == 0) {
                        /* This is needed for adjustHeight() to work in IE */
                        iframe.height(1);
                    }
                    iframe.get(0).contentWindow.gadgets.window.adjustHeight();
                }
            }
        }

        if (this.setup_visible)
            $setup.fadeIn('slow', _adjustHeight);
        else
            $content.fadeIn('slow', _adjustHeight);

        $widget.removeClass('minimized');
    }
    else {
        this.setup_visible = $setup.is(':visible') ? true : false;
        $setup.fadeOut('slow');
        $content.fadeOut('slow');

        $widget.addClass('minimized');
    }

    if (!isInitialCall) {
        this.updateLayout();
    }
};

container.hideSetup = function (id) {
    $('#gadget-'+id+'-preferences').hide();
    $('#gadget-'+id+'-content').show();
}

container.toggleSetup = function (id) {
    if ($('#gadget-' + id + ' .widget').hasClass('minimized')) {
        /* Restore from minimization if it's currently minimized */
        this.minimize(id);

        /* Allow 600ms for fadeIn() in minimize() above to complete */
        var self = this;
        setTimeout(function(){ self.toggleSetup(id) }, 600);

        return;
    }

    $('#gadget-'+id+'-preferences').toggle();
    $('#gadget-'+id+'-content').toggle();
    return;
}

function _getLayout () {
    var cols = [];
    jQuery('.widgetColumn').each(function(col) {
        cols[col] = [];
        jQuery('.widget:not(.waflWidget)', this).each(function(row, widget){
            var $widget = $(widget);
            if ($widget.parents('.wiki').length) { return; }

            var instance_id = $widget.find('input[name=instance_id]').val();
            var gadget = {
                instance_id: instance_id,
                gadget_id: $widget.find('input[name=gadget_id]').val(),
                minimized: $widget.hasClass('minimized'),
                push: $widget.find('.push-widget').is(':checked')
            };

            // also add any pending changes to the gadget
            var pending = container.pendingChanges[instance_id]
            if (pending) $.extend(gadget, pending);

            cols[col].push(gadget);
        });
    });
    return cols;
}

function _setLayout (layout) {
    $('.gadgetElement').addClass('deletedGadget');
    $.each(layout, function(col, gadgets) {
        $.each(gadgets, function(row, gadget) {
            var config = container.pendingChanges[gadget.gadget_instance_id];

            var $gadget = $('#gadget-' + gadget.instance_id);
            if (!$gadget.size()) {
                container.add_gadget({
                    instance_id: gadget.instance_id,
                    col: col,
                    row: row
                });
            }
            else {
                $gadget.removeClass('deletedGadget');
                if (!row) {
                    // first widget in a column
                    $('#col' + col).prepend($gadget);
                }
                else {
                    $gadget.insertAfter(
                        '#gadget-' + gadgets[row-1].instance_id
                    );
                }
            }
        });
    });

    $('.deletedGadget').remove();
}

// This is called when widgets are moved, etc
container.updateLayout = function () {
    var self = this;
    // Don't update the layout when we are editing the layout
    if (self._in_edit_mode) return;
    self.saveLayout(self.base_url);
};

container.add_gadget = function(config) {
    var self = this;

    if (typeof(config.col) == 'undefined') throw new Error('col is required');
    if (typeof(config.row) == 'undefined') throw new Error('row is required');

    // fake id (to buy booze and cigarettes.)
    var instance_id = (new Date).getTime();
    config.install = true; // install this as a new widget

    if (self._in_edit_mode) {
        var params = self.allParams(instance_id);
        var url = '/data/gadgets/' + config.gadget_id + '?' + $.param(params);
        $.getJSON(url, function(data) {
            self.pendingChanges[instance_id] = config;
            var $gadget = container.renderGadget($.extend({}, config, data));
            self.makeEditable($gadget.find('.widget'));
        });
    }
    else {
        $.ajax({
            url:  self.base_url + '/gadgets',
            type: 'POST',
            data: gadgets.json.stringify(config),
            contentType: 'application/json',
            dataType: 'json',
            error: function(xhr, err, errorText) {
                socialtext.dialog.showError(xhr.responseText);
            },
            success: function(data) {
                container.renderGadget(data);
            }
        });
    }
};

container.renderGadget = function(data, template_vars, node) {
    var self = this;
    var before;
    if (!node) {
        node = $('.widgetColumn').get(data.col);
        before = $(node).find('.widget').get(data.row);
    }

    var accounts = Socialtext.accounts;
    var workspaces = Socialtext.workspaces;
    if (self.view == 'group') {
        // Limit accounts and workspaces to the ones accessible by this group
        var account_ids = self.env.account_ids.split(',');
        accounts = $.grep(accounts, function(acc) {
            return $.inArray(acc.account_id, account_ids) != -1;
        });
        var workspace_ids = self.env.workspace_ids.split(',');
        workspaces = $.grep(workspaces, function(wksp) {
            return $.inArray(wksp.id, workspace_ids) != -1;
        });
    }

    // classes
    data.classes = {};
    $.each( (data['class'] || '').split(' '), function(_,c) {
        data.classes[c] = true;
    });

    // Render the widget
    var html = Jemplate.process(self.template, $.extend({
        view: self.view,
        share: nlw_make_plugin_path('/widgets'),
        gadget: data,
        num: $('.widget').size(),
        workspaces: workspaces,
        accounts: accounts,
        loc: loc,
        editing: self._in_edit_mode || self.live_edit,
        pushable: self.type == 'account_dashboard' && !data.parent_instance_id,
        lockable: self.type == 'account_dashboard'
    }, template_vars));

    // insert the widget at col/row
    var $gadget = $(html);
    if (before) {
        $gadget.insertBefore(before);
    }
    else {
        $gadget.appendTo(node);
    }

    self.updateIframeNames();
    self.fixGadgetTitles();
    self.setupPreferenceLookaheads($gadget.find('.preferences'));

    return $gadget;
};

container.remove = function (id) {
    var self = this;
    jQuery('#gadget-'+id).fadeOut('slow',function() {
        jQuery('#gadget-'+id).remove();
        if (!self._in_edit_mode) {
            jQuery.ajax({
                type: 'DELETE',
                url:  self.base_url + '/gadgets/' + id
            });
        }
    });
}

// "float" gadget below any fixed gadgets but above non-fixed
container._float_fixed_gadget = function (id) {
    var $li = jQuery('#gadget-'+id);
    var $draggable = $li.siblings('.draggable:first');
    
    if ($draggable.length) {
        var $copy = $li.clone();
        $copy.insertBefore($draggable);
        $li.remove();
    }
    else {
        var $copy = $li.clone();
        $copy.appendTo($li.parent())
        $li.remove();
    }
    this.updateLayout();
}

container.fix = function (instance_id) {
    var self = this;
    var $li = jQuery('#gadget-'+instance_id);
    var $widget = $li.find('.widget');
    var fixed = $li.hasClass('fixed');
    var $button = $li.find('a.fix');

    if (!this._in_edit_mode) throw new Error("Must be in edit mode");

    if (!this.pendingChanges[instance_id])
        this.pendingChanges[instance_id] = {};
    this.pendingChanges[instance_id].fixed = !fixed;

    if (fixed) {
        jQuery('#gadget-'+instance_id+' img.icon').show();
        $li.addClass('draggable').removeClass('fixed');
        $button.addClass('unfixed').removeClass('fixed');
    }
    else {
        jQuery('#gadget-'+instance_id+' img.icon').hide();
        $li.addClass('fixed').removeClass('draggable');
        $button.addClass('fixed').removeClass('unfixed');
    }
    self._float_fixed_gadget(instance_id);
};

container.makeEditable = function($widget) {
    if (!$widget.hasClass('cannot_move')) {
        $widget.find('img.icon, .widgetHeaderButtons').show();
        $widget.find('.minimize').hide();
        $widget.parent().addClass('draggable').removeClass('fixed');
    }
};

container.makeUneditable = function($widget) {
    $widget.find('img.icon, .widgetHeaderButtons').hide();
    $widget.parent().addClass('fixed').removeClass('draggable');
    $widget.find('.preferences').hide();
    $widget.find('.gadgetContent').show();
};

container.showNotice = function(editing) {
    if (!this.notice_template) return;

    var html = Jemplate.process(this.notice_template, {
        loc: loc,
        container: this,
        st: st,
        editing: editing
    });
    if (html.match(/\S/)) {
        $('.notice').html(html).show();
    }
    else {
        $('.notice').hide();
    }
}

container.enterEditMode = function() {
    var self = this;
    self._in_edit_mode = true;

    self.showNotice(true);

    // Make widgets editable
    $('.widgetHeader').find('.settings, .fix, .close').show();
    $('.widgetColumn')
        .children('.widget:not(.cannot_move)')
        .removeClass('fixed').addClass('draggable');

    // Show edit mode buttons
    $('#globalNav .viewMode').hide();
    $('#globalNav .editMode').show();
    
    //notice loc('widgets.in-layout-mode-click-save-or-cancel')
};

container.leaveEditMode = function() {
    var self = this;

    self.showNotice(false);

    // Make widgets un-editable
    $('.widgetHeader').find('.settings, .fix, .close').hide();
    $('.widgetColumn').children().removeClass('draggable').addClass('fixed');
    
    // Show view mode buttons
    $('#globalNav .editMode').hide();
    $('#globalNav .viewMode').show();

    // Get rid of push checkboxes
    $('.widgetColumn .widgetPush').remove();

    self._in_edit_mode = false;
};

container.saveAdminLayout = function(options) {
    this.saveLayout(this.base_url, options);
}

container.loadDefaults = function(callback) {
    this.loadLayout(this.base_url + '/defaults', callback, true);
}

container.loadLayout = function(url, callback, defaults) {
    var self = this;
    $.getJSON(url, function(gadgets) {
        $('.widget').remove();
        $.each(gadgets, function(_, g) {
            var prefs = {};
            $.each(g.preferences, function(_, pref) {
                prefs[pref.name] = pref.value;
            });
            self.pendingChanges[g.instance_id] = {
                'class': g['class'] || '',
                'fixed': g['fixed'] || false,
                preferences: prefs,
                install: defaults // install new versions if these are defaults
            };
            var $gadget = self.renderGadget(g);
            self.makeEditable($gadget.find('.widget'));
        });
        if ($.isFunction(callback)) callback();
    });
}

container.saveLayout = function(url, options) {
    var self = this;

    if (!url) throw new Error('url required');
    options = $.extend({
        gadgets: _getLayout(),
        success: $.noop,
        error: $.noop
    }, options);

    jQuery.ajax({
        type: 'PUT',
        contentType: 'application/json',
        url:  url,
        data: gadgets.json.stringify(options),
        success: options.success,
        error: options.error
    });
};

return container;

})();

jQuery(function() {
    /**
     * Container notice - fetch and display notices from a cookie
     */
    var notice = Cookie.get('notice');
    if (notice) {
        jQuery('.notice').html(notice).show();
        Cookie.del('notice', '/');
    }
});

// Add some global rpc handlers
var dialog;

gadgets.rpc.register('showDialog', function(vars) {
    dialog = socialtext.dialog.show(vars.name, vars);
    return dialog;
});

gadgets.rpc.register('hideLightbox', function() {
    if (dialog) dialog.close();
});
gadgets.rpc.register('pauseLightbox', function() {
    if (dialog) dialog.disable();
});
gadgets.rpc.register('resumeLightbox', function() {
    if (dialog) dialog.enable();
});
