if (typeof(jQuery) == 'undefined') {
    window.nlw_make_s3_path = function (rest) {
        return nlw_make_static_path(
            '/uploaded-skin/' + Socialtext.wiki_id + rest
        );
    };

    var url = window.nlw_make_s3_path(
        '/javascript/socialtext-s3.js?_=' + (new Date).getTime()
    );
    var script = document.createElement('script');
    script.setAttribute('src', url);
    script.setAttribute('charset', 'utf-8');

    document.getElementsByTagName('head')[0].appendChild(script);
}
