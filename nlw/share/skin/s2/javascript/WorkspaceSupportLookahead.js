/**
 * Abstract class for lookahead widgets whose suggestions are workspace specific (such as page name).
 *
 * @see LookaheadWidget
 * @see ST.extend
 */


/**
 * Constructor
 *
 * @param dialog_window lightbox dialog window
 * @param api API call to retrieve suggestion list
 * @param edit_field_id CSS id for the workspace edit field
 * @param window_class CSS class for the drop down windod which contains the suggestion list
 * @param suggestion_block_class CSS class for the suggestion block
 * @param suggestion_class CSS class for each suggestion
 * @param variable_name JS variable associated with the object
 * @param widget Wikiwyg widget
 */
WorkspaceSupportLookahead = function(dialog_window, api, edit_field_id, window_class, suggestion_block_class, suggestion_class, variable_name, widget) {
	WorkspaceSupportLookahead.baseConstructor.call(
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
    this.workspaceWidget = widget;
    this.defaultWorkspace = '';
};

ST.extend(WorkspaceSupportLookahead, LookaheadWidget);

WorkspaceSupportLookahead.prototype.currentWorkspaceSelected = function () {
    var nodes = document.getElementsByName('st-rb-workspace_id');
    for (var i = 0; i < nodes.length; i++)
        if (nodes[i].checked)
            return nodes[i].value == 'current';
    return false;
}

/**
 * Get latest workspace data when control gains focus
 */
WorkspaceSupportLookahead.prototype._gainFocus = function() {
    this.workspace = this.defaultWorkspace;
    if (!this.currentWorkspaceSelected())
        if (this.workspaceWidget && this.workspaceWidget.title_and_id.workspace_id.id)
            this.workspace = this.workspaceWidget.title_and_id.workspace_id.id;

    WorkspaceSupportLookahead.superClass._gainFocus.call(this)
},

/**
 * Message to return when a 404 status code is returned by the API
 * @return Error message in HTML format
 */
WorkspaceSupportLookahead.prototype._error404Message = function() {
    return '<span class="st-suggestion-warning">' + loc('Workspace "[_1]" does not exist on wiki', this.workspace) + '</span>';
}

/**
 * Build the URI for the API call
 * @return URI for API call
 */
WorkspaceSupportLookahead.prototype._apiURI = function() {
    var uri = WorkspaceSupportLookahead.superClass._apiURI.call(this)
    return this._tokenReplace(uri, ':ws', this.workspace);
}
