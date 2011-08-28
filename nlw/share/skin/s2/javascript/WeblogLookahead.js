/**
 * This class handles look ahead for Weblog name fields. This is a tag look ahead with a
 * different filter (tags must end with blog
 *
 * @see TagLookahead
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
WeblogLookahead = function(dialog_window, edit_field_id, window_class, suggestion_block_class, suggestion_class, variable_name, workspace_id) {
	WeblogLookahead.baseConstructor.call(
        this,
        dialog_window,
        edit_field_id,
		window_class,
		suggestion_block_class,
		suggestion_class,
		variable_name,
        workspace_id
    );
};

ST.extend(WeblogLookahead, TagLookahead);

/**
 * Constructs the regex used to filter the tag list
 *
 * @return filter criteria string
 */
WeblogLookahead.prototype._getFilter = function () {
    return 'filter=\\b'+this.editField.value+'.*(We)?blog$';
}

/**
 * Messge to display in case of an API error
 *
 * @return html string
 */
WeblogLookahead.prototype._apiErrorMessage = function() {
    return '<span class="st-suggestion-warning">' + loc('Could not retrieve weblog list from wiki') + '</span>';
}
