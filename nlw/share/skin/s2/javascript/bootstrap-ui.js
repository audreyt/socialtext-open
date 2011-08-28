// Pop up a new HTML window
function query_popup(url, width, height, left, top) {
    if (!width) width = 400;
    if (!height) height = 287;
    if (!left) left = 400-width/2;
    if (!top) top = 280-height/2;
    window.open(url, '_blank', 'toolbar=no, location=no, directories=no, status=no, menubar=no, titlebar=no, scrollbars=yes, resizable=yes, width=' + width + ', height=' + height + ', left=' + left + ', top=' + top);
}

if (typeof ST == 'undefined') ST = {}

jQuery(function () {
    if (ST.Watchlist) {
        window.Watchlist = new ST.Watchlist();
        window.Watchlist._loadInterface(
            jQuery('#st-watchlist-indicator').get(0)
        );
        jQuery('.watchlist-list-toggle').each(function() {
            var page_id = this.getAttribute('alt');
            var wl = new ST.Watchlist();
            wl.page_id = page_id;
            wl._loadInterface(this);
        });
    }

    var startup = function() {
        createPageObject();
        if (ST.Attachments) window.Attachments = new ST.Attachments ();
        if (ST.Tags) window.Tags = new ST.Tags ();
        if (ST.TagQueue) window.TagQueue = new ST.TagQueue();
        window.NavBar = new ST.NavBar ();
        ST.hookCssUpload();
    }

    var load_ui = function(cb) {
        var script_url =
            nlw_make_s2_path("/javascript/socialtext-display-ui.js.gz")
            .replace(/(\d+\.\d+\.\d+\.\d+)/, '$1.' + Socialtext.make_time) ;

        var self = this;
        jQuery.getScript(script_url, function() {
            cb.call(self);
        });
    };

    var load_socialcalc = function(cb) {
        if (typeof SocialCalc != 'undefined'
             && SocialCalc.bootstrap_finished)  {
            cb.call(this);
        }

        var script_url =
            nlw_make_plugin_path("/socialcalc/javascript/socialtext-socialcalc.js.gz")
                .replace(/(\d+\.\d+\.\d+\.\d+)/, '$1.' + Socialtext.make_time) ;

        var self = this;
        jQuery.getScript(script_url, function() {
            cb.call(self);
        });
    };

    var bootstrap2 = function(cb) {
        if (Socialtext.bootstrap_ui_finished == true)  {
            cb.call(this);
            return;
        }

        jQuery(window).trigger("bootstrapping");

        load_ui.call(this, function() {
            startup();
            if (Socialtext.page_type == 'spreadsheet') {
                load_socialcalc.call(this, function() {
                    cb.call(this);
                    jQuery(window).trigger("bootstrapped");
                });
            }
            else {
                window.setup_wikiwyg();
                cb.call(this);
                jQuery(window).trigger("bootstrapped");
            }
        });
    };

    var bootstrap = function(cb) {
        return function() { bootstrap2.call(this, cb); };
    };

    jQuery("#st-page-boxes-toggle-link,#st-attachments-uploadbutton,#st-attachments-managebutton,#st-tags-addlink")
    .addClass("bootstrapper")
    .one("click", bootstrap(function() {
        jQuery(this).click();
    }));

    var start_editor = function() {
        // This setTimeout is required to get around of some simple mode bug in IE and FF.
        setTimeout(function() {
            if (Socialtext.page_type == 'spreadsheet' &&
                Socialtext.wikiwyg_variables.hub.current_workspace
                    .enable_spreadsheet
            ) {
                Socialtext.start_spreadsheet_editor();
                return false;
            }

            window.wikiwyg.start_nlw_wikiwyg();
            // for "Upload files" and "Add tags" buttons
            jQuery( "#st-edit-mode-uploadbutton" ).unbind().click(function() {
                window.Attachments._display_attach_interface();
                return false;
            });
        }, 0);
    };

    jQuery("#st-edit-button-link,#st-edit-actions-below-fold-edit")
        .addClass("bootstrapper")
        .one("click", bootstrap(start_editor));

    jQuery(window).bind("bootstrapping", function() {
        jQuery("#bootstrap-loader").show();
    });

    jQuery(window).bind("bootstrapped", function() {
        jQuery("#bootstrap-loader").fadeOut("slow");
    })
    .bind("reload", function() {
        jQuery(".bootstrapper").hide();
    });

    if (Socialtext.double_click_to_edit) {
        jQuery("#st-page-content").one("dblclick", bootstrap(start_editor))
    }

    window.Tags = {
        deleteTag: function(name) {
           bootstrap(function() { Tags.deleteTag(name); })();
        }
    };

    if (Socialtext.new_page ||
        Socialtext.start_in_edit_mode ||
        location.hash.toLowerCase() == '#edit' ) {
        setTimeout(function() {
            jQuery("#st-edit-button-link").trigger("click");
        }, 500);
    }

    jQuery("#st-search-term").one("click", function() {
        this.value = "";
    }).one("focus", function() {
        this.value = "";
    });

    jQuery("#st-search-submit").one("click", function() {
        jQuery("#st-search-form").submit();
    });

    window.confirm_delete = function (pageid) {
        bootstrap(function() {
            if (confirm(loc('Are you sure you want to delete this page?'))) {
                location = 'index.cgi?action=delete_page;page_name=' + pageid;
            }
        })();
        return false;
    }
});

