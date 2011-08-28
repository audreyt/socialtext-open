/**
 * Class to implement a tag name lookahead widget
 *
 * @see WorkspaceSupportLookahead
 * @see ST.extend
 */


/**
 * Constructor
 *
 * @param dialog_window lightbox dialog window
 * @param edit_field_id CSS id for the input tag
 * @param window_class CSS class to apply to the div for the suggestion window
 * @param suggestion_block_class CSS class for the div that holds the suggestion list
 * @param suggestion_class CSS class for a suggestion
 * @param variable_name name of JS variable that holds the object
 * @param workspace_id CSS id for the workspace edit field
 *
 */
TagLookahead = function(dialog_window, edit_field_id, window_class, suggestion_block_class, suggestion_class, variable_name, workspace_id) {
	TagLookahead.baseConstructor.call(
        this,
        dialog_window,
        '/data/workspaces/:ws/tags',
        edit_field_id,
		window_class,
		suggestion_block_class,
		suggestion_class,
		variable_name,
        workspace_id
    );
};

ST.extend(TagLookahead, WorkspaceSupportLookahead);

/**
 * Message to display when an API error occurs
 * @return Error message in HTML format
 */
TagLookahead.prototype._apiErrorMessage = function() {
    return '<span class="st-suggestion-warning">' + loc('Could not retrieve tag list from wiki') + '</span>';
}

/**
 * Get the sort order for the suggestions
 * @return sort order parameter string for the API call
 */
TagLookahead.prototype._getOrder = function () {
    return 'order=weighted';
}
