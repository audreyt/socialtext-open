jQuery(function() {

if (!Socialtext.wikiwyg_variables.hub.current_workspace.enable_spreadsheet)
    return;

var $current_target;
var clock_skew = 0;
var $helper = jQuery("#st-page-activity-helper").empty();

if (!Date.now) {
    Date.now = function() {
        return (new Date()).getTime();
    };
}

var refresh_page_activity = function(activities) {
    var act = [];
    jQuery.each(
        activities,
        function(i) {
            var activity = [];
            activity[0] = this[0];
            activity[1] = this[1];
            activity[2] = this[2];

            var t = Number(this[3]);
            var sec_ago = parseInt( (Date.now()/1000) - t - clock_skew);
            activity[3] = sec_ago <= 90
                ? sec_ago + " seconds ago"
                : Math.round(sec_ago / 60) + " minutes ago";

            act.push(activity);
        }
    );

    $helper.html(
        Jemplate.process(
            "page_activity.html",
            { "activities": act }
        )
    );

}

jQuery("#st-edit-button-link").bind("click", function(e) {
    jQuery.ajax({
        url: 'index.cgi',
        type: 'post',
        dataType: 'json',
        data: {
            'action': 'page_activity',
            'page_id': Socialtext.page_id,
            'workspace_id': Socialtext.wiki_id,
            'user_id': Socialtext.username,
            'page_activity': 'edit'
        },
        success: function(ignore) {
        }
    });
});

jQuery(window).bind("page-activity-refresh", function(e) {

    if (!Socialtext.page_id) return;
    if (Socialtext.page_activity_refreshing) return;
    Socialtext.page_activity_refreshing = true;

    var activities = [];

    activities.push({
        'user_id': Socialtext.username,
        "page_id": Socialtext.page_id,
        "workspace_id": Socialtext.wiki_id,
        "page_activity": $current_target ? null : "view"
    });

    jQuery(".st-include-activity").each(function() {
        var page_id = jQuery(this).next("a").attr("href").replace(/.*\?/, '');
        activities.push({
            'user_id': Socialtext.username,
            "page_id": page_id,
            "workspace_id": Socialtext.wiki_id,
            "page_activity": $current_target ? null : "view-include"
        });
    });

    jQuery("#st-page-activity, .st-include-activity").html("&nbsp;");

    jQuery.ajax({
        url: 'index.cgi',
        type: 'post',
        dataType: 'json',
        contentType: 'application/x-www-form-urlencoded; charset=UTF-8',
        data: {
            'action': 'page_activity',
            'activities': JSON.stringify(activities)
        },
        success: function(page_activities) {
            page_activities["__current_client_time"] = parseInt(Date.now()/1000);

            clock_skew = page_activities["__current_client_time"] - page_activities["__current_time"]

            var activities = page_activities[ Socialtext.page_id ];

            jQuery("#st-page-activity")
                .removeClass("edit")
                .text(activities.length);

            if (jQuery.grep(activities, function(i) { return (i[2] == "edit") }).length >0) {
                jQuery("#st-page-activity").addClass("edit")
            }

            jQuery("#st-page-activity").hover(
                function() {
                    refresh_page_activity( page_activities[ Socialtext.page_id ]);
                    var offset = jQuery(this).offset();
                    offset.left += jQuery(this).width() + 10;
                    $helper.css(offset).fadeIn();
                },
                function() { $helper.fadeOut(); }
            );

            jQuery(".st-include-activity").each(function() {
                var page_id = jQuery(this).next("a").attr("href").replace(/.*\?/, '');
                var activities = page_activities[ page_id ];

                jQuery(this).removeClass('edit').text(activities.length);

                if (jQuery.grep(activities, function(i) { return (i[2] == "edit") }).length >0) {
                    jQuery(this).addClass("edit")
                }

                jQuery(this).hover(
                    function() {
                        refresh_page_activity( page_activities[page_id] );

                        var offset = jQuery(this).offset();
                        offset.left += jQuery(this).width() + 10;
                        $helper.css(offset).fadeIn();
                    },
                    function() { $helper.fadeOut(); }
                );
            });

        },
        complete: function() {
            if ($current_target) {
                $current_target.trigger("mouseover");
                $current_target = null;
            }
            Socialtext.page_activity_refreshing = false;
        }
    });
});


jQuery(window).trigger("page-activity-refresh");

jQuery("#st-page-activity, .st-include-activity")
.bind("click", function(e) {
    $current_target = jQuery(e.target);
    jQuery(window).trigger("page-activity-refresh");
    return false;
});



});

