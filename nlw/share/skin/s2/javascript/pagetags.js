if (typeof ST == 'undefined') {
    ST = {};
}

// St.Tags Class

ST.Tags = function (args) {
    $H(args).each(this._applyArgument.bind(this));

    var self = this;
    jQuery(function() {
        self._loadInterface();
    });
};


ST.Tags.prototype = {
    showTagField: false,
    workspaceTags: {},
    initialTags: {},
    suggestionRE: '',
    _deleted_tags: [],
    socialtextModifiers: {
        uri_escape: function (str) {
            return encodeURIComponent(str);
        },
        escapespecial : function(str) {
            var escapes = [
                { regex: /'/g, sub: "\\'" },
                { regex: /\n/g, sub: "\\n" },
                { regex: /\r/g, sub: "\\r" },
                { regex: /\t/g, sub: "\\t" }
            ];
            for (var i=0; i < escapes.length; i++)
                str = str.replace(escapes[i].regex, escapes[i].sub);
            return str;
        },
        quoter: function (str) {
            return str.replace(/"/g, '&quot;');
        },
        tagescapespecial : function(t) {
            var escapes = [
                { regex: /'/g, sub: "\\'" },
                { regex: /\n/g, sub: "\\n" },
                { regex: /\r/g, sub: "\\r" },
                { regex: /\t/g, sub: "\\t" }
            ];
            s = t.name;
            for (var i=0; i < escapes.length; i++)
                s = s.replace(escapes[i].regex, escapes[i].sub);
            return s;
        }
    },

    element: {
        workspaceTags: 'st-tags-workspace',
        tagName: 'st-tags-tagtemplate',
        tagSuggestion: 'st-tags-suggestiontemplate',
        addButton: 'st-tags-addbutton',
        displayAdd: 'st-tags-addlink',
        initialTags: 'st-tags-initial',
        tagField: 'st-tags-field',
        addInput: 'st-tags-addinput',
        addBlock: 'st-tags-addblock',
        message: 'st-tags-message',
        tagSuggestionList: 'st-tags-suggestionlist',
        suggestions: 'st-tags-suggestion',
        deleteTagsMessage: 'st-tags-deletemessage',
        noTagsPlaceholder: 'st-no-tags-placeholder'
    },

    jst: {
        name: '', // WAS TaglineTemplate
        suggestion: '' // WAS SuggestionFormat
    },

    displayListOfTags: function (tagfield_should_focus) {
        this.tagCollection.maxCount = this.workspaceTags.maxCount;
        var tagList = this.tagCollection;
        if (tagList.tags && tagList.tags.length > 0) {
            tagList._MODIFIERS = this.socialtextModifiers;
            this.tagCollection = tagList;

            // Tags might have raw html.
            for (var ii = 0; ii < tagList.tags.length ; ii++)
               tagList.tags[ii].name = html_escape( tagList.tags[ii].name );

            this.computeTagLevels();
            this.jst.name.update(tagList);
        } else {
            this.jst.name.clear();
        }

        if (this.showTagField) {
            Element.setStyle('st-tags-addinput', {display: 'block'});
            if (tagfield_should_focus) {
                tagField = $(this.element.tagField).focus();
            }
        }
        if ($('st-tags-message')) {
            Element.hide('st-tags-message');
        }
    },

    _copy_page_tags_to_master_list: function () {
        for (var i=0; i < this.tagCollection.tags.length; i++) {
            found = false;
            var tag = this.tagCollection.tags[i];
            var lctag = tag.name.toLowerCase();
            for (var j=0; j < this.workspaceTags.tags.length; j++) {
                if (this.workspaceTags.tags[j].name.toLowerCase() == lctag) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                this.workspaceTags.tags.push(tag);
            }
        }
    },

    decodeTagNames: function () {
        var tagList = this.tagCollection;
        for (i=0; i < tagList.tags.length; i++)
            tagList.tags[i].name = decodeURIComponent(tagList.tags[i].name);
    },

    computeTagLevels: function () {
        var tagList = this.tagCollection;
        var i=0;
        var maxWeight = tagList.maxCount;

        if (maxWeight < 10) {
            for (i=0; i < tagList.tags.length; i++)
                tagList.tags[i].level = 'st-tags-level2';
        }
        else {
            for (i=0; i < tagList.tags.length; i++) {
                var tagWeight = tagList.tags[i].page_count / maxWeight;
                if (tagWeight > 0.8)
                    tagList.tags[i].level = 'st-tags-level5';
                else if (tagWeight > 0.6)
                    tagList.tags[i].level = 'st-tags-level4';
                else if (tagWeight > 0.4)
                    tagList.tags[i].level = 'st-tags-level3';
                else if (tagWeight > 0.2)
                    tagList.tags[i].level = 'st-tags-level2';
                else
                    tagList.tags[i].level = 'st-tags-level1';
            }
        }
        this.tagCollection = tagList;
    },

    addTag: function (tagToAdd) {
        Element.hide(this.element.suggestions);
        tagToAdd = this._trim(tagToAdd);
        var tagField = $(this.element.tagField);
        if (tagToAdd.length == 0) {
            return;
        }
        this.showTagMessage(loc('Adding tag [_1]',  html_escape(tagToAdd)));
        var uri = Page.APIUriPageTag(tagToAdd);
        new Ajax.Request (
            uri,
            {
                method: 'post',
                requestHeaders: ['X-Http-Method','PUT'],
                onComplete: (function (req) {
                    this._remove_from_deleted_list(tagToAdd);
                    this.fetchTags();
                    if (Socialtext.page_type == 'wiki')
                        Page.refresh_page_content();
                }).bind(this),
                onFailure: (function(req, jsonHeader) {
                    this.resetDisplayOnError();
                }).bind(this)
            }
        );
        tagField.value = '';
    },

    addTagFromField: function () {
        this.addTag($(this.element.tagField).value);
    },

    displayAddTag: function () {
        this.showTagField = true;
        Element.setStyle(this.element.addInput, {display: 'block'});
        $(this.element.tagField).focus();
        Element.hide(this.element.addBlock);
    },

    _remove_from_deleted_list: function (tagToRemove) {
        this._deleted_tags.deleteElementIgnoreCase(tagToRemove);
        this._update_delete_list();
    },

    showTagMessage: function (msg) {
        Element.hide(this.element.addInput);
        Element.setStyle(this.element.message, {display: 'block'});
        Element.update(this.element.message, msg);
    },

    resetDisplayOnError: function() {
        if (this.showTagField) {
            Element.setStyle(this.element.addInput, {display: 'block'});
        }
        Element.hide(this.element.message);
        Element.update(this.element.message, '');
    },

    findSuggestions: function () {
        var field = $(this.element.tagField);

        if (field.value.length == 0) {
            Element.hide(this.element.suggestions);
        } else {
            if (this.workspaceTags.tags) {
                var expression = field.value;
                expression = expression.replace(/([+?.*\(\)\[\]])/g,"\\$1");
                this.suggestionRE = new RegExp(expression,'i');
                var suggestions = {
                    matches : this.workspaceTags.tags.grep(this.matchTag.bind(this))
                };
                Element.setStyle(this.element.suggestions, {display: 'block'});
                if (suggestions.matches.length > 0) {
                    suggestions._MODIFIERS = this.socialtextModifiers;
                    this.jst.suggestion.update(suggestions);
                } else {
                    var help = loc('<span class="st-tags-nomatch">No matches</span>');
                    this.jst.suggestion.set_text(help);
                }
            }
        }
    },

    matchTag: function (tag) {
        if (typeof tag.name == 'number') {
            var s = tag.name.toString();
            return s.search(this.suggestionRE) != -1;
        } else {
            return tag.name.search(this.suggestionRE) != -1;
        }
    },

    tagFieldKeyHandler: function (event) {
        var key;
        if (window.event) {
            key = event.keyCode;
        } else if (event.which) {
            key = event.which;
        }

        if (key == Event.KEY_RETURN) {
            this.addTagFromField();
            return false;
        } else if (key == Event.KEY_TAB) {
            return this.setFirstMatchingSuggestion();
        }
    },

    setFirstMatchingSuggestion: function () {
        var field = $(this.element.tagField);

        if (field.value.length > 0) {
            var suggestions = this.workspaceTags.tags.grep(this.matchTag.bind(this));
            if ((suggestions.length >= 1) && (field.value != suggestions[0].name)) {
                field.value = suggestions[0].name;
                return false;
            }
        }
        return true;
    },

    fetchTags: function () {
        var uri = Page.APIUriPageTags();
        var date = new Date();
        uri += '?iecacheworkaround=' + date.toLocaleTimeString();
        var ar = new Ajax.Request (
            uri,
            {
                method: 'get',
                requestHeaders: ['Accept','application/json'],
                onComplete: (function (req) {
                    this.tagCollection.tags = JSON.parse(req.responseText);

                    if (this.tagCollection.tags.length == 0) {
                        Element.show(this.element.noTagsPlaceholder);
                    } else {
                        Element.hide(this.element.noTagsPlaceholder);
                    }
                    this.decodeTagNames(); /* Thanks, IE */
                    this.displayListOfTags(false);
                    $(this.element.tagField).focus();
                }).bind(this),
                onFailure: (function(req, jsonHeader) {
                    this._deleted_tags.pop();
                    alert(loc('Could not remove tag'));
                    this.resetDisplayOnError();
                }).bind(this)
            }
        );
    },

    deleteTag: function (tagToDelete) {
        this.showTagMessage(loc('Removing tag [_1]', tagToDelete));
        this._deleted_tags.push(tagToDelete);

        var uri = Page.UriPageTagDelete(tagToDelete);
        var ar = new Ajax.Request (
            uri,
            {
                method: 'post',
                requestHeaders: ['X-Http-Method','DELETE'],
                onComplete: (function (req) {
                    this._update_delete_list();
                    this.fetchTags();
                }).bind(this),
                onFailure: (function(req, jsonHeader) {
                    this._deleted_tags.pop();
                    alert(loc('Could not remove tag'));
                    this.resetDisplayOnError();
                }).bind(this)
            }
        );
    },

    _update_delete_list: function () {
        if (this._deleted_tags.length > 0) {
            Element.update(this.element.deleteTagsMessage, loc('These tags have been removed:') +  ' ' + this._deleted_tags.join(', '));
            $(this.element.deleteTagsMessage).style.display = 'block';
        }
        else {
            Element.update(this.element.deleteTagsMessage, '');
            $(this.element.deleteTagsMessage).style.display = 'none';
        }
    },

    _applyArgument: function (arg) {
        if (typeof this[arg.key] != 'undefined') {
            this[arg.key] = arg.value;
        }
    },

    _trim: function (value) {
        // XXX Belongs in Scalar Utils?
        var ltrim = /\s*((\s*\S+)*)/;
        var rtrim = /((\s*\S+)*)\s*/;
        return value.replace(rtrim, "$1").replace(ltrim, "$1");
    },

    _loadInterface: function () {
        var self = this;
        this.jst.name = new ST.TemplateField(this.element.tagName, 'st-tags-listing');
        this.jst.suggestion = new ST.TemplateField(this.element.tagSuggestion, this.element.tagSuggestionList);

        this.workspaceTags  = JSON.parse($(this.element.workspaceTags).value);
        this.tagCollection = JSON.parse($(this.element.initialTags).value);

        jQuery("#" + this.element.addButton).click(function(e) {
            self.addTagFromField(e);
        });

        jQuery("#" + this.element.displayAdd).click(function(e) {
            self.displayAddTag(e);
        });

        jQuery("#" + this.element.tagField).bind("keyup", function(e) {
            self.findSuggestions(e);
        });

        jQuery("#" + this.element.tagField).bind("keydown", function(e) {
            self.tagFieldKeyHandler(e);
        });
    }

};
