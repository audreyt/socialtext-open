/**
 * This class is a base class for all look ahead widgets that pull suggestions from a specific
 * wiki page. The class supports specifying workspace and page name input fields and will use
 * that information when pulling suggestions.
 *
 * You can set the default workspace id using the workspace data member
 *
 * You can set the default page name using the pagename data member
 *
 * @see LookaheadWidget
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
 * @param workspace_widget Wikiwyg Workspace widget object
 * @param pagename_id CSS id for the page name input tag
 */
PageNameSupportLookahead = function(dialog_window, api, edit_field_id, window_class, suggestion_block_class, suggestion_class, variable_name, workspace_widget, pagename_id) {
	PageNameSupportLookahead.baseConstructor.call(
        this,
        dialog_window,
        api,
        edit_field_id,
        window_class,
        suggestion_block_class,
        suggestion_class,
        variable_name
    );
    this.workspace = '';
    this.workspaceWidget = workspace_widget;
    this.defaultWorkspace = '';

    this.pagename = '';
    this.pagenameId = pagename_id;
    this.defaultPagename = '';
};

ST.extend(PageNameSupportLookahead, LookaheadWidget);

PageNameSupportLookahead.prototype.currentWorkspaceSelected = function () {
    var nodes = document.getElementsByName('st-rb-workspace_id');
    for (var i = 0; i < nodes.length; i++)
        if (nodes[i].checked)
            return nodes[i].value == 'current';
    return false;
}

PageNameSupportLookahead.prototype.currentPageSelected = function () {
    var nodes = document.getElementsByName('st-rb-page_title');
    for (var i = 0; i < nodes.length; i++)
        if (nodes[i].checked)
            return nodes[i].value == 'current';
    return false;
}

/**
 * When the edit field gains focus update the workspace and page name fields
 * from the values in the form
 */
PageNameSupportLookahead.prototype._gainFocus = function() {
	try {
		this.workspace = this.defaultWorkspace;
	    if (!this.currentWorkspaceSelected())
	        if (this.workspaceWidget && this.workspaceWidget.title_and_id.workspace_id.id)
	            this.workspace = this.workspaceWidget.title_and_id.workspace_id.id;

		this.pagename = this.defaultPagename;
	    if (!this.currentPageSelected())
			if (this.pagenameId && trim($(this.pagenameId).value))
				this.pagename = trim($(this.pagenameId).value);
	}
	catch(e) {
		this.pagename = '';
		this.workspace = '';
	}
    PageNameSupportLookahead.superClass._gainFocus.call(this)
},

/**
 * Get the error message to display when the API returns a 404 error
 * @return error message in HTML format
 */
PageNameSupportLookahead.prototype._error404Message = function() {
    return '<span class="st-suggestion-warning">' + loc('Workspace "[_1]" or page "[_2]" does not exist on wiki', this.workspace, this.pagename) + '</span>';
}

/**
 * Build the URI for the API call
 * @return URI
 */
PageNameSupportLookahead.prototype._apiURI = function() {
    var uri = PageNameSupportLookahead.superClass._apiURI.call(this)
    uri = this._tokenReplace(uri, ':ws', this.workspace);
    return this._tokenReplace(uri, ':pname', this.pagename);
}
