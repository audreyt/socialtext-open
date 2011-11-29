var ST = window.ST = window.ST || {};
(function ($) {

ST.SimpleLightbox = function () {};
ST.SimpleLightbox.prototype = {
    show: function (title, msg, cb) {
        $.showLightbox({
            html: Jemplate.process('simple.tt2', { loc: loc, msg: msg, title: title }),
            close: '#simple-lightbox .close'
        });
        
        if ($.isFunction(cb)) {
            $('#simple-lightbox .close').unbind('click').click(function () {
                cb();
                return false;
            });
        }
    }
}

})(jQuery);

function errorLightbox(error, cb) {
    var lb = new ST.SimpleLightbox;
    lb.show(loc('nav.error'), error, cb);
}

function successLightbox(msg, cb) {
    var lb = new ST.SimpleLightbox;
    lb.show(loc('info.success'), msg, cb);
}
