/**
 * This class handles look ahead for page attachments. The class supports specifying workspace
 * and page edit fields and will use those values when pulling attachments.
 *
 * @see PageNameSupportLookahead
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
 * @param workspace_id CSS id for the workspace input tag
 * @param pagename_id CSS id for the page name input tag
 */
PageAttachmentLookahead = function(dialog_window, edit_field_id, window_class, suggestion_block_class, suggestion_class, variable_name, workspace_id, pagename_id) {
	PageAttachmentLookahead.baseConstructor.call(
        this,
        dialog_window,
        '/data/workspaces/:ws/pages/:pname/attachments',
        edit_field_id,
		window_class,
		suggestion_block_class,
		suggestion_class,
        variable_name,
        workspace_id,
        pagename_id
    );
};

ST.extend(PageAttachmentLookahead, PageNameSupportLookahead);

/**
 * Messge to display in case of an API error
 *
 * @return html string
 */
PageAttachmentLookahead.prototype._apiErrorMessage = function() {
    return '<span class="st-suggestion-warning">' + loc('Could not retrieve attachment list from wiki') + '</span>';
}
