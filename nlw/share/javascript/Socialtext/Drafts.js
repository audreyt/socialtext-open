Socialtext.prototype.drafts = (function($){
    var _autoSaveKey;
    var _autoSaveIntervalId;

    function _with_drafts(cb) {
        if (typeof localStorage == 'undefined') return;

        var drafts;
        try {
            drafts = $.secureEvalJSON(
                localStorage.getItem('st-drafts-' + st.viewer.user_id
            ) || "{}");
        } catch (e) {};

        if (drafts) {
            cb(drafts);
        }

        try {
            localStorage.setItem(
                'st-drafts-' + st.viewer.user_id, $.toJSON(drafts)
            );
        } catch (e) {};
    }

    return {
        startAutoSave: function(get_content) {
            var self = this;
            if (typeof localStorage == 'undefined') { return; }
            _autoSaveIntervalId = setInterval(function() {
                self.saveDraftWithContent(get_content());
            }, 25 * 1000);
        },

        saveDraftWithContent: function(content) {
            if (!(content && content.length)) { return; }

            if (!_autoSaveKey) {
                _autoSaveKey = (new Date()).getTime();
            }

            _with_drafts(function(drafts) {
                drafts[_autoSaveKey] = {
                    page_title: $('#st-newpage-pagename-edit').val() || $('#st-page-editing-pagename').val(),
                    workspace_id: st.workspace.name,
                    workspace_title: st.workspace.title,
                    revision_id: st.page.revision_id,
                    page_type: st.page.type,
                    content: content,
                    tags: $('input[name=add_tag]').map(function(){
                        return $(this).val()}
                    ).toArray(),
                    attachments: st.attachments.get_new_attachments(),
                    last_updated: (new Date()).getTime(),
                    is_new_page: Socialtext.new_page
                };
            });
        },

        maybeLoadDraft: function(cb) {
            _autoSaveKey = null;
            _with_drafts(function(drafts) {
                if (!(location.hash && /^#draft-\d+$/.test(location.hash))) {
                    return;
                }

                var key = location.hash.toString().replace(/^#draft-/, '');
                var draft = drafts[key];
                if (!draft) { return; }

                _autoSaveKey = key;
                Socialtext.revision_id = draft.revision_id;
                Socialtext.wikiwyg_variables.page.revision_id = draft.revision_id;
                $('#st-page-editing-revisionid').val(draft.revision_id);

                $.each((draft.attachments || []), function () {
                    if (this.deleted) { return; }
                    st.attachments.addNewAttachment(this);
                });
                $.each((draft.tags || []), function () {
                    st.editor.addNewTag(this);
                });

                cb(draft);
            });
        },

        discardDraft:  function(event_type) {
            if (_autoSaveIntervalId) {
                clearInterval(_autoSaveIntervalId);
            }

            if (!_autoSaveKey) { return; }

            _with_drafts(function(drafts) {
                var keys_to_delete = [];
                var page_title = $('#st-newpage-pagename-edit').val() || $('#st-page-editing-pagename').val();
                var workspace_id = st.workspace.name;
                for (var key in drafts) {
                    if (_autoSaveKey == key) {
                        keys_to_delete.push(key);
                    }
                    else if (
                        (event_type == 'edit_save')
                        && (drafts[key].page_title == page_title)
                        && (drafts[key].workspace_id == workspace_id)
                    ) {
                        keys_to_delete.push(key);
                    }
                }
                for (var i = 0; i < keys_to_delete.length; i++) {
                    delete drafts[keys_to_delete[i]];
                }
            });
        }
    }
})(jQuery);
