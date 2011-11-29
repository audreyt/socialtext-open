(function ($) {

socialtext.dialog.register('activities-show-video', function(opts) {
    var dialog = socialtext.dialog.createDialog({
        html: socialtext.dialog.process('activities-show-video.tt2', opts),
        title: opts.title,
        params: opts.params
    });
    dialog.disable();
    $.ajax({
        method: 'GET',
        dataType: 'text',
        url: '/?action=get_video_html;autoplay=1;width='
            + opts.params.video.width
            + ';video_url=' + encodeURIComponent(opts.params.url),
        success: function(html) {
            dialog.enable();
            dialog.find('.video').html(html);
        }
    });
});

})(jQuery);
