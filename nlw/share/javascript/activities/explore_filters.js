if (typeof(Activities) == 'undefined') Activities = {};

jQuery(function() {
    Activities.ExploreFilters = function(){
        // {bz: 4535} we don't need filters anywhere except explore
        if (!$("#contentContainer").hasClass('explore')) return;

        var callbacks = [];
        var baseURI = "";
        var filters;

        filters = [
            {
                key: 'class',
                defaultVal: 'everything',
                order: 0,
                uriVals: { everything: '' }
            },
            {
                key: 'users',
                defaultVal: 'all',
                order: 1,
                uriVals: {
                    mine: Socialtext.real_user_id,
                    follows: 'follows',
                    all: ''
                }
            },
            {
                key: 'after',
                defaultVal: 'anytime',
                order: 2,
                uriVals: { anytime: '' }
            },
            {
                key: 'before',
                defaultVal: 'now',
                order: 3,
                uriVals: {
                    now: '',
                    '*': function(val) {
                        // Actually pass the following day so we select
                        // everything from the current date (i.e. everything
                        // before the start of the next date)
                        return Activities.ExploreFilters.offsetDate(val, 1);
                    }
                }
            },
            {
                key: 'groups',
                defaultVal: 'any',
                order: 4,
                uriVals: { any: '' }
            },
            {
                key: 'accounts',
                defaultVal: 'any',
                order: 5,
                uriVals: { any: '' }
            },
            {
                key: 'taggers',
                defaultVal: 'any',
                order: 6,
                uriVals: {
                    any: '',
                    me: Socialtext.real_user_id,
                    selected: function() {
                        // XXX not necessarily watchlist
                        return Activities.ExploreFilters.getURIValue('users');
                    }
                }
            },
            {
                key: 'tags',
                defaultVal: 'any',
                order: 6,
                uriVals: { any: '' }
            },
            {
                key: 'order',
                order: 7,
                defaultVal: 'recency'
            }
        ];

        function getFilter(key) {
            var f = $.grep(filters, function(f) { return f.key == key });
            if (f && f.length) return f[0];
            throw new Error('No filter named ' + key);
        }

        function getFilterList(key) {
            var filter = getFilter(key);
            if (!filter.val || filter.val == 'any') return [];
            return String(filter.val).split(',');
        } 

        /**
         * location.href stuff
         */
        var original = [];
        var original_hash;

        // Update the location.href based on internal filter changes
        function updateLocation() {
            var modified = {};
            var isModified = false;
            $.each(filters, function(i, filter) {
                var value = filter.val || filter.defaultVal;
                if (value != original[i]) {
                    original[i] = modified[filter.key] = value;
                    isModified = true;
                }
            });
            location.hash = original_hash = '#' +
                $.map(filters, function(el) {
                    return el.val || el.defaultVal;
                }).join('/');
            if (isModified) {
                $.each(callbacks, function(i, cb) { cb(modified) });
            }
        }

        function loadURL() {
            var values = String(location.hash).replace(/^#/,'').split('/');
            $.each(values, function(i, value) {
                filters[i].val = value;
            });
        }

        // Update the internal filters based on location.href changes
        $('body').everyTime('500ms', 'location', function() {
            if (original_hash != location.hash) {
                loadURL();
                updateLocation();
            }
        });

        loadURL();

        return {
            update: function() {
                updateLocation();
            },
            getURIValue: function(key) {
                var filter = getFilter(key);
                var val =  filter.val;
                if (typeof val == 'undefined') val = filter.defaultVal;
                if (val && filter.uriVals) {
                    var filter_or_value = val;
                    if (typeof filter.uriVals[val] != 'undefined') {
                        filter_or_value = filter.uriVals[val];
                    }
                    else if (typeof filter.uriVals['*'] != 'undefined') {
                        filter_or_value = filter.uriVals['*'];
                    }

                    val = $.isFunction(filter_or_value)
                        ? filter_or_value(val)
                        : filter_or_value;
                }
                return val;
            },
            getValue: function(key) {
                var filter = getFilter(key);
                return filter.val || filter.defaultVal;
            },
            setValue: function(key, val) {
                var filter = getFilter(key);
                filter.val = val;
                updateLocation();
            },
            addValue: function(key, val) {
                var val = $.grep(getFilterList(key), function(v) {
                    return v != val;
                }).concat(val).join(',');
                Activities.ExploreFilters.setValue(key,val);
            },
            removeValue: function(key, val) {
                var val = $.grep(getFilterList(key), function(v) {
                    return v != val
                }).join(',');
                Activities.ExploreFilters.setValue(key,val);
                return val;
            },
            reset: function() {
                $.each(filters, function(i, filter) { delete filter.val });
                updateLocation();
            },
            uri: function(opts) {
                var uri = baseURI + '/data/signals/assets';
                var args = [];
                $.each(opts, function(key,val) {
                    args.push(key + '=' + val);
                });
                $.each(filters, function(i, filter) {
                    var key = filter.key;
                    var val = Activities.ExploreFilters.getURIValue(key);
                    if (val) args.push(key + '=' + val);
                });
                return uri + '?' + args.join('&');
            },
            setBaseUri: function(uri) {
                baseURI = uri;
            },
            onChange: function(cb) {
                callbacks.push(cb);
            },

            // time math function
            offsetDate: function (day, offset, def) {
                // Set the date object
                if (!(day instanceof Date)) {
                    var parts = day.split('-');
                    if (parts.length != 3) return def;
                    day = new Date(parts[0], Number(parts[1]) - 1, parts[2]);
                }

                // Modify the date based on the offset
                day.setDate(day.getDate() + offset);

                // Construct a formatted date string
                var month = day.getMonth() + 1;
                return [
                    day.getFullYear(),
                    month < 10 ? '0' + month : month,
                    day.getDate() < 10 ? '0' + day.getDate() : day.getDate()
                ].join('-');
            }
        };
    }();
});

