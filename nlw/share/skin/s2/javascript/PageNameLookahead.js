/**
 * This class handles look ahead for page names. The class supports specifying a workspace
 * will pull page names from that workspace.
 */

// namespace placeholder
if (typeof ST == 'undefined') {
    ST = {};
}

ST.lookaheadCache = { workspacePageCount: {} };

/**
 * Constructor
 *
 * @param dialog_window lightbox dialog window
 * @param edit_field_id CSS id for the input tag
 * @param window_class CSS class to apply to the div for the suggestion window
 * @param suggestion_block_class CSS class for the div that holds the suggestion list
 * @param suggestion_class CSS class for a suggestion
 * @param variable_name name of JS variable that holds the object
 * @param workspace_id CSS id for the workspace input tag
 */
PageNameLookahead = function(dialog_window, edit_field_id, window_class, suggestion_block_class, suggestion_class, variable_name, workspace_id) {
    PageNameLookahead.baseConstructor.call(
        this,
        dialog_window,
        '/data/workspaces/:ws/pages',
        edit_field_id,
        window_class,
        suggestion_block_class,
        suggestion_class,
        variable_name,
        workspace_id
    );

    this.lastEditLength = 0;
    this.minEditLengthForLookup = 1;
    var radioName = this.editFieldId + '-rb';
    this.setMinEditLengthForLookup();

    if (this.editField.value.length == 0)
        ST.setRadioValue(radioName, 'current');
    else
        ST.setRadioValue(radioName, 'other');
};

ST.extend(PageNameLookahead, WorkspaceSupportLookahead);

/**
 * Override the _get_order method to return an empty string; the sections API call returns
 * items in page order by default.
 *
 * @return blank string
 */
PageNameLookahead.prototype._apiErrorMessage = function() {
    return '<span class="st-suggestion-warning">Could not retrieve page list from wiki</span>';
}

PageNameLookahead.prototype.getPageCountForWorkspace = function() {
    if (this.workspace == '')
        return 1;
    if (this.workspace in ST.lookaheadCache.workspacePageCount)
        return ST.lookaheadCache.workspacePageCount[this.workspace];

    var uri = '/data/workspaces/'+this.workspace+'/tags/recent changes';

    var request = new Ajax.Request (
        uri,
        {
            method: 'get',
            asynchronous: false,
            requestHeaders: ['Accept','application/json']
        }
    );

    if (request.transport.status == 200) {
        var details = JSON.parse(request.transport.responseText);
        ST.lookaheadCache.workspacePageCount[this.workspace] = details.page_count;
        return details.page_count;
    }

    return 0;
}

PageNameLookahead.prototype.setMinEditLengthForLookup = function() {
    var pageCount = this.getPageCountForWorkspace();
    if (pageCount < 5000)
        this.minEditLengthForLookup = 1;
    else if (pageCount < 10000)
        this.minEditLengthForLookup = 2;
    else
        this.minEditLengthForLookup = 3;
}

/**
 * We auto-select the current page radio button when the user clears the page title field
 */
PageNameLookahead.prototype._editIsEmpty = function () {
    PageNameLookahead.superClass._editIsEmpty.call(this);
}

/**
 * If the user types in the page title field then we automatically select the 'custom' radio button
 */
PageNameLookahead.prototype._keyHandler = function (event) {
    var radioName = this.editFieldId + '-rb';
    ST.setRadioValue(radioName, 'other');
    PageNameLookahead.superClass._keyHandler.call(this, event);
}

/**
 * We only want to handle a lookahead if the user has typed a minimum number of characters
 */
PageNameLookahead.prototype._findSuggestions = function () {
    if (this.editField.value.length == 0 || this.editField.value.length >= this.minEditLengthForLookup) {
        if (this.lastEditLength > 0 && this.lastEditLength < this.minEditLengthForLookup)
            this.suggestionBlock.innerHTML = '<span class="st-lookahead-info">' + loc('Searching for matching pages...') + '</span>';
        PageNameLookahead.superClass._findSuggestions.call(this);
    }
    else {
        this.suggestionBlock.innerHTML = '<span class="st-lookahead-info">' + loc('Page title lookahead requires at least [_1] characters', this.minEditLengthForLookup) + '</span>';
        this._showSuggestionBlock();
    }
    this.lastEditLength = this.editField.value.length;
}

/**
 * Get latest workspace data when control gains focus
 */
PageNameLookahead.prototype._gainFocus = function() {
    PageNameLookahead.superClass._gainFocus.call(this)
    this.setMinEditLengthForLookup();
}
