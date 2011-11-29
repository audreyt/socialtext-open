(function($) {

if (typeof(Activities) == 'undefined') Activities = {};

Activities.NetworkDropdown = function(opts) {
    this.extend(opts);
    this.requires([
        'user', 'account_id'
    ]);
}

Activities.NetworkDropdown.prototype = new Activities.Base()

$.extend(Activities.NetworkDropdown.prototype, {
    toString: function() { return 'Activities.NetworkDropdown' },

    _defaults: {
        node: $('body')
    }, 

    show: function(callback) {
        var self = this;
        $.getJSON("/data/users/" + self.user, function(data) {
            self.appdata = new Activities.AppData({
                workspace_id: self.workspace_id,
                prefix: self.prefix,
                instance_id: 1,
                user_data: data,
                node: true,
                owner: true,
                viewer: true,
                owner_id: true
            });

            var default_network = 'account-' + self.account_id;
            self.findId('st-edit-summary-signal-to').val(default_network);

            self.appdata.selectSignalToNetwork = function(network){
                self.findId('st-edit-summary-signal-to').val(network);
            };
        
            self.getSignalToNetworks(function(networks) {
                self.findId('signal_network')
                    .html(
                        self.appdata.processTemplate('network_options', {
                            options: networks
                        })
                    )
                    .dropdown()
                    .change(function() {
                        self.appdata.selectSignalToNetwork($(this).val());

                        // Check for warnings
                        var $opt = $(this).find('option:selected')

                        if ($opt.hasClass('warning')) {
                            self.findId('signal_network_warning')
                                .fadeIn('fast');
                        }
                        else {
                            self.findId('signal_network_warning')
                                .fadeOut('fast');
                        }
                        self.findId('st-edit-summary-signal-checkbox')
                            .attr('checked', true);
                    })
            });
        });
    },

    getSignalToNetworks: function(cb) {
        var self = this;

        var sections = [
            { title: loc('nav.wiki-groups'), networks: [] },
            {
                title: loc('nav.non-wiki-groups'),
                networks: []
            }
        ];

        $.getJSON('/data/workspaces/' + self.workspace_id, function(data) {
            var warningText = loc('info.edit-summary-signal-visibility');
            var dropdown = self.findId('signal_network').get(0);
            var $firstGroup;
            var seenWarning = false;
            $.each(self.appdata.networks(), function(i, net) {
                if (net.value == 'all') return;
                if (!~$.inArray('signals', net.plugins_enabled)) return;

                if (/^account-/.test(net.value)) {
                    if ((data.is_all_users_workspace) && (net.value == ('account-' + data.account_id))) {
                        // No warning signs for All-user workspace on the primary account
                        sections[0].networks.push(net);
                    }
                    else {
                        net['class'] = 'warning';
                        sections[1].networks.push(net);
                    }
                    return;
                }

                var id = parseInt(net.value.substr(6));
                if ($.grep(data.group_ids, function(g) { return (g == id) }).length == 0) {
                    net['class'] = 'warning';
                    sections[1].networks.push(net);
                    return;
                }

                sections[0].networks.push(net);
            });

            cb(sections);
            return;
        });
    }
});

})(jQuery);
