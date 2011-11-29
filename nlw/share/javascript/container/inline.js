// Overload runOnLoadHandlers for inline widgets
gadgets.util.registerOnLoadHandler = function(callback) {
    $(callback);
};

/*
 * Widget-specific code requires us to re-scope a widget specific gadgets
 * object
 */
rescopedGadgetsObject = function(instance_id) {
    var $widgetNode = $("#gadget-" + instance_id);

    return $.extend(true, {}, gadgets, {
        'window': {
            adjustHeight: function(new_height) { /* NOOP */ },
            setTitle: function(title) {
                if (title.length >= 25 ) {
                  title = title.substr(0,23); // same as template
                  title = title + ' ...';
                }
                $widgetNode.find('.widgetTitle h1').html(
                    title.replace(/&/g, '&amp;').replace(/</g, '&lt;')
                );

            }
        },
        'pubsub': {
            publish: function(channel, message) {
                gadgets.rpc.receiveSameDomain({
                    s: "pubsub",
                    f: "inline-" + instance_id,
                    c: null,
                    a: [ "publish", channel, message ],
                    t: 0
                });
            },
            subscribe: function(channel, callback) {
                throw new Error(
                    "pubsub.subscribe is not implemented in inline widgets"
                );
            },
            unsubscribe: function(channel) {
                throw new Error(
                    "pubsub.unsubscribe is not implemented in inline widgets"
                );
            }
        },
        'Prefs': function() {
            var InlinePrefs = function(){};
            InlinePrefs.prototype = {
                prefNode: function(key) {
                    return $widgetNode.find('*[name=' + key + ']');
                },
                getBool: function(key) {
                    return this.prefNode(key).is(':checked');
                },
                getString: function(key) {
                    return this.prefNode(key).val();
                },
                set: function(key, val) {
                    this.prefNode(key).val(val);
                    var prefs = {};
                    prefs['up_' + key] = val;

                    gadgets.container.setPreferences(
                        instance_id, prefs, function(url) {}
                    );
                }
            };
            return InlinePrefs;
        }()
    });
};

shindig = { auth: { getSecurityToken: function() { return "UNSET" } } };
rescopedOpensocialObject = function(instance_id) {
    var ShindigContainer = function() {
        RestfulContainer.call(this, "/nlw", "shindig", { person:[] });
        this.securityToken_ = instance_id;
    };
    ShindigContainer.inherits(RestfulContainer);

    var os = $.extend({}, opensocial);
    os.Container.setContainer(new ShindigContainer());

    return os;
};

