(function ($) {

Page = {
    // args: (ws,page) or (page_in_current_workspace)
    active_page_exists: function () {
        var args = $.makeArray(arguments);
        var page_name = trim(args.pop());
        var wiki_id = args.pop() || Socialtext.wiki_id;
        var data = jQuery.ajax({
            url: Page.pageUrl(wiki_id, page_name),
            async: false
        });
        return data.status == '200';
    },

    restApiUri: function () {
        return Page.pageUrl.apply(this, arguments);
    },

    workspaceUrl: function (wiki_id) {
        return '/data/workspaces/' + (wiki_id || Socialtext.wiki_id);
    },

    pageUrl: function () {
        var args = $.makeArray(arguments);
        var page_name = args.pop() || Socialtext.page_id;
        var wiki_id = args.pop() || Socialtext.wiki_id;
        return Page.workspaceUrl(wiki_id) + '/pages/' + page_name;
    },

    cgiUrl: function () {
        return '/' + Socialtext.wiki_id + '/';
    },

    _repaintBottomButtons: function() {
        $('#bottomButtons').html($('#bottomButtons').html());
        Avatar.createAll();
        $('#st-edit-button-link-bottom').click(function(){
            $('#st-edit-button-link').click();
            return false;
        });
        $('#st-comment-button-link-bottom').click(function(){
            $('#st-comment-button-link').click();
            return false;
        });
    },

    setPageContent: function(html) {
        $('#st-page-content').html(html);
    
        // We may not yet have an edit window, and it may not have finished
        // initialization even if we do.  So ignore all errors here.
        try {
            var iframe = $('iframe#st-page-editing-wysiwyg').get(0);
            iframe.contentWindow.document.body.innerHTML = html;
        } catch (e) {};

        // For MSIE, force browser reflow of the bottom buttons to avoid {bz: 966}.
        Page._repaintBottomButtons();

        // Repaint after each image finishes loading since the height
        // would've been changed.
        $('#st-page-content img').load(function() {
            Page._repaintBottomButtons();
        });
    },

    refreshPageContent: function (force_update) {
        if (Socialtext.page_type != 'wiki') return false;

        $.ajax({
            url: this.pageUrl(),
            data: {
                link_dictionary: 's2',
                verbose: 1,
                iecacheworkaround: (new Date).getTime()
            },
            async: false,
            cache: false,
            dataType: 'json',
            success: function (data) {
                Page.html = data.html;
                var newRev = data.revision_id;
                var oldRev = Socialtext.revision_id;
                if ((oldRev < newRev) || force_update) {
                    Socialtext.wikiwyg_variables.page.revision_id =
                        Socialtext.revision_id = newRev;

                    // By this time, the "edit_wikiwyg" Jemplate had already
                    // finished rendering, so we need to reach into the
                    // bootstrapped input form and update the revision ID
                    // there, otherwise we'll get a bogus editing contention.
                    $('#st-page-editing-revisionid').val(newRev);
                    $('#st-rewind-revision-count').html(newRev);

                    rev_string = loc('page.revisions=count', data.revision_count);
                    $('#controls-right-revisions').html(rev_string);
                    $('#bottom-buttons-revisions').html(rev_string);
                    $('#update-attribution .st-username').empty().append(
                        jQuery(".nlw_phrase", jQuery(data.last_editor_html))
                    );
   
                    $('#update-attribution .st-updatedate').empty().append(
                        jQuery(".nlw_phrase", jQuery(data.last_edit_time_html))
                    );

                    Page.setPageContent(data.html);

                    $('table.sort')
                        .each(function() { Socialtext.make_table_sortable(this) });

                    // After upload, refresh the wikitext contents.
                    if ($('#wikiwyg_wikitext_textarea').size()) {
                        $.ajax({
                            url: Page.pageUrl(),
                            data: { accept: 'text/x.socialtext-wiki' },
                            cache: false,
                            success: function (text) {
                                $('#wikiwyg_wikitext_textarea').val(text);
                            }
                        });
                    }
                }
            } 
        });
    },

    tagUrl: function (tag) {
        return this.pageUrl() + '/tags/' + encodeURIComponent(tag);
    },

    attachmentUrl: function (attach_id) {
        return '/data/workspaces/' + Socialtext.wiki_id +
               '/attachments/' + Socialtext.page_id + ':' + attach_id
    },

    refreshTags: function () {
        var tag_url = '?action=category_display;category=';
        $.ajax({
            url: this.pageUrl() + '/tags?order=alpha',
            cache: false,
            dataType: 'json',
            success: function (tags) {
                $('#st-tags-listing').html('');
                for (var i=0; i< tags.length; i++) {
                    var tag = tags[i];
                    $('#st-tags-listing').append(
                        $('<li />').append(
                            $('<a></a>')
                                .text(tag.name)
                                .addClass('tag_name')
                                .attr('title', tag.name)
                                .attr('href', tag_url + encodeURIComponent(tag.name)),

                            ' ',
                            $('<a href="#" />')
                                .html('<img src="'+nlw_make_s3_path('/images/delete.png')+'" width="16" height="16" border="0" />')
                                .addClass('delete_tag')
                                .attr('name', tag.name)
                                .attr('alt', loc('page.delete-tag'))
                                .attr('title', loc('page.delete-tag'))
                                .bind('click', function () {
                                    $(this).children('img').attr('src', nlw_make_static_path('/skin/common/images/ajax-loader.gif'));
                                    Page.delTag(this.name);
                                    return false;
                                })
                        )
                    )
                }
                if (tags.length == 0) {
                    $('#st-tags-listing').append( 
                        $('<div id="st-no-tags-placeholder" />')
                            .html(loc('page.no-tags'))
                    );
                }
            }
        });
    },

    _format_bytes: function(filesize) {
        var n = 0;
        var unit = '';
        if (filesize < 1024) {
            unit = '';
            n = filesize;
        } else if (filesize < 1024*1024) {
            unit = 'K';
            n = filesize/1024;
            if (n < 10)
                n = n.toPrecision(2);
            else
                n = n.toPrecision(3);
        } else {
            unit = 'M';
            n = filesize/(1024*1024);
            if (n < 10) {
                n = n.toPrecision(2);
            } else if ( n < 1000) {
                n = n.toPrecision(3);
            } else {
                n = n.toFixed(0);
            }
        }
        return n + unit;
    },

    delTag: function (tag) {
        $.ajax({
            type: "DELETE",
            url: this.tagUrl(tag),
            complete: function () {
                Page.refreshTags();
            }
        });
    },

    addTag: function (tag) {
        $.ajax({
            type: "PUT",
            url: this.tagUrl(tag),
            data: { '': '' }, // {bz: 4588}: Use an non-empty payload to avoid "411 Length required"
            complete: function (xhr) {
                Page.refreshTags();
                $('#st-tags-field').val('');
            }
        });
    }
};

})(jQuery);
