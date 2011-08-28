(function ($) {

var ST = window.ST = window.ST || {};

ST.Rename = function () { }
ST.Rename.prototype = new ST.Lightbox;

ST.Rename.prototype.renameLightbox = function () {
    this.process('rename.tt2');
    this.sel = '#st-rename-lightbox';
    $("#st-rename-newname").val(
        Socialtext.page_title
    );
    this.show(
        true, // Do redirection
        function() {
            $("#st-rename-newname").select().focus();
        }
    );
}

})(jQuery);

