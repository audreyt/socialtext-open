if (typeof ST == 'undefined') {
    ST = {};
}

ST.Comment = function () {
    jQuery(function () {
        var comment_button = jQuery('#st-comment-button-link').get(0);
        if (comment_button) {
            if (! comment_button.href.match(/#$/)) {
                return;
            }

            jQuery('#st-comment-button-link').unbind('click').bind('click', function() {
                ST.Comment.launchCommentInterface({
                    page_name: Socialtext.page_id,
                    action: 'display',
                    height: 200
                });
                return false;
            });
            var below_fold_comment_link = jQuery('#st-edit-actions-below-fold-comment').get(0);
            if (below_fold_comment_link) {
                if (! below_fold_comment_link.href.match(/#$/)) {
                    return;
                }

                jQuery('#st-edit-actions-below-fold-comment').unbind('click').bind('click', function () {
                    ST.Comment.launchCommentInterface({
                        page_name: Socialtext.page_id,
                        action: 'display',
                        height: 200
                    });
                    return false;
                });
            }
        }
    });
};

ST.Comment.launchCommentInterface = function (args) {
    var display_width = (window.offsetWidth || document.body.clientWidth || 600);
    var page_name     = args.page_name;
    var action        = args.action;
    var height        = args.height;
    var comment_window = window.open(
        'index.cgi?action=enter_comment;page_name=' + page_name + ';caller_action=' + action,
        '_blank',
        'toolbar=no, location=no, directories=no, status=no, menubar=no, titlebar=no, scrollbars=yes, resizable=yes, width=' + display_width + ', height=' + height + ', left=' + 50 + ', top=' + 200
    );

    if ( navigator.userAgent.toLowerCase().indexOf("safari") != -1 ) {
        window.location.reload();
    }

    return false;
};

Comment = new ST.Comment ();
