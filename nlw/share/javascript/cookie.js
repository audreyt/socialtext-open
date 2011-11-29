Cookie = {};

Cookie.get = function(name) {
    var cookieStart = document.cookie.indexOf(name + "=")
    if (cookieStart == -1) return null
    var valueStart = document.cookie.indexOf('=', cookieStart) + 1
    var valueEnd = document.cookie.indexOf(';', valueStart);
    if (valueEnd == -1) valueEnd = document.cookie.length
    var val = document.cookie.substring(valueStart, valueEnd);
    return val == null
        ? null
        : unescape(document.cookie.substring(valueStart, valueEnd))
};

Cookie.set = function(name, val, expiration, path) {
    // Default to 25 year expiry if not specified by the caller.
    if (typeof(expiration) == 'undefined') {
        expiration = new Date(
            new Date().getTime() + 25 * 365 * 24 * 60 * 60 * 1000
        );
    }
    var str = name + '=' + escape(val)
        + '; expires=' + expiration.toGMTString();
    if (path) {
        str += '; path=' + path;
    }
    document.cookie = str;
};

Cookie.del = function(name, path) {
    Cookie.set(name, '', new Date(new Date().getTime() - 1), path);
};
