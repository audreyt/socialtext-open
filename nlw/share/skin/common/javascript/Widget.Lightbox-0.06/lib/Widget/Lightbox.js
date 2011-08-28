JSAN.use("DOM.Events");

if ( typeof Widget == "undefined" )
    Widget = {};

Widget.Lightbox = function(param) {
    this.win = window;
    this.doc = window.document;
    this.contentHTML = "";
    this.config = {
        clickBackgroundToHide: true
    };
    if ( param ) {
        if (param.divs ) {
            this.divs = {};
            for(var i in param.divs) {
                this.divs[i] = param.divs[i]
            }
            this.div = this.divs.wrapper;
            this.div.style.display="none";
        }
        if ( param.effects ) {
            this._effects = [];
            for (var i=0; i<param.effects.length; i++) {
                this._effects.push(param.effects[i]);
            }
        }
        if (param.wrapperClassName) {
            this.wrapperClassName = param.wrapperClassName;
        }
        else
            this.wrapperClassName = '';

        if (param.contentClassName) {
            this.contentClassName = param.contentClassName;
        }
        else
            this.contentClassName = '';
    }
    return this;
}

Widget.Lightbox.VERSION = '0.06';
Widget.Lightbox.EXPORT = [];
Widget.Lightbox.EXPORT_OK = [];
Widget.Lightbox.EXPORT_TAGS = {};

Widget.Lightbox.is_ie = function() {
    ua = navigator.userAgent.toLowerCase();
    is_ie = (
        ua.indexOf("msie") != -1 &&
        ua.indexOf("opera") == -1 &&
        ua.indexOf("webtv") == -1
    );
    return is_ie;
}();

Widget.Lightbox.show = function(param) {
    if ( typeof param == 'string' ) {
        var box = new Widget.Lightbox;
        box.content(param);
        box.show();
        return box;
    }
    else {
        var box = new Widget.Lightbox(param);
        box.show();
        return box;
    }
}

Widget.Lightbox.prototype.show = function(callback) {
    this.scrollable = "no";
    var div = this.create();
    if ( this.div.style.display== "none" )
        this.div.style.display="block";
    this.applyStyle();
    this.applyHandlers();
    this.applyEffects();

    if ( typeof callback == 'function') {
        callback(div);
    }
}

Widget.Lightbox.prototype.hide = function() {
    if (this.div.parentNode) {
        this.div.style.display="none";
        if (Widget.Lightbox.is_ie) {
            document.body.scroll = this.scrollable = "yes";
        }
    }
}

Widget.Lightbox.prototype.content = function(content) {
    if ( typeof content != 'undefined' ) {
        this._content = content;
    }
    return this._content;
}

Widget.Lightbox.prototype.create = function() {
    if (typeof this.div != 'undefined') {
        return this.div;
    }

    var wrapperDiv = this.doc.createElement("div");
    wrapperDiv.className = "jsan-widget-lightbox";

    var contentDiv = this.doc.createElement("div");

    if (this.contentClassName) {
        contentDiv.className = this.contentClassName;
    }
    else {
        contentDiv.className = "jsan-widget-lightbox-content";
    }

    if ( typeof this._content == 'object' ) {
        if ( this._content.nodeType && this._content.nodeType == 1 ) {
            contentDiv.appendChild( this._content );
        }
    }
    else {
        contentDiv.innerHTML = this._content;
    }

    var contentWrapperDiv = this.doc.createElement("div");
    if (this.wrapperClassName) {
        contentWrapperDiv.className = this.wrapperClassName;
    }
    else {
        contentWrapperDiv.className = "jsan-widget-lightbox-content-wrapper";
    }

    var bgDiv = this.doc.createElement("div");
    bgDiv.className = "jsan-widget-lightbox-background";

    contentWrapperDiv.appendChild(contentDiv);

    wrapperDiv.appendChild(bgDiv);
    wrapperDiv.appendChild(contentWrapperDiv);

    this.div = wrapperDiv;
    this.divs = {
        wrapper: wrapperDiv,
        background: bgDiv,
        content: contentDiv,
        contentWrapper: contentWrapperDiv
    };
    wrapperDiv.style.display = "none";
    this.doc.body.appendChild(this.div);
    return this.div;
}


Widget.Lightbox.prototype.applyStyle = function() {
    var divs = this.divs;
    with(divs.wrapper.style) {
        position= Widget.Lightbox.is_ie ? 'absolute': 'fixed';
        top=0;
        left=0;
        width='100%';
        height='100%';
        padding=0;
        margin=0;
    }
    with(divs.background.style) {
        position= Widget.Lightbox.is_ie ? 'absolute': 'fixed';
        background="#000";
        opacity="0.5";
        filter = "alpha(opacity=50)";
        top=0;
        left=0;
        width="100%";
        height="100%";
        zIndex=2000;
        padding=0;
        margin=0;
    }

    divs.contentWrapper.style.position = Widget.Lightbox.is_ie ? 'absolute': 'fixed';

    if (this.wrapperClassName) {
        divs.contentWrapper.className = this.wrapperClassName;
    }
    else {
        with(divs.contentWrapper.style) {
            zIndex=2001;
            padding=0;
            background='#fff';
            width='520px';
            margin='100px auto';
            border="1px outset #555";
        }
    }

    with(divs.content.style) {
        margin='5px';
    }

    var win_height = document.body.clientHeight;
    var win_width = document.body.clientWidth;
    var my_width = divs.content.offsetWidth;
    var my_left = (win_width - my_width) /2;
    my_left = (my_left < 0)? 0 : my_left + "px";
    divs.contentWrapper.style.left = my_left;

    if ( Widget.Lightbox.is_ie ) {
        document.body.scroll = this.scrollable;
        divs.background.style.height = win_height;
    }
}

Widget.Lightbox.prototype.applyHandlers = function(){
    if(!this.div)
        return;

    var self = this;

    if ( this.config.clickBackgroundToHide == true ) {
        DOM.Events.addListener(this.divs.background, "click", function () {
            self.hide();
        });
    }
    if (Widget.Lightbox.is_ie) {
        DOM.Events.addListener(window, "resize", function () {
            self.applyStyle();
        });
    }
}

Widget.Lightbox.prototype.effects = function() {
    if ( arguments.length > 0 ) {
        this._effects = [];
        for (var i=0; i<arguments.length; i++) {
            this._effects.push(arguments[i]);
        }
    }
    return this._effects;
}

Widget.Lightbox.prototype.applyEffects = function() {
    if (!this._effects)
        return;
    for (var i=0;i<this._effects.length;i++) {
        this.applyEffect(this._effects[i]);
    }
}

Widget.Lightbox.prototype.applyEffect = function(effect) {
    var func_name = "applyEffect" + effect;
    if ( typeof this[func_name] == 'function') {
        this[func_name]();
    }
}

// Require Effect.RoundedCorners
Widget.Lightbox.prototype.applyEffectRoundedCorners = function() {
    divs = this.divs
    if ( ! divs ) { return; }
    if ( typeof Effect.RoundedCorners == 'undefined' ) { return; }
    divs.contentWrapper.style.border="none";
    var bs = divs.contentWrapper.getElementsByTagName("b");
    for (var i = 0; i < bs.length; i++) {
        if(bs[i].className.match(/rounded-corners-/)) {
            return;
        }
    }
    for (var i=1; i< 5; i++) {
        Effect.RoundedCorners._Styles.push(
            [ ".rounded-corners-" + i,
              "opacity: 0.4",
              "filter: alpha(opacity=40)"
             ]
        );
    }

    Effect.RoundedCorners._addStyles();
    Effect.RoundedCorners._roundCorners(
        divs.contentWrapper,
        {   'top': true,
            'bottom':true,
            'color':'black'
            }
        );
}

// A Generator function for scriptaculous effects.
;(function () {
    var effects = ['Appear', 'Grow', 'BlindDown', 'Shake'];
    for (var i=0; i<effects.length; i++) {
        var name = "applyEffect" + effects[i];
        Widget.Lightbox.prototype[name] = function(effect) {
            return function() {
                if ( ! this.divs ) { return; }
                if ( typeof Effect[effect] == 'undefined' ) { return; }
                if (effect != 'Shake')
                    this.divs.contentWrapper.style.display="none";
                Effect[effect](this.divs.contentWrapper, { duration: 2.0 });
            }
        }(effects[i]);
    }
})();



/**

*/
