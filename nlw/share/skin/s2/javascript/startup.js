(function() {

return;

if (Socialtext.box_javascript) {
    createPageObject();

    if (ST.Attachments) window.Attachments = new ST.Attachments ();
    if (ST.Tags) window.Tags = new ST.Tags ();
    if (ST.TagQueue) window.TagQueue = new ST.TagQueue ();
    if (ST.Watchlist) window.Watchlist = new ST.Watchlist();

    jQuery(function() {
        window.Watchlist._loadInterface('st-watchlist-indicator');
    });
}

window.NavBar = new ST.NavBar ();

jQuery(function() {
    if (ST.Watchlist)
    jQuery('.watchlist-list-toggle').each(function() {
        var page_id = this.getAttribute('alt');
        var wl = new ST.Watchlist();
        wl.page_id = page_id;
        wl._loadInterface(this);
    });
    ST.hookCssUpload();

});

})();
