(function ($) {

var ST = window.ST = window.ST || {};

ST.Delete = function () { }
ST.Delete.prototype = new ST.Lightbox;

ST.Delete.prototype.deleteLightbox = function () {
    this.process('delete.tt2');
    $("#st-delete-newname").val(
        Socialtext.page_title
    );

    $.showLightbox({
        content: '#st-delete-lightbox',
        close: '#st-delete-lightbox .close'
    });

    $('#st-delete-lightbox .submit').click(function () {
        $(this).parents('form').submit();
    });
}

})(jQuery);

