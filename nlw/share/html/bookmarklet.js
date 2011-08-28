function updateDynamicLink(e) {
    var workspaces = $('workspace-list');
    var link = $('dynamic-link');
    var chosen_workspace_names = [];
    var chosen_workspace_titles = [];
    var chosen_label = '';
    forEach(workspaces.options, function(option) {
        if (option.selected) {
            chosen_workspace_names.push(option.value);
            chosen_workspace_titles.push(option.innerHTML);
        }
    });
    chosen_label = (chosen_workspace_titles.length == 0) ? '' : (chosen_workspace_titles.length == 1) ? chosen_workspace_titles[0] : chosen_workspace_titles.slice(0, -1).join(', ') + ' and ' + chosen_workspace_titles[chosen_workspace_titles.length - 1];
    link.href = "javascript:(function(){w='" + chosen_workspace_names.join('%20OR%20') + "';q=prompt('Search " + chosen_label + " for:');if(q) location.href='http://www3.socialtext.net/search?q=' + escape(q) + '%20AND%20(' + escape(w) + ')';})()";
    link.innerHTML = 'Search ' + chosen_label;
}

addLoadEvent(function(){connect('workspace-list', 'onchange', updateDynamicLink);});