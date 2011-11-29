(function ($) {

if (typeof(Socialtext) == 'undefined') Socialtext = {};

Socialtext.getStickySearch = function () {
    var cookie = Cookie.get('stickysearch');
    return cookie ? $.evalJSON(cookie) : {};
}

Socialtext.stickySearch = function (args) {
    var settings = {
        // Defaults:
        workspaces: 'search_workspaces',
        workspace: 'search_workspace',
        people: 'search_people',
        dashboard: 'search_signals',
        groups: 'search_groups',
        explore: 'search_signals',
        signals: 'search_signals'
    };
        
    if (!!args.sticky) {
        $.extend(settings, Socialtext.getStickySearch());
        $('.searchSelect').change(function () {
            var orig = Socialtext.getStickySearch();
            orig[args.scope] = $(this).find('option:selected').val();
            Cookie.set('stickysearch', $.toJSON(orig), undefined, '/');
        });
    }

    $('.searchSelect').val(settings[args.scope])
};

})(jQuery);
