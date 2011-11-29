(function ($) {

socialtext.dialog.register('activities-add-video', function(opts) {
    var dialog = socialtext.dialog.createDialog({
        html: socialtext.dialog.process('activities-add-video.tt2', opts),
        title: loc('do.add-video'),
        params: opts.params,
        buttons: [
            {
                id: 'activities-add-video-ok',
                text: loc('do.ok'),
                click: function() {
                    dialog.find('form').submit();
                }
            },
            {
                id: 'activities-add-video-cancel',
                text: loc('do.cancel'),
                click: function() {
                    dialog.close();
                }
            }
        ]
    });

    var intervalId = startCheckingVideoURL();

    $('#activities-add-video-ok').button('disable');

    dialog.find('form').submit(function() {
        if (dialog.find('.submit').is(':hidden')) return;
        var url = dialog.find('.video_url').val() || '';
        var title = dialog.find('.video_title').val() || '';

        if (opts.callback(url, title) === false) {
            // cancellable by returning false
            dialog.find('.error')
                .text(loc("error.invalid-video-link"))
                .show();
            dialog.find('.video_url').focus();
        }
        else {
            clearInterval(intervalId);
            dialog.close();
        }
        return false;
    });

    function startCheckingVideoURL(url) {
        var $url = dialog.find('.video_url');
        var $done = $('#activities-add-video-ok');
        var $title = dialog.find('.video_title');

        var previousURL = $url.val() || null;
        var loading = false;
        var queued = false;

        return setInterval(function (){
            var url = $url.val();
            if (!/^[-+.\w]+:\/\/[^\/]+\//.test(url)) {
                $title.val('');
                url = null;
                $done.button('disable');
            }
            if (url == previousURL) return;
            previousURL = url;
            if (loading) { queued = true; return }
            queued = false;
            if (!url) return;
            loading = true;
            $title
                .val(loc('activities.loading-video'))
                .attr('disabled', true);

            $done.button('disable');

            jQuery.ajax({
                type: 'get',
                async: true,
                url: '/',
                dataType: 'json',
                data: {
                    action: 'check_video_url',
                    video_url: url.replace(/^<|>$/g, '')
                },
                success: function(data) {
                    loading = false;
                    if (queued) { return; }
                    if (data.title) {
                        $title
                            .val(data.title)
                            .attr('disabled', false)
                            .attr('title', '');
                        $done.button('enable');
                    }
                    else if (data.error) {
                        $title.val(data.error)
                            .attr('disabled', true)
                            .attr('title', data.error);
                    }
                }
            });
        }, 500);
    }
});

})(jQuery);
