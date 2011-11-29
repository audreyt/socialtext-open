(function($) {

var t = new Test.Visual();

t.plan(10);

t.runAsync([
    function() {
        t.open_iframe('/admin?Announcements and links', t.nextStep());
    },

    function() {
        var Page = t.win.Page;

        t.ok(Page, 'Page object exists');
        t.ok(
            Page.active_page_exists('Announcements and links'),
            'active_page_exists'
        );
        t.is(
            Page.pageUrl('workspace1', 'page2'),
            '/data/workspaces/workspace1/pages/page2',
            'pageUrl with workspace and page_id'
        );
        t.is(
            Page.pageUrl('page2'),
            '/data/workspaces/admin/pages/page2',
            'pageUrl with only page_id'
        );
        t.is(
            Page.pageUrl(),
            '/data/workspaces/admin/pages/announcements_and_links',
            'pageUrl with no args'
        );

        t.is(
            Page.restApiUri('workspace1', 'page2'),
            '/data/workspaces/workspace1/pages/page2',
            'restApiUri with workspace and page_id args'
        );
        t.is(
            Page.restApiUri('page2'),
            '/data/workspaces/admin/pages/page2',
            'restApiUri with only page_id arg'
        );
        t.is(
            Page.restApiUri(),
            '/data/workspaces/admin/pages/announcements_and_links',
            'restApiUri with no args'
        );

        t.is(
            Page.workspaceUrl('workspace1'),
            '/data/workspaces/workspace1',
            'workspaceUrl with workspace arg'
        );
        t.is(
            Page.workspaceUrl(),
            '/data/workspaces/admin',
            'workspaceUrl with no args'
        );

        t.endAsync();
    }
]);

})(jQuery);
