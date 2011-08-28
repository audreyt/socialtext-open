(function ($) {

var ST = window.ST = window.ST || {};

ST.Duplicate = function () { }
ST.Duplicate.prototype = new ST.Lightbox;

ST.Duplicate.prototype.duplicateLightbox = function () {
    this.process('duplicate.tt2');
    this.sel = '#st-duplicate-lightbox';
    $("#st-duplicate-newname").val(
        loc('page.duplicate=title', Socialtext.page_title)
    );
    this.show(
        true, // Do redirection
        function() {
            $("#st-duplicate-newname").select().focus();
        }
    );
}

})(jQuery);
