(function($) {

if (typeof(Activities) == 'undefined') Activities = {};

Activities.LastSignal = function(opts) {
    this.extend(opts);
}

Activities.LastSignal.prototype = new Activities.Base()

$.extend(Activities.LastSignal.prototype, {
    toString: function() { return 'Activities.LastSignal' },

    _defaults: {
        base_uri: location.protocol + '//' + location.host
    }, 

    render: function(callback) {
        var self = this;
        var uri = self.base_uri
            + "/data/signals?no_replies=1;limit=1;sender=" + self.owner_id;
        self.makeRequest(uri, function(response) {
            if (!response.data.length) return;
            var html = self.processTemplate('activities/last_signal.tt2', {
                signal: response.data[0]
            });
            $(self.node).html(html).show();

            // Update the ago text every 10 seconds
            var $ago = $(self.node).find('.ago');
            setInterval(function() {
                var ago_text = self.processTemplate('activities/ago.tt2', {
                    at: response.data[0].at
                });
                if (ago_text != $ago.text()) $ago.text(ago_text);
            }, 10000);
        });
    }
});

})(jQuery);
