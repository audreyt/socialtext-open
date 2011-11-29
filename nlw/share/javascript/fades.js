(function($){

$.fn.fade = function(color, cb) {
    $(this).addClass('colorFaded').animate(
        { backgroundColor: color },
        function() {
            if (cb) cb();
            cb = null;
        }
    );
}

$.fn.yellowFade = function(cb) {
    $(this).fade('#FFC', cb);
}

$.fn.redFade = function(cb) {
    $(this).fade('#ECAAAA', cb);
}

$.fn.clearFades = function(cb) {
    if ($(this).hasClass('colorFaded')) {
        $(this).fade('white', function() {
            $(this).removeClass('colorFaded');
            $(this).clearFades(cb); // tail-recurse into the next branch...
        });
    }
    else if ($(this).find('.colorFaded').size()) {
        $(this).find('.colorFaded').fade('white', function() {
            $(this).find('.colorFaded').removeClass('colorFaded');
            $(this).clearFades(cb); // tail-recurse into the next branch...
        });
    }
    else {
        if (cb) cb();
        cb = null;
    }
}

})(jQuery);
