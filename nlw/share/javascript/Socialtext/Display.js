(function($) {

function hideSideboxes() {
    var $container = $('#st-display-mode-container')
    $container.removeClass($container.data('expanded'));
    $container.addClass($container.data('collapsed'));
    $('#st-display-mode-widgets').hide();
    $('#st-page-boxes-show-link').show();
    $('#st-page-boxes-hide-link').hide();
}

function showSideboxes() {
    var $container = $('#st-display-mode-container')
    $container.removeClass($container.data('collapsed'));
    $container.addClass($container.data('expanded'));
    $('#st-page-boxes-show-link').hide();
    $('#st-page-boxes-hide-link').show();
    $('#st-display-mode-widgets').show();
}

Socialtext.prototype.setupPageHandlers = function() {
    /**
     * Tools Menu
     */
    // collapse
    $('.tools .expanded').live('click', function() {
        $(this).hide();
        $(this).siblings('.subtools').hide();
        $(this).siblings('.collapsed').show();
        return false;
    });
    // expand
    $('.tools .collapsed').live('click', function() {
        $(this).hide();
        $(this).siblings('.subtools').show();
        $(this).siblings('.expanded').show();
        return false;
    });

    // Show/Hide
    var $container = $('#st-display-mode-container')
    $('#st-page-boxes-hide-link').click(function() {
        hideSideboxes();
        Cookie.set('sideboxes', 'hide');
        return false;
    });
    $('#st-page-boxes-show-link').click(function() {
        showSideboxes();
        Cookie.set('sideboxes', 'show');
        return false;
    });

    // Watch
    $('#st-watchlist-indicator a').click(function() {
        var $link = $(this);
        if ($link.data('watching')) {
            st.page.unwatch(function() {
                $link.attr('title', loc("do.watch")).text(loc('do.watch'));
                $link.data('watching', 0);
            });
        }
        else {
            st.page.watch(function() {
                $link.attr('title', loc("watch.stop")).text(loc('watch.stop'));
                $link.data('watching', 1);
            });
        }
        return false;
    });

    // Share This
    $("#st-signalthis-indicator").click(function() {
        st.dialog.show('activities-signalthis');
    });

    // Email
    $('#st-pagetools-email a').click(function() {
        st.dialog.show('page-email');
        return false;
    });

    // Duplicate
    $('#st-pagetools-duplicate a').click(function() {
        st.dialog.show('page-duplicate');
        return false;
    });

    // Rename
    $('#st-pagetools-rename a').click(function() {
        st.dialog.show('page-rename');
        return false;
    });

    // Copy
    $('#st-pagetools-copy a').click(function() {
        st.dialog.show('page-copy');
        return false;
    });

    // Delete
    $('#st-pagetools-delete a').click(function() {
        st.dialog.show('page-delete');
        return false;
    });

    /**
     * Tags
     */
    st.page.renderTags();

    $('#st-tags-addlink').button().click(function() {
        $(this).hide();
        $('#st-tags-form').show();
        var focused = false;
        $('#st-tags-field').val('').focus().unbind('focus').focus(function() {
            focused = true;
        });
        $('#st-tags-field').unbind('blur').blur(function () {
            focused = false;
            setTimeout(function () {
                if (!focused) {
                    $('#st-tags-field').autocomplete('close');
                    $('#st-tags-form').hide();
                    $('#st-tags-addlink').show();
                }
            }, 500);
        })
    });

    $('#st-tags-plusbutton-link')
        .button({ label: '+' })
        .click(function() { $('#st-tags-form').submit() });

    $('#st-tags-form')
        .bind('submit', function () {
            var tag = $('#st-tags-field').val();
            st.page.addTag(tag);
            return false;
        });
    $('#st-tags-plusbutton-link').click(function() {
        $('#st-tags-form').submit();
    });
    $('#st-tags-field')
        .lookahead({
            url: '/data/workspaces/' + st.workspace.name + '/tags',
            params: {
                order: 'weighted',
                exclude_from: st.page.id
            },
            linkText: function (i) {
                return i.name
            },
            onAccept: function (val) {
                st.page.addTag(val);
            }
        });

    /**
     * Attachments
     */
    st.attachments.renderAttachments();

    $('#st-attachments-uploadbutton').button().click(function () {
        socialtext.dialog.show('attachments-upload');
        return false;
    });

    // HTML5 Drag and drop of files from desktop
    $('#dropbox').createUploadDropArea({ url: st.page.uri() + '/attachments' });

    /**
     * Edit
     */
    $('#st-edit-button-link').button().click(function() {
        var $button = $(this);
        $('#content').uiDisable({
            'height': '20px',
            'top':
                - $('#content').offset().top // Move to the body top
                + $(window).scrollTop()      // top of the window
                + $(window).height() / 2     // middle of the window
                - 10                         // half the height back
        });
        if (st.page.type == 'spreadsheet') {
            $.getScript(st.nlw_make_js_path('socialtext-socialcalc.jgz'), function() {
                Socialtext.start_spreadsheet_editor();
                $('#content').uiEnable();
            });
            return false;
        }

        $.getScript(st.nlw_make_js_path('socialtext-ckeditor.jgz'), function() {
            Socialtext.start_xhtml_editor();
            $('#content').uiEnable();
        });
        return false;
    });

    if (Number(st.double_click_to_edit)) {
        jQuery("#st-page-content").one("dblclick", function() {
            jQuery("#st-edit-button-link").click();
        });
    }

    if (st.page.is_new
        && st.page.title != loc("page.untitled")
        && st.page.title != loc("sheet.untitled")
        && !location.href.toString().match(/action=display;/)
        && !/^#draft-\d+$/.test(location.hash)
    ) {
        if ($('#st-edit-button-link').length) {
            st.dialog.show('create-content', { incipient_title: st.page.title });
        }
    }
    else if (st.page.is_new || st.start_in_edit_mode
            || location.hash.toLowerCase() == '#edit') {
        setTimeout(function() {
            $("#st-edit-button-link").click();
        }, 500);
    }

    /**
     * Comments
     *
     * I'm just going to get this to work because the plan is to get rid of
     * it.
     */
    $("#st-comment-button a").click(function () {
        if ($('div.commentWrapper').length) {
            st.page._currentGuiEdit.scrollTo();
            return;
        }

        $.ajaxSettings.cache = true;
        $.ajax({
            url: st.nlw_make_js_path('socialtext-comments.jgz'),
            dataType: 'script',
            success: function() {
                var ge = new GuiEdit({
                    id: 'st-comment-interface',
                    oncomplete: function () {
                        st.page.refreshPageContent();
                    },
                    onclose: function () {
                    }
                });
                st.page._currentGuiEdit = ge;
                ge.show();
            },
            error: function(jqXHR, textStatus, errorThrown) {
                throw errorThrown;
            }
        });
        $.ajaxSettings.cache = false;

        return false;
    });
};

Socialtext.prototype.setupBlogHandlers = function() {
    $(".weblog_comment").click(function () {
        var page = new Socialtext.Page({
            id: this.id.replace(/^comment_/,'')
        });

        $.ajaxSettings.cache = true;
        $.ajax({
            url: st.nlw_make_js_path('socialtext-comments.jgz'),
            dataType: 'script',
            success: function() {
                var ge = new GuiEdit({
                    page_id: page.id,
                    id: 'content_' + page.id,
                    oncomplete: function () {
                        page.getPageContent(function(data) {
                            $('#content_'+page.id).html(data.html);
                        });
                    }
                });
                ge.show();
            },
            error: function(jqXHR, textStatus, errorThrown) {
                throw errorThrown;
            }
        });
        $.ajaxSettings.cache = false;

        return false;
    });
};

/**
 * Do some things always
 */
$(function() {
    // Create content
    $('#st-create-content-link').button().click(function() {
        st.dialog.show('create-content');
    });

    // Make various links into buttons
    $('#st-wiki-subnav-link-invite, #st-login-to-edit-button-link, #st-wikinav-register').button();

    if (location.hash.toLowerCase() == '#new_page' || location.search.toLowerCase() == '?_p=new_page') {
        $('#st-create-content-link').click();
    }

    if (location.hash.toLowerCase() == '#new_page') {
        $('#st-create-content-link').click();
    }

    var sideboxToggle = Cookie.get('sideboxes');
    if (sideboxToggle == 'hide')
        hideSideboxes();
    else
        showSideboxes();
});


})(jQuery);
