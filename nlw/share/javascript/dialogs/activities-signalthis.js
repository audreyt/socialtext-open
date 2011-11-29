st.dialog.register('activities-signalthis', function(opts) {
    var $node = $('#st-signal-this-frame');
    if ($node.size()) $node.remove();
    $node = $(st.dialog.process('activities-signalthis.tt2'))
        .appendTo('#content');

    $node
        .css({
            backgroundColor: '#FFF',
            width: '440px',
            position: (
                ($.browser.msie && $.browser.version < 7)
                    ? 'absolute' // IE6
                    : 'fixed'
            ),
            right: '15px',
            top: '15px',
            display: 'none',
            border: '1px solid #999',
            zIndex: '3000',
            boxShadow: '5px 5px 3px rgba(0, 0, 0, 0.3)',
            '-moz-box-shadow': '5px 5px 3px rgba(0, 0, 0, 0.3)',
            '-webkit-box-shadow': '5px 5px 3px rgba(0, 0, 0, 0.3)'
        })
        .createSelectOverlap({noPadding: true})
        .fadeIn('fast');

    var base_uri = location.protocol + '//' + location.host;
    var activities = new Activities.Widget({
        ui_template: "ui.signalthis.tt2",
        draggable: {
            handle: '.top'
        },
        overlap: true,
        instance_id: "0",
        node: $node.get(0),
        prefix: 'st-signalthis',
        base_uri: base_uri,
        share: nlw_make_plugin_path('/widgets'),
        static_path: base_uri + nlw_make_static_path(''),
        viewer: Socialtext.userid,
        viewer_id: Socialtext.real_user_id,
        viewer_name: Socialtext.username,
        owner: Socialtext.userid,
        owner_id: Socialtext.real_user_id,
        owner_name: Socialtext.username,
        default_network:
            "account-" + Socialtext.current_workspace_account_id,
        signal_this:
            '{link: ' + Socialtext.wiki_id 
                + '[' + Socialtext.page_title + ']}',
        workspace_id: Socialtext.wiki_id,
        initial_text: ' ',
        fixed_action: 'action-signals',
        signals_only: '1',

        mention_user_id: '',
        mention_user_name: ''
    });
    activities.start();
});
