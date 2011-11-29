(function($) {

if (typeof(Socialtext) != 'undefined')
    throw new Error ('Socialtext.js must be loaded first!');

Socialtext = function(vars) {
    $.extend(this, vars);

    // TODO this.viewer = new Socialtext.User(this.viewer);
    if (this.workspace)
        this.workspace = new Socialtext.Workspace(this.workspace);
    if (this.page)
        this.page = new Socialtext.Page(this.page);
}

Socialtext.prototype = {
    info: {
        focus_field: {
            'preferences_settings': 'form > div > input:eq(0)',
            'users_invitation': 'textarea[name="users_new_ids"]',
            'users_settings': 'input[name="first_name"]',
            'weblogs_create': 'dl.form > dd > input:eq(0)',
            'workspaces_create': 'dl.form > dd > input:eq(0)',
            'workspaces_settings_appearance': 'dl.form > dd > input:eq(0)'
        }
    },

    UA_is_MacOSX: navigator.userAgent.match(/Mac OS X/),
    UA_is_Safari: ($.browser.safari && parseInt($.browser.version) < 500),
    UA_is_Selenium: (function(){ var UA_is_Selenium = false; try { UA_is_Selenium = (
        (typeof seleniumAlert != 'undefined' && seleniumAlert)
        || (typeof Selenium != 'undefined' && Selenium)
        || ((typeof window.top != 'undefined' && window.top)
            && (window.top.selenium_myiframe
                || window.top.seleniumLoggingFrame)
        || ((typeof window.top.opener != 'undefined' && window.top.opener)
            && (window.top.opener.selenium_myiframe
                || window.top.opener.seleniumLoggingFrame))
        )
    ); } catch (e) {}; return UA_is_Selenium; })(),

    // For some templates
    loc: loc,

    // Paths
    nlw_make_path: function(path) {
      return this.dev_mode
          ? path.replace(/(\d+\.\d+\.\d+\.\d+)/,'$1.'+(new Date).getTime())
          : path;
    },
    nlw_make_static_path: function(rest) {
        return this.nlw_make_path(this.static_path + rest);
    },
    nlw_make_js_path: function(file) {
        return this.nlw_make_path(['/js', this.version, file].join('/'));
    },
    nlw_make_plugin_path: function(rest) {
        return this.nlw_make_path(
            this.static_path.replace(/static/, 'nlw/plugin') + rest
        );
    },
    makeWatchHandler: function(pageId) {
        return function(){
            var self = this;
            if ($(this).hasClass('on')) {
                $.get(
                    location.pathname + '?action=remove_from_watchlist'+
                    ';page=' + pageId +
                    ';_=' + (new Date()).getTime(),
                    function () {
                        var text = loc("do.watch");
                        $(self).attr('title', text).text(text);
                        $(self).removeClass('on');
                    }
                );
            }
            else {
                $.get(
                    location.pathname + '?action=add_to_watchlist'+
                    ';page=' + pageId +
                    ';_=' + (new Date()).getTime(),
                    function () {
                        var text = loc('watch.stop');
                        $(self).attr('title', text).text(text);
                        $(self).addClass('on');
                    }
                );
            }
            return false;
        };
    },

    /**
     * Recreate the old Socialtext.var_name API that will be replaced with the
     * st API
     */
    setupLegacy: function() {
        $.extend(true, Socialtext, {
            version: this.version,
            accept_encoding: this.accept_encoding,
            loc_lang: this.loc_lang,
            dev_mode: this.dev_mode,
            template_name: this.template_name,

            // TODO
            start_in_edit_mode: false,
            double_click_to_edit: false, // if wikiwyg_double

            // Viewer
            real_user_id:  this.viewer.user_id,
            userid:        this.viewer.username,
            email_address: this.viewer.email_address,
            username:      this.viewer.guess_real_name,
            workspaces:    this.viewer.workspaces,
            accounts:      this.viewer.accounts,

            // Workspace
            wiki_id: this.workspace.name,
            wiki_title: this.workspace.title,
            current_workspace_account_id: this.workspace.account_id,
            comment_form_window_height:
                this.workspace.comment_form_window_height,

            // Page
            new_page:   this.page ? this.page.is_new : false,
            page_id:    this.page ? this.page.id : '',
            page_title: this.page ? this.page.title : '',
            page_type:  this.page ? this.page.type : '',
            page_size:  this.page ? this.page.size : 0,

            // Revision
            revision_id : this.page ? this.page.revision_id : 0
        });
    }
};

// Legacy stuff that we still need, but maybe could be improved
trim = function(value) {
    var ltrim = /\s*((\s*\S+)*)/;
    var rtrim = /((\s*\S+)*)\s*/;
    return value.replace(rtrim, "$1").replace(ltrim, "$1");
};
nlw_name_to_id = function(name) {
    if (name == '') return '';
    return encodeURI(Socialtext.Page.title_to_page_id(name));
};
is_reserved_pagename = function(pagename) {
    if (pagename && pagename.length > 0) {
        var name = nlw_name_to_id(trim(pagename));
        var untitled = nlw_name_to_id(loc('page.untitled'));
        var untitledspreadsheet = nlw_name_to_id(loc('sheet.untitled'));
        return(
            (name == untitled) || (name == untitledspreadsheet)
            || (name == 'untitled_page') || (name == 'untitled_spreadsheet')
        );
    }
    else {
        return false;
    }
};

// Deprecated functions
nlw_make_s2_path = function (rest) {
    throw new Error('deprecated call to nlw_make_s2_path!');
}
nlw_make_s3_path = function (rest) {
    throw new Error('deprecated call to nlw_make_s3_path!');
}
nlw_make_skin_path = function (rest) {
    throw new Error('deprecated call to nlw_make_skin_path!');
}

// Legacy path functions
nlw_make_static_path = function(rest) { return st.nlw_make_static_path(rest) }
nlw_make_js_path = function(file) { return st.nlw_make_js_path(file) }
nlw_make_plugin_path = function(rest) { return st.nlw_make_plugin_path(rest) }

// Handy stuff
$('input.initial').live('click', function() {
  $(this).removeClass('initial').val('');
});
$('input.initial').live('keydown', function() {
  $(this).removeClass('initial').val('');
});

if (Socialtext.prototype.UA_is_Selenium) {
    $(function() {
        // Show <body> and maximize the window if we're running under Selenium
        try { 
            top.window.moveTo(0,0);
            top.window.resizeTo(screen.availWidth, screen.availHeight);
            document.body.style.visibility = 'visible';
        } catch (e) {};
    });
}

})(jQuery);
