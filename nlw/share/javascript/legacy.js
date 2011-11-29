;if (typeof Socialtext != 'object' || (!Socialtext.S3)) {

var Socialtext = Socialtext || {};
Socialtext.S3 = true;

(function(){
// Create a document.hasFocus function that tests whether we've lost focus
var chrome = /chrome/.test( navigator.userAgent.toLowerCase() );
if (typeof(document.hasFocus) == 'undefined' || chrome){
    var focus = true;
    $(window).focus();

    if ($.browser.msie) {
        $(document).bind('focusin', function() { focus = true });
        $(document).bind('focusout', function() { focus = false });
    }
    else {
        $(window).focus(function () { focus = true });
        $(window).blur(function () { focus = false });
    }
    document.hasFocus = function() { return focus }
}
})();

/* DO NOT EDIT THIS FUNCTION! run dev-bin/generate-title-to-id-js.pl instead */
function page_title_to_page_id (str) {
    str = str.replace(/^\s+/, '').replace(/\s+$/, '').replace(/[\u0000-\u002F\u003A-\u0040\u005B-\u005E\u0060\u007B-\u00A9\u00AB-\u00B1\u00B4\u00B6-\u00B8\u00BB\u00BF\u00D7\u00F7\u02C2-\u02C5\u02D2-\u02DF\u02E5-\u02EB\u02ED\u02EF-\u02FF\u0375\u0378-\u0379\u037E-\u0385\u0387\u038B\u038D\u03A2\u03F6\u0482\u0526-\u0530\u0557-\u0558\u055A-\u0560\u0588-\u0590\u05BE\u05C0\u05C3\u05C6\u05C8-\u05CF\u05EB-\u05EF\u05F3-\u060F\u061B-\u0620\u065F\u066A-\u066D\u06D4\u06DD\u06E9\u06FD-\u06FE\u0700-\u070F\u074B-\u074C\u07B2-\u07BF\u07F6-\u07F9\u07FB-\u07FF\u082E-\u08FF\u093A-\u093B\u094F\u0956-\u0957\u0964-\u0965\u0970\u0973-\u0978\u0980\u0984\u098D-\u098E\u0991-\u0992\u09A9\u09B1\u09B3-\u09B5\u09BA-\u09BB\u09C5-\u09C6\u09C9-\u09CA\u09CF-\u09D6\u09D8-\u09DB\u09DE\u09E4-\u09E5\u09F2-\u09F3\u09FA-\u0A00\u0A04\u0A0B-\u0A0E\u0A11-\u0A12\u0A29\u0A31\u0A34\u0A37\u0A3A-\u0A3B\u0A3D\u0A43-\u0A46\u0A49-\u0A4A\u0A4E-\u0A50\u0A52-\u0A58\u0A5D\u0A5F-\u0A65\u0A76-\u0A80\u0A84\u0A8E\u0A92\u0AA9\u0AB1\u0AB4\u0ABA-\u0ABB\u0AC6\u0ACA\u0ACE-\u0ACF\u0AD1-\u0ADF\u0AE4-\u0AE5\u0AF0-\u0B00\u0B04\u0B0D-\u0B0E\u0B11-\u0B12\u0B29\u0B31\u0B34\u0B3A-\u0B3B\u0B45-\u0B46\u0B49-\u0B4A\u0B4E-\u0B55\u0B58-\u0B5B\u0B5E\u0B64-\u0B65\u0B70\u0B72-\u0B81\u0B84\u0B8B-\u0B8D\u0B91\u0B96-\u0B98\u0B9B\u0B9D\u0BA0-\u0BA2\u0BA5-\u0BA7\u0BAB-\u0BAD\u0BBA-\u0BBD\u0BC3-\u0BC5\u0BC9\u0BCE-\u0BCF\u0BD1-\u0BD6\u0BD8-\u0BE5\u0BF3-\u0C00\u0C04\u0C0D\u0C11\u0C29\u0C34\u0C3A-\u0C3C\u0C45\u0C49\u0C4E-\u0C54\u0C57\u0C5A-\u0C5F\u0C64-\u0C65\u0C70-\u0C77\u0C7F-\u0C81\u0C84\u0C8D\u0C91\u0CA9\u0CB4\u0CBA-\u0CBB\u0CC5\u0CC9\u0CCE-\u0CD4\u0CD7-\u0CDD\u0CDF\u0CE4-\u0CE5\u0CF0-\u0D01\u0D04\u0D0D\u0D11\u0D29\u0D3A-\u0D3C\u0D45\u0D49\u0D4E-\u0D56\u0D58-\u0D5F\u0D64-\u0D65\u0D76-\u0D79\u0D80-\u0D81\u0D84\u0D97-\u0D99\u0DB2\u0DBC\u0DBE-\u0DBF\u0DC7-\u0DC9\u0DCB-\u0DCE\u0DD5\u0DD7\u0DE0-\u0DF1\u0DF4-\u0E00\u0E3B-\u0E3F\u0E4F\u0E5A-\u0E80\u0E83\u0E85-\u0E86\u0E89\u0E8B-\u0E8C\u0E8E-\u0E93\u0E98\u0EA0\u0EA4\u0EA6\u0EA8-\u0EA9\u0EAC\u0EBA\u0EBE-\u0EBF\u0EC5\u0EC7\u0ECE-\u0ECF\u0EDA-\u0EDB\u0EDE-\u0EFF\u0F01-\u0F17\u0F1A-\u0F1F\u0F34\u0F36\u0F38\u0F3A-\u0F3D\u0F48\u0F6D-\u0F70\u0F85\u0F8C-\u0F8F\u0F98\u0FBD-\u0FC5\u0FC7-\u0FFF\u104A-\u104F\u109E-\u109F\u10C6-\u10CF\u10FB\u10FD-\u10FF\u1249\u124E-\u124F\u1257\u1259\u125E-\u125F\u1289\u128E-\u128F\u12B1\u12B6-\u12B7\u12BF\u12C1\u12C6-\u12C7\u12D7\u1311\u1316-\u1317\u135B-\u135E\u1360-\u1368\u137D-\u137F\u1390-\u139F\u13F5-\u1400\u166D-\u166E\u1680\u169B-\u169F\u16EB-\u16ED\u16F1-\u16FF\u170D\u1715-\u171F\u1735-\u173F\u1754-\u175F\u176D\u1771\u1774-\u177F\u17B4-\u17B5\u17D4-\u17D6\u17D8-\u17DB\u17DE-\u17DF\u17EA-\u17EF\u17FA-\u180A\u180E-\u180F\u181A-\u181F\u1878-\u187F\u18AB-\u18AF\u18F6-\u18FF\u191D-\u191F\u192C-\u192F\u193C-\u1945\u196E-\u196F\u1975-\u197F\u19AC-\u19AF\u19CA-\u19CF\u19DB-\u19FF\u1A1C-\u1A1F\u1A5F\u1A7D-\u1A7E\u1A8A-\u1A8F\u1A9A-\u1AA6\u1AA8-\u1AFF\u1B4C-\u1B4F\u1B5A-\u1B6A\u1B74-\u1B7F\u1BAB-\u1BAD\u1BBA-\u1BFF\u1C38-\u1C3F\u1C4A-\u1C4C\u1C7E-\u1CCF\u1CD3\u1CF3-\u1CFF\u1DE7-\u1DFC\u1F16-\u1F17\u1F1E-\u1F1F\u1F46-\u1F47\u1F4E-\u1F4F\u1F58\u1F5A\u1F5C\u1F5E\u1F7E-\u1F7F\u1FB5\u1FBD\u1FBF-\u1FC1\u1FC5\u1FCD-\u1FCF\u1FD4-\u1FD5\u1FDC-\u1FDF\u1FED-\u1FF1\u1FF5\u1FFD-\u203E\u2041-\u2053\u2055-\u206F\u2072-\u2073\u207A-\u207E\u208A-\u208F\u2095-\u20CF\u20F1-\u2101\u2103-\u2106\u2108-\u2109\u2114\u2116-\u2118\u211E-\u2123\u2125\u2127\u2129\u212E\u213A-\u213B\u2140-\u2144\u214A-\u214D\u214F\u218A-\u245F\u249C-\u24E9\u2500-\u2775\u2794-\u2BFF\u2C2F\u2C5F\u2CE5-\u2CEA\u2CF2-\u2CFC\u2CFE-\u2CFF\u2D26-\u2D2F\u2D66-\u2D6E\u2D70-\u2D7F\u2D97-\u2D9F\u2DA7\u2DAF\u2DB7\u2DBF\u2DC7\u2DCF\u2DD7\u2DDF\u2E00-\u2E2E\u2E30-\u3004\u3008-\u3020\u3030\u3036-\u3037\u303D-\u3040\u3097-\u3098\u309B-\u309C\u30A0\u30FB\u3100-\u3104\u312E-\u3130\u318F-\u3191\u3196-\u319F\u31B8-\u31EF\u3200-\u321F\u322A-\u3250\u3260-\u327F\u328A-\u32B0\u32C0-\u33FF\u4DB6-\u4DFF\u9FCC-\u9FFF\uA48D-\uA4CF\uA4FE-\uA4FF\uA60D-\uA60F\uA62C-\uA63F\uA660-\uA661\uA673-\uA67B\uA67E\uA698-\uA69F\uA6F2-\uA716\uA720-\uA721\uA789-\uA78A\uA78D-\uA7FA\uA828-\uA82F\uA836-\uA83F\uA874-\uA87F\uA8C5-\uA8CF\uA8DA-\uA8DF\uA8F8-\uA8FA\uA8FC-\uA8FF\uA92E-\uA92F\uA954-\uA95F\uA97D-\uA97F\uA9C1-\uA9CE\uA9DA-\uA9FF\uAA37-\uAA3F\uAA4E-\uAA4F\uAA5A-\uAA5F\uAA77-\uAA79\uAA7C-\uAA7F\uAAC3-\uAADA\uAADE-\uABBF\uABEB\uABEE-\uABEF\uABFA-\uABFF\uD7A4-\uD7AF\uD7C7-\uD7CA\uD7FC-\uF8FF\uFA2E-\uFA2F\uFA6E-\uFA6F\uFADA-\uFAFF\uFB07-\uFB12\uFB18-\uFB1C\uFB29\uFB37\uFB3D\uFB3F\uFB42\uFB45\uFBB2-\uFBD2\uFD3E-\uFD4F\uFD90-\uFD91\uFDC8-\uFDEF\uFDFC-\uFDFF\uFE10-\uFE1F\uFE27-\uFE32\uFE35-\uFE4C\uFE50-\uFE6F\uFE75\uFEFD-\uFF0F\uFF1A-\uFF20\uFF3B-\uFF3E\uFF40\uFF5B-\uFF65\uFFBF-\uFFC1\uFFC8-\uFFC9\uFFD0-\uFFD1\uFFD8-\uFFD9\uFFDD-\uFFFF]+/g,'_');
    str = str.replace(/_+/g, '_');
    str = str.replace(/(^_|_$)/g, '');
    if (str == '0') str = '_';
    if (str == '') str = '_';
    return str.toLocaleLowerCase();
} /* function page_title_to_page_id */

function nlw_name_to_id(name) {
    if (name == '')
        return '';

    return encodeURI(page_title_to_page_id(name));
}

push_onload_function = function (fcn) { jQuery(fcn) }

Socialtext.make_table_sortable = function(table) {
    if (jQuery.browser.msie) { 
        for (var i in table) {
            if (i.match(/^jQuery\d+/)) {
                table.removeAttribute(i);
                jQuery(table).removeAttr(i);
                jQuery('*', table).removeAttr(i);
            }
        }
    }

    if (!table) return;
    if (typeof(table.config) != 'undefined' && table.config != null) {
        // table.config = null;
        $(table).trigger("update");
    }
    else {
        $(table).addClass("sort");
        $(table).tablesorter();

        // Because the tables inside wysiwyg editing area are expected to be
        // changed, we forcibly update it on every sort.
        if (window.wikiwyg &&
            wikiwyg.current_mode &&
            wikiwyg.current_mode.classtype == 'wysiwyg' &&
            $(table).parents("body").get(0) == wikiwyg.current_mode.get_edit_document().body
        ) {
            $(table).bind("sortStart", function() {
                $(this).trigger("update");
            });
        }
    }
}

Socialtext.make_table_unsortable = function(table) {
    if (!table) return;
    if (typeof(table.config) != 'undefined')  {
        try { delete table.config; }
        catch (e) { table.config = null; }
    }
    $(table).removeClass("sort").find("tr:eq(0) td").unbind("click").unbind("mousedown");
}

Socialtext.prepare_attachments_before_save = function() {
    var files = Attachments.get_new_attachments();

    $.each(files, function () {
        if (this.deleted) return;
        $('<input type="hidden" name="attachment" />')
            .val(this['id'] + ':' + this['page-id'])
            .appendTo('#st-page-editing-files');
    });
}

Socialtext.show_signal_network_dropdown = function(prefix, width) {
    prefix = prefix || '';
    var url = '/widgets/javascript/socialtext-network-dropdown.js';
    $.getScript(nlw_make_plugin_path(url), function() {
        if ((typeof Activities == 'undefined') || !Activities) return;
        var dropdown = new Activities.NetworkDropdown({
            prefix: prefix,
            width: width,
            user: Socialtext.userid,
            workspace_id: Socialtext.wiki_id,
            account_id: Socialtext.current_workspace_account_id
        });
        dropdown.show();
    });
}

Socialtext.addNewTag = function (tag) {
    var rand = (''+Math.random()).replace(/\./, '');

    jQuery("#st-page-editing-files")
        .append(jQuery('<input type="hidden" name="add_tag" id="st-tagqueue-' + rand +'" />').val(tag));

    jQuery('#st-tagqueue-list').show();

    jQuery("#st-tagqueue-list")
        .append(
            jQuery('<span class="st-tagqueue-taglist-name" id="st-taglist-'+rand+'" />')
            .text(
                (jQuery('.st-tagqueue-taglist-name').size() ? ', ' : '')
                + tag
            )
        );

    jQuery("#st-taglist-" + rand)
        .append(
            jQuery('<a href="#" class="st-tagqueue-taglist-delete" />')
                .attr('title', loc("edit.remove=tag", tag))
                .click(function () {
                    jQuery('#st-taglist-'+rand).remove();
                    jQuery('#st-tagqueue-'+rand).remove();
                    if (!jQuery('.st-tagqueue-taglist-name').size())
                        jQuery('#st-tagqueue-list').hide();
                    return false;
                })
                .html(
                    '<img src="/static/skin/common/images/delete.png" width="16" height="16" border="0" />'
                )
        );
}


$(function() {
    if (document.getElementById('contentWarning')) {
        setTimeout(function() {
            /* The DOM may be entirely gone by this point, so first check we
             * still have access to $ and to contentWarning.
             */
            if ((typeof $ != 'undefined') && document.getElementById('contentWarning')) {
                $('#contentWarning').hide('slow')
            }
        }, 10000);
    }

    // Fix the global nav for IE6
    //$('#mainNav ul.level2').createSelectOverlap({noPadding: true});

    $('table.sort, table[data-sort]')
        .each(function() { Socialtext.make_table_sortable(this) });

    $('#st-page-boxes-toggle-link')
        .bind('click', function() {
            var hidden = $('#contentColumns').hasClass('hidebox');
            if (hidden)
                $('#contentColumns').removeClass("hidebox").addClass("showbox");
            else
                $('#contentColumns').removeClass("showbox").addClass("hidebox");
            hidden = !hidden;
            $(this).text(hidden ? loc('nav.show') : loc('nav.hide'));
            Cookie.set('st-page-accessories', hidden ? 'hide' : 'show');

            if ($('div#contentLeft').css('overflow') == 'visible') {
                if (hidden) {
                    cl.width(parseInt(cl.css('max-width')));
                }
                else {
                    cl.width(parseInt(cl.css('min-width')));
                }
            }
            
            // Because the content area's height might have changed, repaint
            // the Edit/Comment buttons at the bottom for IE.
            Page._repaintBottomButtons();

            return false;
        });

    $('#st-tags-addlink')
        .bind('click', function () {
            $(this).hide();
            $('#st-tags-addbutton-link').show();
            $('#st-tags-field')
                .val('')
                .show()
                .focus();
            return false;
        })

    $('#st-tags-field')
        .blur(function () {
            setTimeout(function () {
                $('#st-tags-field').hide();
                $('#st-tags-addbutton-link').hide();
                $('#st-tags-addlink').show()
            }, 500);
        })
        .lookahead({
            url: Page.workspaceUrl() + '/tags',
            params: {
                order: 'weighted',
                exclude_from: Socialtext.page_id
            },
            linkText: function (i) {
                return i.name
            },
            onAccept: function (val) {
                Page.addTag(val);
            }
        });
            

    $('#st-tags-form')
        .bind('submit', function () {
            var tag = $('#st-tags-field').val();
            Page.addTag(tag);
            return false;
        });

    if ($.browser.msie && $.browser.version < 7) {
        $('#st-attachment-listing li').mouseover(function() {
            $(this).addClass("hover");
        });
        $('#st-attachment-listing li').mouseout(function() {
            $(this).removeClass("hover");
        });

        // {bz: 4714}: IE6 doesn't grok this :hover rule in screen.css,
        //             so code its equivalent using jQuery here.
        $('ul.buttonRight li.submenu, #controlsRight ul.level1 li.submenu')
            .mouseover(function(){
                $('ul.level2', this).show();
            })
            .mouseout(function(){
                $('ul.level2', this).hide();
            });
    }

    $('#st-attachments-uploadbutton').unbind('click').click(function () {
        get_lightbox('attachment', function () {
            $('#st-attachments-attach-list').html('').hide();
            Attachments.showUploadInterface();
        });
        return false;
    });

    $('.extract_attachment').unbind('click').click(function () {
        get_lightbox('attachment', function() {
            $(this).children('img')
                .attr('src', '/static/skin/common/images/ajax-loader.gif');
                Attachments.extractAttachment($(this).attr('name'));
                return false
        });
    });

    $('.delete_attachment').unbind('click').click(function () {
        var self = this
        get_lightbox('attachment', function () {
            Attachments.showDeleteInterface(self);
        });
        return false;
    });

    var _gz = '';

    if (!$.browser.safari && Socialtext.accept_encoding && Socialtext.accept_encoding.match(/\bgzip\b/)) {
        _gz = '.gz';
    }

    var timestamp = (new Date).getTime();

    var editor_uri = nlw_make_s3_path('/javascript/socialtext-editor.js' + _gz);
    if (Socialtext.dev_env) {
        editor_uri = editor_uri.replace(/(\d+\.\d+\.\d+\.\d+)/,'$1.'+timestamp);
    }

    var socialcalc_uri = nlw_make_plugin_path(
        "/socialcalc/javascript/socialtext-socialcalc.js" + _gz
    );
    if (Socialtext.socialcalc_make_time) {
        socialcalc_uri = socialcalc_uri.replace(
            /(\d+\.\d+\.\d+\.\d+)/,
            '$1.' + Socialtext.socialcalc_make_time
        );
    }

    var ckeditor_uri = nlw_make_plugin_path(
        "/ckeditor/javascript/socialtext-ckeditor.js" + _gz
    );
    if (Socialtext.ckeditor_make_time) {
        ckeditor_uri = ckeditor_uri.replace(
            /(\d+\.\d+\.\d+\.\d+)/,
            '$1.' + Socialtext.ckeditor_make_time
        );
    }

    function get_lightbox (lightbox, cb) {
        Socialtext.lightbox_loaded = Socialtext.lightbox_loaded || {};
        if (Socialtext.lightbox_loaded[lightbox]) {
            cb();
        }
        else {
            Socialtext.lightbox_loaded[lightbox] = true;
            var uri = nlw_make_s3_path(
                '/javascript/lightbox-' + lightbox + '.js' + _gz
            );
            if (Socialtext.dev_env) {
                uri = uri.replace(/(\d+\.\d+\.\d+\.\d+)/,'$1.'+timestamp);
            }

            $.ajaxSettings.cache = true;
            $.getScript(uri, cb);
            $.ajaxSettings.cache = false;
        }
    }
    window.get_lightbox = get_lightbox;

    function get_plugin_lightbox (plugin, lightbox, cb) {
        Socialtext.plugin_lightbox_loaded =
            Socialtext.plugin_lightbox_loaded || {};
        if (Socialtext.plugin_lightbox_loaded[lightbox]) {
            cb()
        }
        else {
            var uri = nlw_make_plugin_path(
                '/' + plugin + '/javascript/lightbox-' + lightbox + '.js' + _gz
            );
            if (Socialtext.dev_env) {
                uri = uri.replace(/(\d+\.\d+\.\d+\.\d+)/,'$1.'+timestamp);
            }
            $.ajaxSettings.cache = true;
            $.getScript(uri, cb);
            $.ajaxSettings.cache = false;
        }
    }
    window.get_plugin_lightbox = get_plugin_lightbox;

    $(".weblog_comment").click(function () {
        var page_id = this.id.replace(/^comment_/,'');
        get_lightbox('comment', function () {
            var ge = new GuiEdit({
                page_id: page_id,
                id: 'content_'+page_id,
                oncomplete: function () {
                    $.get(Page.pageUrl(page_id), function (html) {
                        $('#content_'+page_id).html(html);
                    }, 'html');
                }
            });
            ge.show();
        });
        return false;
    });

    $("#st-pagetools-email").click(function () {
        get_lightbox('email', function () {
            var Email = new ST.Email;
            Email.show();
        });
        return false;
    });

    $('#st-edit-warning-help').click(function() {
        get_lightbox('edit_warning_help', function() {
            $("body").append(Jemplate.process("edit_warning_help.tt2", {}));
            jQuery.showLightbox({
                speed: 0,
                content: "#st-edit-warning-help-inline",
                close: "#st-edit-warning-help-inline .close",
                callback: function() {
                    //$.hideLightbox();
                }
            });
        });
        return false;
    });

    //index.cgi?action=duplicate_popup;page_name=[% page.id %]
    $("#st-pagetools-duplicate").click(function () {
        get_lightbox('duplicate', function () {
            var duplicate = new ST.Duplicate;
            duplicate.duplicateLightbox();
        });
        return false;
    });

    $("#st-pagetools-rename").click(function () {
        get_lightbox('rename', function () {
            var rename = new ST.Rename;
            rename.renameLightbox();
        });
        return false;
    });

    $("#st-pagetools-edit-as-xhtml").click(function () {
        Socialtext.auto_convert_wiki_to_html = true;
        Socialtext.load_editor();
        return false;
    });

    var page_lock_rollover = function() {
        var img = $(this).find('img');
        var src = img.attr('src');
        var path = '/static/skin/s3/images/';

        new_src = ( src == path + 'lock-locked.png' )
            ? path + 'lock-unlocked.png'
            : path + 'lock-locked.png';

        img.attr('src', new_src);
    }

    $('#st-admin-lock-link').mouseover(page_lock_rollover);
    $('#st-admin-lock-link').mouseout(page_lock_rollover);
    $('#st-admin-lock-link').click(function() {
        $(this).unbind('mouseover');
        $(this).unbind('mouseout');

        var img = $(this).find('img');
        img.attr('src', '/static/skin/common/images/ajax-loader.gif');
    });

    //index.cgi?action=copy_to_workspace_popup;page_name=[% page.id %]')
    $("#st-pagetools-copy").click(function () {
        get_lightbox('copy', function () {
            var copy = new ST.Copy;
            copy.copyLightbox();
        });
        return false;
    });

    $("#st-create-content-link, .incipient").unbind("click").click(function (e, data) {
        var $anchor = jQuery(this);

        var title;

        if ($anchor.hasClass('incipient')) {
            var match = $anchor.attr('href').match(/page_name=([^;#]+)/);
            if (match) {
                title = match[1];
            }
            else {
                title = $anchor.text();
            }
        }
        else if (data) {
            title = data.title
        }

        get_lightbox('create_content', function () {
            var create_content = new ST.CreateContent;
            create_content.show();
            if (title) {
                create_content.set_incipient_title(title);
            }
        });
        return false;
    });

    $("#st-pagetools-delete").click(function () {
        get_lightbox('delete', function () {
            var del = new ST.Delete;
            del.deleteLightbox();
        });
        return false;
    });

    if (location.hash.toLowerCase() == '#new_page' || location.search.toLowerCase() == '?_p=new_page') {
        $('#st-create-content-link').click();
    }

    if (location.hash.toLowerCase() == '#new_page') {
        $('#st-create-content-link').click();
    }

    // Currently, the pre edit hook will check for an edit contention.
    Socialtext.pre_edit_hook = function (wikiwyg_launcher, cleanup_callback) {
        jQuery.ajax({
            type: 'POST',
            url: location.pathname,
            data: {
                action: 'edit_check_start',
                page_name: Socialtext.wikiwyg_variables.page.title
            },
            dataType: 'json',
            success: function(data) {
                if (data.user_id) {
                    if (location.hash && /^#draft-\d+$/.test(location.hash)) {
                        // If recovering from a draft, don't show edit contention
                        // if the contention was from the same editing user
                        if (data.user_id == Socialtext.real_user_id) return;
                    }

                    get_lightbox("edit_check", function() {
                        $("body").append(
                            Jemplate.process("edit_check.tt2", $.extend({
                                loc: loc,
                                time_ago: loc('ago.minutes=count', data.minutes_ago)
                            }, data))
                        );

                        jQuery.showLightbox({
                            speed: 0,
                            content: "#st-edit-check",
                            close: "#st-edit-check .close",
                            callback: function() {
                                $('#bootstrap-loader').hide();

                                var bootstrap = false;
                                $("#st-edit-check .continue")
                                    .removeClass('checked')
                                    .unbind('click')
                                    .click(function() {

                                    jQuery.ajax({
                                        type: 'POST',
                                        url: location.pathname,
                                        data: {
                                            action: 'edit_start',
                                            page_name: Socialtext.wikiwyg_variables.page.title,
                                            revision_id: Socialtext.wikiwyg_variables.page.revision_id
                                        }
                                    });

                                    $("#st-edit-check .continue").addClass('checked');
                                    $.hideLightbox();
                                });

                                $("#lightbox")
                                    .one("lightbox-unload", function() {
                                        if (cleanup_callback && !$("#st-edit-check .continue").hasClass('checked')) {
                                            cleanup_callback();
                                        }
                                        $('#st-edit-check').remove();
                                    });
                            }
                        });

                    });
                }
            }
        });

        wikiwyg_launcher();
    }

    Socialtext._show_loading_animation = function () {
        $('#bootstrap-loader')
            .css('position', 'absolute')
            .css('float', 'none')
            .css('left', 
                $('#st-editing-tools-edit li:last').offset().left + 120 + 'px')
            .show();
    }

    Socialtext._hide_floating_dialogs = function () {
        /* Hide the "Signal This Page" floating dialog */
        if ($('#st-signal-this-frame').size() > 0) {
            $('#st-signal-this-frame').fadeOut('fast', function(){
                $('#st-signal-this-frame').remove();
            });
        }
    }

    Socialtext.load_editor = function () {
        $.ajaxSettings.cache = true;
        var current_workspace = Socialtext.wikiwyg_variables.hub.current_workspace;

        if (Socialtext.page_type == 'spreadsheet' && current_workspace.enable_spreadsheet) {
            $.getScript(socialcalc_uri, function () {
                Socialtext.start_spreadsheet_editor();
                $('#bootstrap-loader').hide();
            });
        }
        else if (Socialtext.page_type == 'xhtml' && current_workspace.enable_xhtml) {
            $.getScript(ckeditor_uri, function () {
                Socialtext.start_xhtml_editor();
                $('#bootstrap-loader').hide();
            });
        }
        else if (Socialtext.auto_convert_wiki_to_html && current_workspace.enable_xhtml) {
            $.getScript(ckeditor_uri, function () {
                Socialtext.start_xhtml_editor();
                $('#bootstrap-loader').hide();
            });
        }
        else {
            $.getScript(editor_uri);

            if (!$.browser.msie) {
                var lnk = $('link[rel=stylesheet][media=screen]');
                var uri = nlw_make_s3_path('/css/wikiwyg.css');
                if (Socialtext.dev_env) {
                    uri = uri.replace(/(\d+\.\d+\.\d+\.\d+)/,'$1.'+timestamp);
                }
                lnk.clone()
                    .attr('href',  uri)
                    .attr('media', 'wikiwyg')
                    .appendTo('head');
            }
        }
        $.ajaxSettings.cache = false;
        return false;
    }

    $("#st-edit-button-link,#st-edit-actions-below-fold-edit, #bottomButtons .editButton")
        .one("click", function(){
	    Socialtext._hide_floating_dialogs();
	    Socialtext._show_loading_animation();

	    setTimeout(
		function() {
		    if (editorIntervalId) {
			clearInterval(editorIntervalId);
			Socialtext.load_editor();
		    }
		}, 90000 // max. 90sec wait before we start editing
	    );

	    var editorIntervalId = setInterval(function() {
		if (Socialtext.body_loaded) {
		    clearInterval(editorIntervalId);
		    editorIntervalId = 0;
		    Socialtext.load_editor();
		}
	    }, 100); // Poll every 0.1 seconds until all pictures finish loading
	});

    if (Socialtext.double_click_to_edit) {
        var double_clicker = function() {
            jQuery("#st-edit-button-link").click();
        };
        jQuery("#st-page-content").one("dblclick", double_clicker);
    }

    $('#st-listview-submit-pdfexport').click(function() {
        if (!$('.st-listview-selectpage-checkbox:checked').size()) {
            alert(loc("error.no-page-pdf"));
        }
        else {
            $('#st-listview-action').val('pdf_export')
            $('#st-listview-filename').val(Socialtext.wiki_id + '.pdf');
            $('#st-listview-form').submit();
        }
        return false;
    });

    $('#st-listview-submit-rtfexport').click(function() {
        if (!$('.st-listview-selectpage-checkbox:checked').size()) {
            alert(loc("error.no-page-doc"));
        }
        else {
            $('#st-listview-action').val('rtf_export')
            $('#st-listview-filename').val(Socialtext.wiki_id + '.rtf');
            $('#st-listview-form').submit();
        }
        return false;
    });

    $('#st-listview-selectall').click(function () {
        var self = this;
        $('input[type=checkbox]').each(function() {
            if ( ! $(this).attr('disabled') ) {
                $(this).attr('checked', self.checked);
            }
        });
        return true;
    });

    $('input[name=homepage_is_weblog]').click(function () {
        $('input[name=homepage_weblog]')
            .attr('disabled', Number($(this).val()) ? false : true)
    });

    $('input[name=homepage_weblog]').lookahead({
        url: function () { return Page.workspaceUrl() + '/tags' },
        filterValue: function (val) {
            return val + '.*(We)?blog$';
        },
        linkText: function (i) { return i.name }
    });

    Socialtext.ui_expand_on = function() {
        $("#st-edit-pagetools-expand,#st-pagetools-expand").attr("title", loc("info.normal-view")).text(loc("edit.normal")).addClass("contract");

        if ($.browser.msie && $.browser.version < 7) {
            $('#globalNav select').css('visibility', 'hidden');
        }

        $('#st-edit-mode-container, #mainWrap').addClass("expanded");

        $(window).trigger("resize");

        if ($('body').css('overflow') != 'hidden') {
            Socialtext._originalBodyOverflow = $('body').css('overflow');
            $('body').css('overflow', 'hidden');
        }

        if ($('html').css('overflow') != 'hidden') {
            Socialtext._originalHTMLOverflow = $('html').css('overflow');
            $('html').css('overflow', 'hidden');
        }

        window.scrollTo(0, 0);
        return false;
    };
    Socialtext.ui_expand_off = function() {
        $("#st-edit-pagetools-expand,#st-pagetools-expand").attr("title", loc("info.expand-view")).text(loc("edit.expand")).removeClass("contract");

        if ($.browser.msie && $.browser.version < 7) {
            $('#globalNav select').css('visibility', 'visible');
        }

        $('#st-edit-mode-container, #mainWrap').removeClass("expanded");

        $("iframe#st-page-editing-wysiwyg").width( $('#st-edit-mode-view').width() - 48 );

        $(window).trigger("resize");
        $('html').css('overflow', Socialtext._originalHTMLOverflow || 'auto');
        $('body').css('overflow', Socialtext._originalBodyOverflow || 'auto');
        return false;
    };
    Socialtext.ui_expand_setup = function() {
        if (Cookie.get("ui_is_expanded"))
            return Socialtext.ui_expand_on();
    };
    Socialtext.ui_expand_toggle = function() {
        if (Cookie.get("ui_is_expanded")) {
            Cookie.del("ui_is_expanded");
            return Socialtext.ui_expand_off();
        }
        else {
            Cookie.set("ui_is_expanded", "1");
            return Socialtext.ui_expand_on();
        }
    };
    $("#st-pagetools-expand").click(Socialtext.ui_expand_toggle);

    function makeWatchHandler (pageId) { return function(){
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
    }; }

    $('#st-wikinav-register a').click(function() {
        if (Socialtext.userid == 'guest') return true;

        $.ajax({
            type: 'GET',
            url: '/data/workspaces/' + Socialtext.wiki_id + '/groups',
            success: function(response) {
                var groups = $.grep(response, function(group) {
                    return (group.permission_set == 'self-join');
                });

                if (groups.length > 0) {
                    get_lightbox('self_join_workspace', function () {
                        SelfJoinWorkspace.show(groups);
                    });
                }
                else { // old default action
                    var href = $('#st-wikinav-register a').attr('href');
                    window.location = href;
                }
            },
            dataType: 'json'
        });
        return false;
    });

    // Watch handler for single-page view
    $('#st-watchlist-indicator').click(makeWatchHandler(Socialtext.page_id));

    // Watch handler for watchlist view
    $('td.listview-watchlist a[id^=st-watchlist-indicator-]').each(function(){
        $(this).click(
            makeWatchHandler(
                $(this).attr('id').replace(/^st-watchlist-indicator-/, '')
            )
        );
    });

    if ( Socialtext.new_page
            && Socialtext.page_title != loc("page.untitled")
            && Socialtext.page_title != loc("sheet.untitled")
            && !location.href.toString().match(/action=display;/)
            && !/^#draft-\d+$/.test(location.hash) ) {
        $("#st-create-content-link").trigger("click", { title: Socialtext.page_title })
    }
    else if (Socialtext.new_page||
        Socialtext.start_in_edit_mode ||
        location.hash.toLowerCase() == '#edit' ) {
        setTimeout(function() {
            $("#st-edit-button-link").click();
        }, 500);
    }

    var cl = $('div#contentLeft');
    if (cl.length) {
        var adjustContentLeftOverflow = function () {
            var cl = $('div#contentLeft');
            if (cl.get(0).offsetHeight > cl.get(0).clientHeight) {
                var clWidth = $('#contentLeft').get(0).scrollWidth;
                var crWidth = $('#contentRight').width();

                var newWidth = clWidth + crWidth + 50;

                /* {bz: 3395}
                 * Enforce the #mainWrap min-width expression in screen.ie.css
                 */
                if ($.browser.msie && newWidth < 950) newWidth = 950;

                $('#mainWrap').width(newWidth);

                cl.css('min-width', clWidth + 'px');
                cl.css('max-width', (clWidth + crWidth) + 'px');

                if ($('div#contentColumns.hidebox').length) {
                    cl.width(clWidth + crWidth);
                }
                else {
                    cl.width(clWidth);
                }

                cl.addClass('overflowVisible');

                $('#contentRight').css('width', crWidth + 'px');
                $('#contentRight').css('max-width', crWidth + 'px');

                Page._repaintBottomButtons();
            }
        };
        adjustContentLeftOverflow();
        $(window).resize(adjustContentLeftOverflow);
    }

    // Find the field to focus
    var focus_field = Socialtext.info.focus_field[ Socialtext.action ];
    if (! focus_field && typeof(focus_field) == 'undefined') {
        focus_field = Socialtext.info.focus_field.default_field;
    }
    if (focus_field)
        jQuery(focus_field).select().focus();

    // Workaround IE bug in {bz: 4595} by repainting buttons on image load
    if ($.browser.msie && $('div.wiki img').length > 0) {
        $('div.wiki img').load(function(){
            Page._repaintBottomButtons();
        });
        setTimeout(function(){
            Page._repaintBottomButtons();
        }, 100);
    }

    if ($.browser.msie && $('div.wiki iframe').length > 0) {
        $('div.wiki iframe').load(function(){
            Page._repaintBottomButtons();
        }).resize(function(){
            Page._repaintBottomButtons();
        });
        setTimeout(function(){
            Page._repaintBottomButtons();
        }, 100);
    }

    // Offer to restore unsaved drafts
    if (typeof localStorage != 'undefined' && !(/^#draft-\d+$/.test(location.hash || ''))) {
      $(function(){
        try {
          var draft_json = localStorage.getItem('st-drafts-' + Socialtext.real_user_id);
          var all_drafts = draft_json ? $.secureEvalJSON(draft_json) : {};
          for (var key in all_drafts) {
            var draft = all_drafts[key];
            if (((new Date()).getTime() - draft.last_updated) > 30 * 1000)  {
              var resume_link = '/'+draft.workspace_id+'/'
                              + '?action=edit'
                              + ';page_name=' + encodeURIComponent(draft.page_title)
                              + ';page_type=' + draft.page_type
                              + '#draft-'+key;
              $('#contentColumns').prepend(
                $('<div />', { id: "st-draft-notice-" + key, css: { background: '#ffff80', textAlign: 'center', padding: '2px', borderBottom: '1px solid #ccc' } })
                  .text(loc('draft.unsaved=page,wiki,wiki-id:', draft.page_title, draft.workspace_title, draft.workspace_id))
                  .append('&nbsp;')
                  .append(
                    $('<a />')
                      .text(loc('draft.resume'))
                      .attr('href', resume_link)
                  )
                  .append(loc('draft.or'))
                  .append(
                    $('<a />')
                      .text(loc('draft.discard'))
                      .attr('href', '#')
                      .attr('id', 'st-discard-draft-' + key)
                      .click(function(){
                        if (confirm(loc("draft.discard?"))) {
                          var key = $(this).attr('id').replace(/^st-discard-draft-/, '');
                          $('#st-draft-notice-' + key).fadeOut();
                          try {
                            var all_drafts = $.secureEvalJSON(localStorage.getItem('st-drafts-' + Socialtext.real_user_id));
                            delete all_drafts[key];
                            localStorage.setItem('st-drafts-' + Socialtext.real_user_id, $.toJSON(all_drafts));
                          } catch (e) {}
                        }
                        return false;
                      })
                  )
                  .append(loc('draft.?'))
               );
            }
          }
        } catch (e) {}
      });
    }

    // Maximize the window if we're running under Selenium
    try { if (
        (typeof seleniumAlert != 'undefined' && seleniumAlert)
        || (typeof Selenium != 'undefined' && Selenium)
        || ((typeof window.top != 'undefined' && window.top)
            && (window.top.selenium_myiframe
                || window.top.seleniumLoggingFrame)
        || ((typeof window.top.opener != 'undefined' && window.top.opener)
            && (window.top.opener.selenium_myiframe
                || window.top.opener.seleniumLoggingFrame))
        )
    ) {
        top.window.moveTo(0,0);
        top.window.resizeTo(screen.availWidth, screen.availHeight);
    } } catch (e) {}
});

};
