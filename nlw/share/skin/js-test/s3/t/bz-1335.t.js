(function($) {

var t = new Test.Visual();

t.plan(1);

var iframeHeight;

var pageName = 'bz_1335_' + t.gensym();

t.runAsync([
    function() {
        t.open_iframe( "/admin/index.cgi?how_do_i_make_a_new_page", t.nextStep() );
    },
            
    function() { 
        t.$('#st-pagetools-duplicate').click();
        t.callNextStep(1500);
    },

    function() { 
        t.$('#st-duplicate-newname').val(pageName);
        t.$('#st-duplicate-form').submit();

        t.open_iframe( "/admin/index.cgi?" + pageName, t.nextStep(3000) );
    },

    function() {
        t.scrollTo(200);
        t.win.Page.setPageContent('Replace me');
        t.$('#st-attachment-listing li:first a').click();

        t.poll(function() {
            return t.$('#st-attachment-delete').is(':visible');
        }, function() {t.callNextStep(1500);});
    },

    function() {
        t.$('#st-attachment-delete').click();
        t.callNextStep(7500);
    },

    function() { 
        t.isnt(
            t.$('#st-page-content').html(),
            'Replace me',
            'Deleting an attachment image should refresh page content'
        );

        t.endAsync();
    }
]);

})(jQuery);
