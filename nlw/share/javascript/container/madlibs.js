function updateTimestamps(containerselector, relorigselector, reltargetselector)
{
    jQuery(containerselector).each(
        function(index, item) {
            var timestamp=jQuery(relorigselector, item).text();
            var then = new Date();
            then.setISO8601(timestamp);
            jQuery(reltargetselector, item).text(getAgoString(then));
        }
    );
}


// The following 2 functions borrowed from http://delete.me.uk/2005/03/iso8601.html
Date.prototype.setISO8601 = function (string) {
    var regexp = "([0-9]{4})(-([0-9]{2})(-([0-9]{2})" +
        "([T ]([0-9]{2}):([0-9]{2})(:([0-9]{2})(\.([0-9]+))?)?" +
        "(Z|(([-+])([0-9]{1,2})(?::([0-9]{2}))?))?)?)?)?";
    var d = string.match(new RegExp(regexp));

    var offset = 0;
    var date = new Date(d[1], 0, 1);

    if (d[3]) { date.setMonth(d[3] - 1); }
    if (d[5]) { date.setDate(d[5]); }
    if (d[7]) { date.setHours(d[7]); }
    if (d[8]) { date.setMinutes(d[8]); }
    if (d[10]) { date.setSeconds(d[10]); }
    if (d[12]) { date.setMilliseconds(Number("0." + d[12]) * 1000); }
    if (d[14]) {
        offset = (Number(d[16] || 0) * 60) + Number(d[17] || 0);
        offset *= ((d[15] == '-') ? 1 : -1);
    }

    offset -= date.getTimezoneOffset();
    var time = (Number(date) + (offset * 60 * 1000));
    this.setTime(Number(time));
}

Date.prototype.toISO8601String = function (format, offset) {
    /* accepted values for the format [1-6]:
     1 Year:
       YYYY (eg 1997)
     2 Year and month:
       YYYY-MM (eg 1997-07)
     3 Complete date:
       YYYY-MM-DD (eg 1997-07-16)
     4 Complete date plus hours and minutes:
       YYYY-MM-DDThh:mmTZD (eg 1997-07-16T19:20+01:00)
     5 Complete date plus hours, minutes and seconds:
       YYYY-MM-DDThh:mm:ssTZD (eg 1997-07-16T19:20:30+01:00)
     6 Complete date plus hours, minutes, seconds and a decimal
       fraction of a second
       YYYY-MM-DDThh:mm:ss.sTZD (eg 1997-07-16T19:20:30.45+01:00)
    */
    if (!format) { var format = 6; }
    if (!offset) {
        var offset = 'Z';
        var date = this;
    } else {
        var d = offset.match(/([-+])([0-9]{2}):([0-9]{2})/);
        var offsetnum = (Number(d[2]) * 60) + Number(d[3]);
        offsetnum *= ((d[1] == '-') ? -1 : 1);
        var date = new Date(Number(Number(this) + (offsetnum * 60000)));
    }

    var zeropad = function (num) { return ((num < 10) ? '0' : '') + num; }

    var str = "";
    str += date.getUTCFullYear();
    if (format > 1) { str += "-" + zeropad(date.getUTCMonth() + 1); }
    if (format > 2) { str += "-" + zeropad(date.getUTCDate()); }
    if (format > 3) {
        str += "T" + zeropad(date.getUTCHours()) +
               ":" + zeropad(date.getUTCMinutes());
    }
    if (format > 5) {
        var secs = Number(date.getUTCSeconds() + "." +
                   ((date.getUTCMilliseconds() < 100) ? '0' : '') +
                   zeropad(date.getUTCMilliseconds()));
        str += ":" + zeropad(secs);
    } else if (format > 4) { str += ":" + zeropad(date.getUTCSeconds()); }

    if (format > 3) { str += offset; }
    return str;
}

function best_full_name(person) {
    if (person['best_full_name'])
        return person['best_full_name'];

    if ((person['first_name'] != undefined) && 
        (person['last_name'] != undefined)) 
    {
        return person['first_name'] + " " + person['last_name'];
    }
    else {
        return person['name'].split('@')[0];
    }
}

function html_escape(text) {
    // XXX: surely we can use some javascript lib's version of this hack
    text = text.replace(/&/g,'&amp;');
    text = text.replace(/</g,'&lt;');
    text = text.replace(/>/g,'&gt;');
    return text;
}

function a_tag(link, text, clazz) {
    if (clazz == null) clazz = "";
    return '<a class="'+clazz+'"' +
            ' href="'+link+'">'+html_escape(text)+'</a>';
}

function linked_person_tag(evt, tag_name) { 
    return a_tag('/?action=people;tag='+encodeURIComponent(tag_name), tag_name);
}

function linked_page_tag(evt, tag_name) { 
    var ws_name = evt.page.workspace_name;
    var link_base = 'index.cgi?action=category_display;category=';
    return a_tag('/' + ws_name + '/' + link_base + encodeURIComponent(tag_name), tag_name, 'tag');
}

function linked_person(evt, person) {
    var bfn = best_full_name(person);
    return Number(person.profile_is_visible) ? a_tag('/?profile/' + person.id, bfn, 'person') : bfn;
}

function context_summary(evt, context) {
    return context.summary;
}

function linked_page(evt, page) { 
    var pg_id = page.id;
    var pg_name = page.name;
    var ws_name = page.workspace_name;
    var ws_title = page.workspace_title;
    var page = a_tag('/'+ws_name+'/index.cgi?'+pg_id, pg_name, 'object');
    var ws = a_tag('/'+ws_name+'/index.cgi', ws_title, undefined);
    return page + ' in ' + ws;
}

var page_madlib_constructors = {
    'view': {
        'sentence': "%(actor)s viewed %(page)s",
        'transformer': {}
    },
    'edit_save': {
        'sentence': "%(actor)s edited %(page)s",
        'transformer': {}
    },
    'duplicate': {
        'sentence': "%(actor)s duplicated %(page)s",
        'transformer': {}
    },
    'rename': {
        'sentence': "%(actor)s renamed  %(page)s",
        'transformer': {}
    },
    'delete': {
        'sentence': "%(actor)s deleted %(page)s",
        'transformer': {}
    },
    'comment': {
        'sentence': "%(actor)s commented on %(page)s, saying %(context)s",
        'transformer': {
            'context': context_summary
        }
    },
    'tag_add': {
        'sentence': "%(actor)s tagged %(page)s as %(tag_name)s",
        'transformer': {
            'tag_name': linked_page_tag
        }
    },
    'tag_delete': {
        'sentence': "%(actor)s removed tag %(tag_name)s from %(page)s",
        'transformer': {
            'tag_name': linked_page_tag
        }
    },

    'comment:convo': {
        // comment summaries don't show up in my convos feed
        'sentence': "%(actor)s commented on %(page)s",
        'transformer': {}
    },
    'tag_add:convo': {
        // tag names don't show up in my convos feed
        'sentence': "%(actor)s tagged %(page)s",
        'transformer': {}
    },
    'upload_file:convo': {
        'sentence': "%(actor)s uploaded a file to %(page)s",
        'transformer': {}
    },
    'watch_add': {
        'sentence': "%(actor)s is now following %(page).",
        'transformer': {}
    },
    'watch_delete': {
        'sentence': "%(actor)s has stopped following %(page).",
        'transformer': {}
    },

    'default': {
        'sentence': "%(actor)s performed action '%(action)s' on %(page)s",
        'transformer': {}
    }
}

var person_madlib_constructors = {
    'edit_save': {
        'sentence': "%(actor)s edited %(person)s's profile",
        'transformer': {}
    },
    'tag_add': {
        'sentence': "%(person)s was tagged '%(tag_name)s' by %(actor)s",
        'transformer': {
            'tag_name': linked_person_tag
        }
    },
    'tag_delete': {
        'sentence': "%(actor)s removed tag '%(tag_name)s' from %(person)s",
        'transformer': {
            'tag_name': linked_person_tag
        }
    },
    'watch_add': {
        'sentence': "%(actor)s is now following %(person)s.",
        'transformer': {}
    },
    'watch_delete': {
        'sentence': "%(actor)s has stopped following %(person)s.",
        'transformer': {}
    },
    'default': {
        'sentence': "%(actor)s performed action '%(action)s' on %(person)s",
        'transformer': {}
    }
}

var default_transformers = {
    'event_class': identity,
    'action': action,
    'actor': linked_person,
    'person': linked_person,
    'page': linked_page
}
var default_sentence =
    "%(actor)s did %(action)s to an %(event_class)s object";

var madlib_constructors = {
    'page' : page_madlib_constructors,
    'person': person_madlib_constructors
}


function identity(x) { return x; }
function action(x) { return x.action; }
// The following 2 functions inspired by http://trac.typosphere.org/browser/trunk/public/javascripts/typo.js
function prettyDateDelta(minutes)
{
    minutes = Math.abs(minutes);
    if (minutes < 1) return "less than a minute";
    if (minutes == 1) return "one minute";
    if (minutes < 50) return String(minutes) + " minutes";
    if (minutes < 90) return "about one hour";
    if (minutes < 1080) return String(Math.round(minutes/60)) + " hours";
    if (minutes < 1440) return "one day";
    if (minutes < 2880) return "about one day";
    return String(Math.round(minutes/1440)) + " days";
}

function getAgoString(then)
{
    var nowts = new Date();
    var now = Number(nowts);
    then = Number(then);

    var delta_minutes;
    if ((now-then) < 0) {
        delta_minutes = 0;
    }
    else {
        delta_minutes = Math.floor((now-then) / (60 * 1000));
    }
    return prettyDateDelta(delta_minutes) + " ago";
}

function madlib_render_event(evt) {
    var then = new Date();
    then.setISO8601(evt.at);

    var cons = madlib_constructors[evt.event_class][evt.action];
    if (cons == null) {
        cons = madlib_constructors[evt.event_class]['default'];
        if (cons == null) {
            return '';
        }
    }

    var sentence = cons['sentence'];
    var keywords = ['actor','action','person','page','tag_name','context'];
    for (var i=0, l=keywords.length; i<l; i++) {
        var keyword = keywords[i];

        var transformer = cons.transformer[keyword];
        if (!transformer) {
            transformer = default_transformers[keyword];
        }
        if (!transformer) continue;

        var pre_val = evt[keyword];
        if (!pre_val) continue;
        
        var val = transformer(evt, pre_val);
        sentence = sentence.replace("%("+keyword+")s", val);
    }

    return "<p>" + sentence + 
        " <span class='madlib-ago'>(" + getAgoString(then) + ")</span></p>";
}
