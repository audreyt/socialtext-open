(function ($) {
/* Overload jQuery's getScript to always place script tags in the head rather
 * than evaling them
 */
$.getScript = function (url, callback) {
    var head = document.getElementsByTagName("head")[0];
    var script = document.createElement("script");
    script.src = url;

    var done = false;

    // Attach handlers for all browsers
    script.onload = script.onreadystatechange = function() {
        if ( !done && (!this.readyState ||
             this.readyState == "loaded" || this.readyState == "complete") ) {
            done = true;
            if ($.isFunction(callback))
                callback();
        }
    };
    head.appendChild(script);
};

$.fn.serializeHash = function() {
    var hash = {};
    $(this).each(function() {
        $.each($(this).serializeArray(), function(i, el) {
            hash[ el.name ] = el.value
        });
    });
    return hash;
};

})(jQuery);
