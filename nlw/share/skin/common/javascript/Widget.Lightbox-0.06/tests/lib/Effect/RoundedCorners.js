JSAN.use("DOM.Ready");

if ( typeof Effect == "undefined" ) Effect = {};

Effect.RoundedCorners = {};

Effect.RoundedCorners.VERSION = "0.12";

Effect.RoundedCorners.roundCorners = function (params) {
    if ( typeof params == "string" ) {
        params = { "elementId": params };
    }

    if ( ! params["elementId"] ) {
        throw new Error("Effect.RoundedCorners requires an elementId parameter");
    }

    Effect.RoundedCorners._addStyles();

    if ( ! params.hasOwnProperty("top") ) {
        params["top"] = true;
    }

    if ( ! params.hasOwnProperty("bottom") ) {
        params["bottom"] = true;
    }

    var callback = function () {
        var elt = document.getElementById( params.elementId );
        if ( ! elt ) { return }
        Effect.RoundedCorners._roundCorners( elt, params );
    };
    DOM.Ready.onDOMDone(callback);
}

Effect.RoundedCorners._roundCorners = function (elt, params) {
    var color = params["color"];
    if ( ! color ) {
        var current_elt = elt.parentNode;
        while ( current_elt && ( ! color || color == "transparent" ) ) {
            try {
                color = window.getComputedStyle( current_elt, null ).backgroundColor;
            }
            /* at least on Firefox calling getComputedStyle on the
             * root HTML node seems to produce an error */
            catch (e) {}
            current_elt = current_elt.parentNode;
        }

        if ( color == undefined || color == "transparent" ) {
            color = "white";
        }
    }

    if ( params["top"] ) {
        Effect.RoundedCorners._roundUpperCorners( elt, color );
    }

    if ( params["bottom"] ) {
        Effect.RoundedCorners._roundBottomCorners( elt, color );
    }

}

Effect.RoundedCorners._roundUpperCorners = function (elt, color) {
    var container =
       Effect.RoundedCorners._makeElements( color, [ "1", "2", "3", "4" ] );

    elt.insertBefore( container, elt.firstChild );
}

Effect.RoundedCorners._roundBottomCorners = function (elt, color) {
    var container =
       Effect.RoundedCorners._makeElements( color, [ "4", "3", "2", "1" ] );

    elt.appendChild(container);
}

var foo = 1;
Effect.RoundedCorners._makeElements = function (color, order) {
    var container = document.createElement("b");
    container.className = "rounded-corners-container";

    while ( order.length ) {
        var b_tag = document.createElement("b");
        b_tag.className = "rounded-corners-" + order.shift();
        b_tag.style.backgroundColor = "transparent";
        b_tag.style.borderColor = color;

        container.appendChild(b_tag);
    }

    return container;
}

Effect.RoundedCorners._Styles = [
    [ ".rounded-corners-container",
      "display: block",
      "background-color: transparent" ],

    [ ".rounded-corners-container *",
      "display: block",
      "height: 1px",
      "overflow: hidden",
      "font-size: 1px",
      "border-style: solid",
      "border-width: 0px 1px"
    ],

    [ ".rounded-corners-1",
      "border-left-width: 5px",
      "border-right-width: 5px"
    ],

    [ ".rounded-corners-2",
      "border-left-width: 3px",
      "border-right-width: 3px"
    ],

    [ ".rounded-corners-3",
      "border-left-width: 2px",
      "border-right-width: 2px"
    ],

    [ ".rounded-corners-4",
      "height: 2px"
    ]
];

Effect.RoundedCorners._StylesAdded = 0;
Effect.RoundedCorners._addStyles = function () {
    if (Effect.RoundedCorners._StylesAdded) {
        return;
    }

    var styles = Effect.RoundedCorners._Styles;
    var style_string = "";

    for ( var i = 0; i < styles.length; i++ ) {
        var style = styles[i];

        style_string =
            style_string
            + style.shift()
            + " {\n  "
            + style.join(";\n  ")
            + ";\n}\n\n";
    }

    var style_elt = document.createElement("style");
    style_elt.setAttribute("type", "text/css");

    if ( style_elt.styleSheet ) { /* IE */
        style_elt.styleSheet.cssText = style_string;
    }
    else { /* w3c */
        var style_text = document.createTextNode(style_string);
        style_elt.appendChild(style_text);
    }

    var head = document.getElementsByTagName("head")[0];
    head.appendChild(style_elt);
    
    Effect.RoundedCorners._StylesAdded = 1;
}

/*

*/
