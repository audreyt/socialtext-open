/*
 * Abstract class for a lookahead widget. A lookahead widget watches an &lt;input&gt; field
 * and presents the user with a list of suggested possible matches. Suggestion list is retrieved
 * using AJAX and the REST API.
 *
 * AJAX calls are asyncronous so as to not lock the browser and prevent the user from typing.
 * I could not determine a way to cancel an existing AJAX call so the class tracks which
 * AJAX call is the <i>active</i>. The class makes sure the suggestion list only contains
 * suggestions from the active AJAX call.
 */


/**
 * Constructor
 *
 * @param dialog_window lightbox dialog window
 * @param api API call to populate lookup window
 * @param edit_field_id CSS id for the workspace edit field
 * @param window_class CSS class for the drop down windod which contains the
 * suggestion list
 * @param suggestion_block_class CSS class for the suggestion block
 * @param suggestion_class CSS class for each suggestion
 * @param variable_name JS variable associated with the object
 */
LookaheadWidget = function(dialog_window, api, edit_field_id, window_class, suggestion_block_class, suggestion_class, variable_name) {
    this.apiCall = api;
    this.editFieldId = edit_field_id;
    this.editField = $(edit_field_id);

    this.variableName = variable_name;
    this.activeTransport = null;
    this.suggestions = [];
    this.hasFocus = false;
    this.mouseInSuggestion = false;
    this.suggestionYOffset = 2;

    this.suggestionWindowClass = window_class;
    this.suggestionClass = suggestion_class;
    this.suggestionBlockClass = suggestion_block_class;

    this.suggestionWindow = null;
    this.suggestionBlock = null;
    this.dialogWindow = dialog_window;
    this.previousText = '';

    // We have our own auto-complete, disable the browser's version
    this.editField.setAttribute('autocomplete', 'off');

    this._hookInterface();
}

/**
 * Update the edit field with the suggestion selected by the user
 */
LookaheadWidget.prototype.acceptSuggestion = function(suggestion) {
    this.activeTransport = null;
    this._hideSuggestionBlock();
    this.editField.value = suggestion;
    this.previousText = suggestion;
    return false;
}

/**
 * Build the URI for the API call to retrieve the suggestion list
 * @return URI string
 */
LookaheadWidget.prototype._apiURI = function () {
    var uri = this.apiCall;
    var connector = '?';
    var parameters = [this._getOrder(), this._getFilter(), this._getType()];
    for (i=0; i < parameters.length; i++) {
        if (parameters[i] != '') {
            uri += connector + parameters[i];
            connector = ';';
        }
    }

    return uri;
}

/**
 * Create the suggestion window and populate it with the suggestions from the API call
 */
LookaheadWidget.prototype._createSuggestionBlock = function () {
    if (this.suggestionWindow)
        return;

    this.suggestionWindow = document.createElement('div');
    this.suggestionWindow.id = 'st-widget-lookahead-window';

    this.suggestionWindow.className = this.suggestionWindowClass;
    this.suggestionWindow.style.height = "0px";
    this.suggestionWindow.style.overflow = "hidden";
    this.suggestionWindow.style.display = 'none';

    this.suggestionBlock = document.createElement('div');
    this.suggestionBlock.id = 'st-widget-lookahead-suggestionblock';
    this.suggestionBlock.className = this.suggestionBlockClass;
    this.suggestionWindow.appendChild(this.suggestionBlock);

    this.dialogWindow.appendChild(this.suggestionWindow);

    Event.observe(this.suggestionWindow, 'mouseover', this._mouseInSuggestion.bind(this), false);
    Event.observe(this.suggestionWindow, 'mouseout', this._mouseLeavingSuggestion.bind(this), false);
}

/**
 * Delete the suggestion window
 */
LookaheadWidget.prototype._deleteSuggestionWindow = function () {
    if (!this.suggestionWindow)
        return;

    this.suggestionWindow.removeChild(this.suggestionBlock);
    this.suggestionWindow.parentNode.removeChild(this.suggestionWindow);
    this.suggestionBlock = null;
    this.suggestionWindow = null;
}

/**
 * Escape the suggestion text so it works with HTML
 * @return Escaped suggestion text
 */
LookaheadWidget.prototype._escapedSuggestion = function (suggestion) {
    var escapes = [
        { regex: /'/g, sub: "\\'" },
        { regex: /\n/g, sub: "\\n" },
        { regex: /\r/g, sub: "\\r" },
        { regex: /\t/g, sub: "\\t" }
    ];
    for (var i=0; i < escapes.length; i++)
        suggestion = suggestion.replace(escapes[i].regex, escapes[i].sub);
    return suggestion.replace(/"/g, '&quot;');
}

LookaheadWidget.prototype._editIsEmpty = function () {
    this.activeTransport = null;
    this.suggestions = [];
    this._hideSuggestionBlock();
}

/**
 * Call the API and fetch the suggestion list
 */
LookaheadWidget.prototype._findSuggestions = function () {
    if (this.editField.value.length == 0) {
        this._editIsEmpty();
    }
    else {
        if (this.previousText != this.editField.value) {
            this.previousText = this.editField.value;
            try {
                var uri = this._apiURI();
                var id = this.activeId;
                var aj = new Ajax.Request();
                var request = new Ajax.Request (
                    uri,
                    {
                        method: 'get',
                        requestHeaders: ['Accept','text/plain'],
                        onComplete: (function (req) {
                            this.populateSuggestion(req);
                        }).bind(this),
                        onFailure: (function(req, jsonHeader) {
                        }).bind(this)
                    }
                );
                this.activeTransport = request.transport;
            }
            catch(e) {
                // XXX Ignore any error?
            }
        }
    }
}

/**
 * Called when the edit control gains focus.
 */
LookaheadWidget.prototype._gainFocus = function () {
    if (!this.hasFocus) {
        this.hasFocus = true;
        this.activeTransport = null;
        this._createSuggestionBlock();
        this._findSuggestions();
    }
},

/**
 * Build the filter criteria for the API call
 * @return Filter criteria string for the API URI
 */
LookaheadWidget.prototype._getFilter = function () {
    var filter = this.editField.value;
    filter = filter.replace(/^\s+/,'');
    filter = filter.replace(/ /g, '.*');
    return 'filter=\\b'+this.editField.value;
}

/**
 * Get the order clause for the API call. Default order is alpha
 * @return Order criteria string for the API URI
 */
LookaheadWidget.prototype._getOrder = function () {
    return 'order=alpha';
}

LookaheadWidget.prototype._getType = function () {
    if (this.pageType) return "type=" + this.pageType;
    return ""
}

/**
 * Hide the suggestion window
 */
LookaheadWidget.prototype._hideSuggestionBlock = function () {
    this.suggestionBlock.innerHTML = '';
    this.suggestionWindow.style.overflow = 'hidden';
    this.suggestionWindow.style.display = 'none';
    this.editField.focus();
}

/**
 * Add the JS event observers for the &lt;input&gt; field
 */
LookaheadWidget.prototype._hookInterface = function () {
    if ($(this.editFieldId)) {
        Event.observe(this.editFieldId, 'keyup', this._findSuggestions.bind(this));
        Event.observe(this.editFieldId, 'keydown', this._keyHandler.bind(this));
        Event.observe(this.editFieldId, 'blur', this._loseFocus.bind(this));
        Event.observe(this.editFieldId, 'focus', this._gainFocus.bind(this));
    }
}

/**
 * Called when a key is pressed when the edit field has the focus
 * @param event JS event object
 */
LookaheadWidget.prototype._keyHandler = function (event) {
    var e = event || window.event;
    var key = e.charCode || e.keyCode;

    if (key == Event.KEY_TAB && this._suggestionsDisplayed()) {
        this._hideSuggestionBlock();
        var ret = this._setFirstMatchingSuggestion();
    }
}

/**
 * Called when the input field loses focus. Default action is to hide the suggestion window
 */
LookaheadWidget.prototype._loseFocus = function() {
    if (this.hasFocus && !this.mouseInSuggestion) {
        this.hasFocus = false;
        this._deleteSuggestionWindow();
        this.activeTransport = null;
    }
}

/**
 * Called when the mouse enters the suggestion window.
 *
 * We need to track if the mouse is in the suggestion window to handle focus change. If
 * the mouse is in the suggestion window we don't want to hide the window from the user.
 */
LookaheadWidget.prototype._mouseInSuggestion = function() {
    this.mouseInSuggestion = true;
}

/**
 * Called when the mouse leaves the suggestion window.
 *
 * We need to track if the mouse is in the suggestion window to handle focus change. If
 * the mouse is in the suggestion window we don't want to hide the window from the user.
 */
LookaheadWidget.prototype._mouseLeavingSuggestion = function() {
    this.mouseInSuggestion = false;
}

/**
 * Parse the API return and build the suggestion list
 *
 * The suggestion list is cleared if it only contains one suggestion which matches
 * the contents of the edit field. No use showing the user what they have already typed.
 */
LookaheadWidget.prototype._parseSuggestionList = function(suggestions_text) {
    var text = trim(suggestions_text);
    if (text.length == 0)
        this.suggestions = [];
    else {
        this.suggestions = text.split("\n");
        while (this.suggestions[this.suggestions.length -1] == '')
            this.suggestions.pop();
    }
    if (this.suggestions.length == 1 && this.suggestions[0] == this.editField.value)
        this.suggestions.pop();
}

LookaheadWidget.prototype.isValidTransport = function(request) {
    if ((this.activeTransport != null && request != this.activeTransport) || !this.hasFocus)
        return false;
    else
        return true;
}

/**
 * Build the suggestion window and populate it with the suggestions from the API call
 */
LookaheadWidget.prototype.populateSuggestion = function(request) {

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

    if (this.suggestions.length == 0) {
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
            this._escapedSuggestion(this.suggestions[i]) +
            '\')">' +
            this.suggestions[i] +
            '</a>';
        if (i != this.suggestions.length - 1)
            suggestions_text += ',';
        suggestions_text += '</span> ';
    }
    this.suggestionBlock.innerHTML = suggestions_text;
    this._showSuggestionBlock();
}

/**
 * Select the first suggestion and update the edit field. This method is called if the user
 * presses tab while the suggestion window is displayed
 */
LookaheadWidget.prototype._setFirstMatchingSuggestion = function () {
    if (this.editField.value.length > 0 && this.suggestions.length > 0) {
        this.editField.value = this.suggestions[0];
        this._hideSuggestionBlock();
    }
    return true;
}

/**
 * Size, position, and display the suggestion window
 */
LookaheadWidget.prototype._showSuggestionBlock = function () {
    this.suggestionWindow.style.display = 'block';
    this.suggestionWindow.height = '1px';
    this.suggestionWindow.style.overflow = 'hidden';
    this.suggestionWindow.style.position = 'absolute';

    this.suggestionWindow.style.left = ST.getDocumentX(this.editField,true) + "px";
    this.suggestionWindow.style.top =
        ST.getDocumentY(this.editField,true) +
        this.editField.offsetHeight +
        this.suggestionYOffset + "px";
    this.suggestionWindow.style.width = this.editField.offsetWidth + "px";
    if (this.suggestionBlock.offsetHeight > 200) {
        this.suggestionWindow.style.height = "200px";
    }
    else {
        this.suggestionWindow.style.height = this.suggestionBlock.offsetHeight + 2 + "px";
    }
    this.suggestionWindow.style.overflow = "auto";
}

/**
 * Determine if the suggestion window is being displayed
 *
 * @return bool
 */
LookaheadWidget.prototype._suggestionsDisplayed = function (message) {
    return this.suggestionWindow.offsetHeight != 0;
}

/**
 * Replace tokens in the API URI with the appropriate values
 *
 * @return modified API URI
 */
LookaheadWidget.prototype._tokenReplace = function(command, token, value) {
    if (!this.workspace)
        throw URIError('No workspace to query');

    var re = new RegExp(token);
    if (command.match(re))
        command = command.replace(re, value);

    return command;
}
