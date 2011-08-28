JSAN.use("DOM.Events");

if ( typeof Widget == "undefined" )
    Widget = {};

Widget.Balloon = function(params) {
    var refNodeId = params['elementId'];
    var refNode = params['element'];
    var html = params['innerHTML'];
    var doc = params['document'];
    var freeze = params['freeze_callback'];

    this.document = doc ? doc : document;
    this.freeze_callback = freeze ? freeze : function() {};

    var self = this._init();
    if ( !refNode && refNodeId ) {
        refNode = this.document.getElementById(refNodeId);
    }
    this.eventIds = { refNode: {}, balloonNode: {} };
    if ( refNode ) {
        this.refNode = refNode;
        this._addListeners();
    }

    if ( html )
        self.setInnerHTML(html);

    return self;
}

Widget.Balloon.VERSION = '0.02';
Widget.Balloon.EXPORT = [];
Widget.Balloon.EXPORT_OK = [];
Widget.Balloon.EXPORT_TAGS = {};

Widget.Balloon.prototype.balloon_divs = [];

Widget.Balloon.prototype.balloon_master;

Widget.Balloon.prototype._init = function() {
    var id = this.balloon_divs.length + 1;
    var div = this.document.createElement('div');
    div.id = 'balloon_' + id;
    div.setAttribute('class', 'balloon-div');
    with ( div.style ) {
        zIndex = 65535; // Large enough to be above everything.
        borderWidth = "1px";
        borderStyle = "solid";
        borderColor = "#000";
        position = "absolute";
        width = "200px";
        // height = "200px";
        height: '100px',
        background = "#fff";
        display = "block";
    }
    this.balloon_divs.push(div);
    this.div = div;
    this.is_hidden = true;
    this.is_freezed = false;
    this.is_highlighted = false;
    return this;
}

Widget.Balloon.prototype.setInnerHTML = function(html) {
    this.div.innerHTML = html;
}

Widget.Balloon.prototype.setPosition = function(e) {
    var top =  e.clientY + 2;
    var left = e.clientX + 2;

    /*
    this.debug("style.left:" + left + "\n" +
               "style.top: " + top  + "\n" +
               "innerWidth: " + window.innerWidth  + "\n" +
               "innerHeight:" + window.innerHeight
               );
    */
    if ( left + this.div.offsetWidth > window.innerWidth ) {
        left = e.clientX - 2 - this.div.offsetWidth;
    }

    if ( top + this.div.offsetHeight > window.innerHeight ) {
        top = e.clientY - 2 - this.div.offsetHeight;
    }

    this.div.style.top = top;
    this.div.style.left = left;
}

Widget.Balloon.prototype.show = function(e) {
    if ( this.is_hidden ) {
        this.document.body.appendChild( this.div );
        this.is_hidden = false;
    }
    this.refresh(e);
}

Widget.Balloon.prototype.hide = function(e) {
    if ( this.is_hidden ) return;
        this.document.body.removeChild( this.div );
    this.is_hidden = true;
    this.unhighlight();
}

Widget.Balloon.prototype.refresh = function(e) {
    if ( ! this.is_freezed )
        this.setPosition(e);
}

Widget.Balloon.prototype.highlight = function(e) {
    this.is_highlighted = true;
    this.div.style.backgroundColor = "#fbffcc";
}

Widget.Balloon.prototype.unhighlight = function(e) {
    this.is_highlighted = false;
    this.div.style.backgroundColor = "#fff";
}

/*
Widget.Balloon.prototype.debug = function(str) {
    var e = this.document.getElementById("debug");
    if ( e ) {
        e.innerHTML = '<pre>' + str + '</pre>';
    }
}
*/

Widget.Balloon.prototype.freeze = function(e) {
    if ( this.is_freezed ) {
        this._addListeners();
        this.is_freezed = false;
        return;
    }
    
    this.is_freezed = true;
    this._removeListeners({ refNode: ['mouseover', 'mousemove', 'mouseout'] });
    this.freeze_callback(this.div);
}

Widget.Balloon.prototype._listeners = function () {
    var self = this;
    return {
        refNode: {
            mouseover: function(e) { self.show(e);   },
            mouseout:  function(e) { self.hide(e);   },
            mousemove: function(e) { self.refresh(e) },
            click:     function(e) {
                if ( self.is_freezed ) {
                    self.hide(e);
                } else if ( self.is_hidden ) {
                    self.show(e);
                }
                self.freeze(e);
                self.refresh(e);
            }
        },
        balloonNode: {}
//             click:     function(e) {
//                 if ( self.is_highlighted )
//                     self.unhighlight();
//                 else
//                     self.highlight();
//             }
//         }
    };
}

Widget.Balloon.prototype._addListeners = function() {
    var self = this;
    var listeners = this._listeners();

    for (id in listeners["balloonNode"]) {
        if ( this.eventIds["balloonNode"][id] )
            continue;
        this.eventIds["balloonNode"][id]
            = DOM.Events.addListener(this.div, id,
                                     listeners["balloonNode"][id]);
    }
    
    var refNode = this.refNode;
    if ( ! refNode )
        return;
    
    for (id in listeners["refNode"]) {
        if ( this.eventIds["refNode"][id] )
            continue;
        this.eventIds["refNode"][id]
            = DOM.Events.addListener(refNode, id, listeners["refNode"][id]);
    }
}

Widget.Balloon.prototype._removeListeners = function(ids) {
    if ( !ids ) {
        ids = [];
        for(var i in this.eventIds) {
            ids[i] = this.eventIds[i];
        }
    }
    
    for(var node in ids) {
        var events = ids[node];
        for ( var i = 0 ; i < events.length ; i++ ) {
            var id = events[i];
            if ( ! ( this.eventIds[node] && this.eventIds[node][id] ) )
                continue;
            DOM.Events.removeListener(this.eventIds[node][id]);
            this.eventIds[node][id] = false;
        }
    }
}

/* Two currently unused functions. */

/*
Widget.Balloon.prototype._findPosX = function(obj) {
    var curleft = 0;
    if (obj.offsetParent) {
	while (obj.offsetParent) {
	    curleft += obj.offsetLeft
	    obj = obj.offsetParent;
	}
    }
    else if (obj.x)
	curleft += obj.x;
    return curleft;
}

Widget.Balloon.prototype._findPosY = function(obj) {
    var curtop = 0;
    if (obj.offsetParent) {
	while (obj.offsetParent) {
	    curtop += obj.offsetTop
	    obj = obj.offsetParent;
	}
    }
    else if (obj.y)
	curtop += obj.y;
    return curtop;
}
*/
