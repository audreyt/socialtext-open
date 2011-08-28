/**
 * This class implements a workspace lookahead widget.
 *
 * @see LookaheadWidget
 * @see ST.Extend
 */

/**
 * Constructor
 *
 * @param dialog_window lightbox dialog window
 * @param edit_field_id CSS id for the workspace edit field
 * @param window_class CSS class for the drop down windod which contains the
 * suggestion list
 * @param suggestion_block_class CSS class for the suggestion block
 * @param suggestion_class CSS class for each suggestion
 * @param variable_name JS variable associated with the object
 * @param widget Wikiwyg widget
 */
WorkspaceLookahead = function(dialog_window, edit_field_id, window_class, suggestion_block_class, suggestion_class, variable_name, widget) {
    WorkspaceLookahead.baseConstructor.call(
        this,
        dialog_window,
        '/data/workspaces',
        edit_field_id,
        window_class,
        suggestion_block_class,
        suggestion_class,
        variable_name
    );
    this.widget = widget;
    this.setTitleFromId();
    this.perfectMatch = false;
};

ST.extend(WorkspaceLookahead, LookaheadWidget);

/**
 * Update the wikiwyg widget and the workspace edit field with the user selection
 */
WorkspaceLookahead.prototype.acceptSuggestion = function(suggestion) {
    this.activeTransport = null;
    this._hideSuggestionBlock();
    this.widget.title_and_id.workspace_id.id = suggestion;
    this.widget.title_and_id.workspace_id.title = this.getTitleFromName(suggestion);
    this.editField.value = this.widget.title_and_id.workspace_id.title;
    this.previousText = this.widget.title_and_id.workspace_id.title;
    return false;
}

/**
 * Retrieves the title for a workspace name from the suggestion list returned
 * by the API.
 *
 * @param name workspace name
 * @return workspace title
 */
WorkspaceLookahead.prototype.getTitleFromName = function(name) {
    var title = '';
    for (var i=0; i < this.suggestions.length; i++) {
        if (this.suggestions[i].name == name) {
            title = this.suggestions[i].title;
            break;
        }
    }

    return title;
}

/**
 * Message to display when an API error occurs
 * @return Error message in HTML format
 */
WorkspaceLookahead.prototype._apiErrorMessage = function() {
    return '<span class="st-suggestion-warning">' + loc('Could not retrieve workspace list from wiki') + '</span>';
}

/**
 * Message to return when a 404 status code is returned by the API
 * @return Error message in HTML format
 */
WorkspaceLookahead.prototype._error404Message = function() {
    return this._apiErrorMessage();
}

/**
 * If the user cleared the workspace edit field reset the value to default
 * @return Nothing
 */
WorkspaceLookahead.prototype._editIsEmpty = function () {
    this.widget.title_and_id.workspace_id.id = '';
    this.widget.title_and_id.workspace_id.title = '';
    WorkspaceLookahead.superClass._editIsEmpty.call(this);
}

/**
 * Fetch the list of workspaces that match the user's string
 */
WorkspaceLookahead.prototype._findSuggestions = function () {
    if (this.editField.value.length == 0) {
        this._editIsEmpty();
    }
    else {
        if (this.previousText != this.editField.value) {
            this.previousText = this.editField.value;
            var uri = this._apiURI();
            var id = this.activeId;
            var aj = new Ajax.Request();
            var request = new Ajax.Request (
                uri,
                {
                    method: 'get',
                    requestHeaders: ['Accept','application/json'],
                    onComplete: (function (req) {
                        this.populateSuggestion(req);
                    }).bind(this),
                    onFailure: (function(req, jsonHeader) {
                        // XXX Need an error messaage
                    }).bind(this)
                }
            );
            this.activeTransport = request.transport;
        }
    }
}

/**
 * Since only the id for the workspace is saved with the widget
 * we need to pull the name of the workspace to display to the
 * end user
 * @return Nothing
 */
WorkspaceLookahead.prototype.setTitleFromId = function () {
    var radioName = this.editFieldId + '-rb';
    if (!this.widget.title_and_id.workspace_id.id) {
        ST.setRadioValue(radioName, 'current');
    }
    else {
        ST.setRadioValue(radioName, 'other');
        this.editField.value = this.widget.title_and_id.workspace_id.title;
    }
}

/**
 * Build the title filter for the workspace API call
 * @return Filter clause of the API call
 */
WorkspaceLookahead.prototype._getFilter = function () {
    var filter = this.editField.value;
    filter = filter.replace(/^\s+/,'');
    filter = filter.replace(/ /g, '.*');
    return 'title_filter=\\b'+this.editField.value;
}

/**
 * Parse the API return and build out the suggestion list. The suggestion
 * list is cleared if only one suggestion is returned and it matches what the
 * user has entered. This prevents the lookahead component from displaying the
 * single suggestion in the dropdown list.
 */
WorkspaceLookahead.prototype._parseSuggestionList = function(suggestions_text) {
    this.suggestions = [];
    var text = trim(suggestions_text);
    if (text.length != 0)
        this.suggestions = JSON.parse(text);

    var re = new RegExp('^'+this.editField.value+'$', 'i');
    if (this.suggestions.length == 1 && this.suggestions[0].title.match(re)) {
        this.widget.title_and_id.workspace_id.id = this.suggestions[0].name;
        this.suggestions.pop();
        this.perfectMatch = true;
    }
    else
        this.perfectMatch = false;
}

/**
 * Called by the AJAX request. Parse the return from the AJAX call and display
 * the suggestion window if required.
 */
WorkspaceLookahead.prototype.populateSuggestion = function(request) {
    if (!this.isValidTransport(request))
        return;

    if (request.status != 200) {
        if (request.status == 404) {
            this.suggestionBlock.innerHTML = this._error404Message();
        }
        else {
            this.suggestionBlock.innerHTML = this._apiErrorMessage();
        }
        this._showSuggestionBlock();
        return;
    }

    this._parseSuggestionList(request.responseText);
    if (!this.hasFocus) {
        this.activeTransport = null;
        return;
    }

    if (this.suggestions.length == 0) {
        if (!this.perfectMatch) {
            this.widget.title_and_id.workspace_id.id = this.editField.value;
            this.widget.title_and_id.workspace_id.title = this.editField.value;
        }
        this.suggestionBlock.innerHTML = '';
        this._hideSuggestionBlock();
        return;
    }

    var suggestions_text = '';
    for (var i=0; i < this.suggestions.length; i++) {
        suggestions_text +=
            '<span class="' +
            this.suggestionClass +
            '"><a href="#" onclick="return ' + this.variableName + '.acceptSuggestion(\'' +
            this._escapedSuggestion(this.suggestions[i].name) +
            '\')">' +
            this.suggestions[i].title + ' (' + this.suggestions[i].name + ')' +
            '</a>';
        if (i != this.suggestions.length - 1)
            suggestions_text += ',';
        suggestions_text += '</span> ';
    }

    if (this.suggestionBlock == null)
        this._createSuggestionBlock();

    this.suggestionBlock.innerHTML = suggestions_text;

    this._showSuggestionBlock();
}

/**
 * If the user types in the workspace field then we automatically select the 'custom' radio button
 */
WorkspaceLookahead.prototype._keyHandler = function (event) {
    var radioName = this.editFieldId + '-rb';
    ST.setRadioValue(radioName, 'other');
    WorkspaceLookahead.superClass._keyHandler.call(this, event);
}

/**
 * Selects the first available suggestion. Called when the user presses tab and
 * the suggestion window is visible.
 * @return true
 */
WorkspaceLookahead.prototype._setFirstMatchingSuggestion = function () {
    if (this.editField.value.length > 0 && this.suggestions.length > 0) {
        this.acceptSuggestion(this.suggestions[0].name);
    }
    return true;
}

WorkspaceLookahead.prototype.isValidTransport = function(request) {
    if ((this.activeTransport != null && request != this.activeTransport))
        return false;
    else
        return true;
}

/**
 * We need to override the default handling to capture the last call so we can update
 * the ID if appropriate
 */
WorkspaceLookahead.prototype._loseFocus = function() {
    if (this.hasFocus && !this.mouseInSuggestion) {
        this.hasFocus = false;
        this._deleteSuggestionWindow();
//        this.activeTransport = null;
    }
}
