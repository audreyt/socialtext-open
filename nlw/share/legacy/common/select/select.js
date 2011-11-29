(function(){
/*
 * jQuery 1.2.1 - New Wave Javascript
 *
 * Copyright (c) 2007 John Resig (jquery.com)
 * Dual licensed under the MIT (MIT-LICENSE.txt)
 * and GPL (GPL-LICENSE.txt) licenses.
 *
 * $Date: 2007-09-16 23:42:06 -0400 (Sun, 16 Sep 2007) $
 * $Rev: 3353 $
 */

// Map over jQuery in case of overwrite
if ( typeof jQuery != "undefined" )
	var _jQuery = jQuery;

var jQuery = window.jQuery = function(selector, context) {
	// If the context is a namespace object, return a new object
	return this instanceof jQuery ?
		this.init(selector, context) :
		new jQuery(selector, context);
};

// Map over the $ in case of overwrite
if ( typeof $ != "undefined" )
	var _$ = $;
	
// Map the jQuery namespace to the '$' one
window.$ = jQuery;

var quickExpr = /^[^<]*(<(.|\s)+>)[^>]*$|^#(\w+)$/;

jQuery.fn = jQuery.prototype = {
	init: function(selector, context) {
		// Make sure that a selection was provided
		selector = selector || document;

		// Handle HTML strings
		if ( typeof selector  == "string" ) {
			var m = quickExpr.exec(selector);
			if ( m && (m[1] || !context) ) {
				// HANDLE: $(html) -> $(array)
				if ( m[1] )
					selector = jQuery.clean( [ m[1] ], context );

				// HANDLE: $("#id")
				else {
					var tmp = document.getElementById( m[3] );
					if ( tmp )
						// Handle the case where IE and Opera return items
						// by name instead of ID
						if ( tmp.id != m[3] )
							return jQuery().find( selector );
						else {
							this[0] = tmp;
							this.length = 1;
							return this;
						}
					else
						selector = [];
				}

			// HANDLE: $(expr)
			} else
				return new jQuery( context ).find( selector );

		// HANDLE: $(function)
		// Shortcut for document ready
		} else if ( jQuery.isFunction(selector) )
			return new jQuery(document)[ jQuery.fn.ready ? "ready" : "load" ]( selector );

		return this.setArray(
			// HANDLE: $(array)
			selector.constructor == Array && selector ||

			// HANDLE: $(arraylike)
			// Watch for when an array-like object is passed as the selector
			(selector.jquery || selector.length && selector != window && !selector.nodeType && selector[0] != undefined && selector[0].nodeType) && jQuery.makeArray( selector ) ||

			// HANDLE: $(*)
			[ selector ] );
	},
	
	jquery: "1.2.1",

	size: function() {
		return this.length;
	},
	
	length: 0,

	get: function( num ) {
		return num == undefined ?

			// Return a 'clean' array
			jQuery.makeArray( this ) :

			// Return just the object
			this[num];
	},
	
	pushStack: function( a ) {
		var ret = jQuery(a);
		ret.prevObject = this;
		return ret;
	},
	
	setArray: function( a ) {
		this.length = 0;
		Array.prototype.push.apply( this, a );
		return this;
	},

	each: function( fn, args ) {
		return jQuery.each( this, fn, args );
	},

	index: function( obj ) {
		var pos = -1;
		this.each(function(i){
			if ( this == obj ) pos = i;
		});
		return pos;
	},

	attr: function( key, value, type ) {
		var obj = key;
		
		// Look for the case where we're accessing a style value
		if ( key.constructor == String )
			if ( value == undefined )
				return this.length && jQuery[ type || "attr" ]( this[0], key ) || undefined;
			else {
				obj = {};
				obj[ key ] = value;
			}
		
		// Check to see if we're setting style values
		return this.each(function(index){
			// Set all the styles
			for ( var prop in obj )
				jQuery.attr(
					type ? this.style : this,
					prop, jQuery.prop(this, obj[prop], type, index, prop)
				);
		});
	},

	css: function( key, value ) {
		return this.attr( key, value, "curCSS" );
	},

	text: function(e) {
		if ( typeof e != "object" && e != null )
			return this.empty().append( document.createTextNode( e ) );

		var t = "";
		jQuery.each( e || this, function(){
			jQuery.each( this.childNodes, function(){
				if ( this.nodeType != 8 )
					t += this.nodeType != 1 ?
						this.nodeValue : jQuery.fn.text([ this ]);
			});
		});
		return t;
	},

	wrapAll: function(html) {
		if ( this[0] )
			// The elements to wrap the target around
			jQuery(html, this[0].ownerDocument)
				.clone()
				.insertBefore(this[0])
				.map(function(){
					var elem = this;
					while ( elem.firstChild )
						elem = elem.firstChild;
					return elem;
				})
				.append(this);

		return this;
	},

	wrapInner: function(html) {
		return this.each(function(){
			jQuery(this).contents().wrapAll(html);
		});
	},

	wrap: function(html) {
		return this.each(function(){
			jQuery(this).wrapAll(html);
		});
	},

	append: function() {
		return this.domManip(arguments, true, 1, function(a){
			this.appendChild( a );
		});
	},

	prepend: function() {
		return this.domManip(arguments, true, -1, function(a){
			this.insertBefore( a, this.firstChild );
		});
	},
	
	before: function() {
		return this.domManip(arguments, false, 1, function(a){
			this.parentNode.insertBefore( a, this );
		});
	},

	after: function() {
		return this.domManip(arguments, false, -1, function(a){
			this.parentNode.insertBefore( a, this.nextSibling );
		});
	},

	end: function() {
		return this.prevObject || jQuery([]);
	},

	find: function(t) {
		var data = jQuery.map(this, function(a){ return jQuery.find(t,a); });
		return this.pushStack( /[^+>] [^+>]/.test( t ) || t.indexOf("..") > -1 ?
			jQuery.unique( data ) : data );
	},

	clone: function(events) {
		// Do the clone
		var ret = this.map(function(){
			return this.outerHTML ? jQuery(this.outerHTML)[0] : this.cloneNode(true);
		});

		// Need to set the expando to null on the cloned set if it exists
		// removeData doesn't work here, IE removes it from the original as well
		// this is primarily for IE but the data expando shouldn't be copied over in any browser
		var clone = ret.find("*").andSelf().each(function(){
			if ( this[ expando ] != undefined )
				this[ expando ] = null;
		});
		
		// Copy the events from the original to the clone
		if (events === true)
			this.find("*").andSelf().each(function(i) {
				var events = jQuery.data(this, "events");
				for ( var type in events )
					for ( var handler in events[type] )
						jQuery.event.add(clone[i], type, events[type][handler], events[type][handler].data);
			});

		// Return the cloned set
		return ret;
	},

	filter: function(t) {
		return this.pushStack(
			jQuery.isFunction( t ) &&
			jQuery.grep(this, function(el, index){
				return t.apply(el, [index]);
			}) ||

			jQuery.multiFilter(t,this) );
	},

	not: function(t) {
		return this.pushStack(
			t.constructor == String &&
			jQuery.multiFilter(t, this, true) ||

			jQuery.grep(this, function(a) {
				return ( t.constructor == Array || t.jquery )
					? jQuery.inArray( a, t ) < 0
					: a != t;
			})
		);
	},

	add: function(t) {
		return this.pushStack( jQuery.merge(
			this.get(),
			t.constructor == String ?
				jQuery(t).get() :
				t.length != undefined && (!t.nodeName || jQuery.nodeName(t, "form")) ?
					t : [t] )
		);
	},

	is: function(expr) {
		return expr ? jQuery.multiFilter(expr,this).length > 0 : false;
	},

	hasClass: function(expr) {
		return this.is("." + expr);
	},
	
	val: function( val ) {
		if ( val == undefined ) {
			if ( this.length ) {
				var elem = this[0];
		    	
				// We need to handle select boxes special
				if ( jQuery.nodeName(elem, "select") ) {
					var index = elem.selectedIndex,
						a = [],
						options = elem.options,
						one = elem.type == "select-one";
					
					// Nothing was selected
					if ( index < 0 )
						return null;

					// Loop through all the selected options
					for ( var i = one ? index : 0, max = one ? index + 1 : options.length; i < max; i++ ) {
						var option = options[i];
						if ( option.selected ) {
							// Get the specifc value for the option
							var val = jQuery.browser.msie && !option.attributes["value"].specified ? option.text : option.value;
							
							// We don't need an array for one selects
							if ( one )
								return val;
							
							// Multi-Selects return an array
							a.push(val);
						}
					}
					
					return a;
					
				// Everything else, we just grab the value
				} else
					return this[0].value.replace(/\r/g, "");
			}
		} else
			return this.each(function(){
				if ( val.constructor == Array && /radio|checkbox/.test(this.type) )
					this.checked = (jQuery.inArray(this.value, val) >= 0 ||
						jQuery.inArray(this.name, val) >= 0);
				else if ( jQuery.nodeName(this, "select") ) {
					var tmp = val.constructor == Array ? val : [val];

					jQuery("option", this).each(function(){
						this.selected = (jQuery.inArray(this.value, tmp) >= 0 ||
						jQuery.inArray(this.text, tmp) >= 0);
					});

					if ( !tmp.length )
						this.selectedIndex = -1;
				} else
					this.value = val;
			});
	},
	
	html: function( val ) {
		return val == undefined ?
			( this.length ? this[0].innerHTML : null ) :
			this.empty().append( val );
	},

	replaceWith: function( val ) {
		return this.after( val ).remove();
	},

	eq: function(i){
		return this.slice(i, i+1);
	},

	slice: function() {
		return this.pushStack( Array.prototype.slice.apply( this, arguments ) );
	},

	map: function(fn) {
		return this.pushStack(jQuery.map( this, function(elem,i){
			return fn.call( elem, i, elem );
		}));
	},

	andSelf: function() {
		return this.add( this.prevObject );
	},
	
	domManip: function(args, table, dir, fn) {
		var clone = this.length > 1, a; 

		return this.each(function(){
			if ( !a ) {
				a = jQuery.clean(args, this.ownerDocument);
				if ( dir < 0 )
					a.reverse();
			}

			var obj = this;

			if ( table && jQuery.nodeName(this, "table") && jQuery.nodeName(a[0], "tr") )
				obj = this.getElementsByTagName("tbody")[0] || this.appendChild(document.createElement("tbody"));

			jQuery.each( a, function(){
				var elem = clone ? this.cloneNode(true) : this;
				if ( !evalScript(0, elem) )
					fn.call( obj, elem );
			});
		});
	}
};

function evalScript(i, elem){
	var script = jQuery.nodeName(elem, "script");

	if ( script ) {
		if ( elem.src )
			jQuery.ajax({ url: elem.src, async: false, dataType: "script" });
		else
			jQuery.globalEval( elem.text || elem.textContent || elem.innerHTML || "" );
	
		if ( elem.parentNode )
			elem.parentNode.removeChild(elem);

	} else if ( elem.nodeType == 1 )
    jQuery("script", elem).each(evalScript);

	return script;
}

jQuery.extend = jQuery.fn.extend = function() {
	// copy reference to target object
	var target = arguments[0] || {}, a = 1, al = arguments.length, deep = false;

	// Handle a deep copy situation
	if ( target.constructor == Boolean ) {
		deep = target;
		target = arguments[1] || {};
	}

	// extend jQuery itself if only one argument is passed
	if ( al == 1 ) {
		target = this;
		a = 0;
	}

	var prop;

	for ( ; a < al; a++ )
		// Only deal with non-null/undefined values
		if ( (prop = arguments[a]) != null )
			// Extend the base object
			for ( var i in prop ) {
				// Prevent never-ending loop
				if ( target == prop[i] )
					continue;

				// Recurse if we're merging object values
				if ( deep && typeof prop[i] == 'object' && target[i] )
					jQuery.extend( target[i], prop[i] );

				// Don't bring in undefined values
				else if ( prop[i] != undefined )
					target[i] = prop[i];
			}

	// Return the modified object
	return target;
};

var expando = "jQuery" + (new Date()).getTime(), uuid = 0, win = {};

jQuery.extend({
	noConflict: function(deep) {
		window.$ = _$;
		if ( deep )
			window.jQuery = _jQuery;
		return jQuery;
	},

	// This may seem like some crazy code, but trust me when I say that this
	// is the only cross-browser way to do this. --John
	isFunction: function( fn ) {
		return !!fn && typeof fn != "string" && !fn.nodeName && 
			fn.constructor != Array && /function/i.test( fn + "" );
	},
	
	// check if an element is in a XML document
	isXMLDoc: function(elem) {
		return elem.documentElement && !elem.body ||
			elem.tagName && elem.ownerDocument && !elem.ownerDocument.body;
	},

	// Evalulates a script in a global context
	// Evaluates Async. in Safari 2 :-(
	globalEval: function( data ) {
		data = jQuery.trim( data );
		if ( data ) {
			if ( window.execScript )
				window.execScript( data );
			else if ( jQuery.browser.safari )
				// safari doesn't provide a synchronous global eval
				window.setTimeout( data, 0 );
			else
				eval.call( window, data );
		}
	},

	nodeName: function( elem, name ) {
		return elem.nodeName && elem.nodeName.toUpperCase() == name.toUpperCase();
	},
	
	cache: {},
	
	data: function( elem, name, data ) {
		elem = elem == window ? win : elem;

		var id = elem[ expando ];

		// Compute a unique ID for the element
		if ( !id ) 
			id = elem[ expando ] = ++uuid;

		// Only generate the data cache if we're
		// trying to access or manipulate it
		if ( name && !jQuery.cache[ id ] )
			jQuery.cache[ id ] = {};
		
		// Prevent overriding the named cache with undefined values
		if ( data != undefined )
			jQuery.cache[ id ][ name ] = data;
		
		// Return the named cache data, or the ID for the element	
		return name ? jQuery.cache[ id ][ name ] : id;
	},
	
	removeData: function( elem, name ) {
		elem = elem == window ? win : elem;

		var id = elem[ expando ];

		// If we want to remove a specific section of the element's data
		if ( name ) {
			if ( jQuery.cache[ id ] ) {
				// Remove the section of cache data
				delete jQuery.cache[ id ][ name ];

				// If we've removed all the data, remove the element's cache
				name = "";
				for ( name in jQuery.cache[ id ] ) break;
				if ( !name )
					jQuery.removeData( elem );
			}

		// Otherwise, we want to remove all of the element's data
		} else {
			// Clean up the element expando
			try {
				delete elem[ expando ];
			} catch(e){
				// IE has trouble directly removing the expando
				// but it's ok with using removeAttribute
				if ( elem.removeAttribute )
					elem.removeAttribute( expando );
			}

			// Completely remove the data cache
			delete jQuery.cache[ id ];
		}
	},

	// args is for internal usage only
	each: function( obj, fn, args ) {
		if ( args ) {
			if ( obj.length == undefined )
				for ( var i in obj )
					fn.apply( obj[i], args );
			else
				for ( var i = 0, ol = obj.length; i < ol; i++ )
					if ( fn.apply( obj[i], args ) === false ) break;

		// A special, fast, case for the most common use of each
		} else {
			if ( obj.length == undefined )
				for ( var i in obj )
					fn.call( obj[i], i, obj[i] );
			else
				for ( var i = 0, ol = obj.length, val = obj[0]; 
					i < ol && fn.call(val,i,val) !== false; val = obj[++i] ){}
		}

		return obj;
	},
	
	prop: function(elem, value, type, index, prop){
			// Handle executable functions
			if ( jQuery.isFunction( value ) )
				value = value.call( elem, [index] );
				
			// exclude the following css properties to add px
			var exclude = /z-?index|font-?weight|opacity|zoom|line-?height/i;

			// Handle passing in a number to a CSS property
			return value && value.constructor == Number && type == "curCSS" && !exclude.test(prop) ?
				value + "px" :
				value;
	},

	className: {
		// internal only, use addClass("class")
		add: function( elem, c ){
			jQuery.each( (c || "").split(/\s+/), function(i, cur){
				if ( !jQuery.className.has( elem.className, cur ) )
					elem.className += ( elem.className ? " " : "" ) + cur;
			});
		},

		// internal only, use removeClass("class")
		remove: function( elem, c ){
			elem.className = c != undefined ?
				jQuery.grep( elem.className.split(/\s+/), function(cur){
					return !jQuery.className.has( c, cur );	
				}).join(" ") : "";
		},

		// internal only, use is(".class")
		has: function( t, c ) {
			return jQuery.inArray( c, (t.className || t).toString().split(/\s+/) ) > -1;
		}
	},

	swap: function(e,o,f) {
		for ( var i in o ) {
			e.style["old"+i] = e.style[i];
			e.style[i] = o[i];
		}
		f.apply( e, [] );
		for ( var i in o )
			e.style[i] = e.style["old"+i];
	},

	css: function(e,p) {
		if ( p == "height" || p == "width" ) {
			var old = {}, oHeight, oWidth, d = ["Top","Bottom","Right","Left"];

			jQuery.each( d, function(){
				old["padding" + this] = 0;
				old["border" + this + "Width"] = 0;
			});

			jQuery.swap( e, old, function() {
				if ( jQuery(e).is(':visible') ) {
					oHeight = e.offsetHeight;
					oWidth = e.offsetWidth;
				} else {
					e = jQuery(e.cloneNode(true))
						.find(":radio").removeAttr("checked").end()
						.css({
							visibility: "hidden", position: "absolute", display: "block", right: "0", left: "0"
						}).appendTo(e.parentNode)[0];

					var parPos = jQuery.css(e.parentNode,"position") || "static";
					if ( parPos == "static" )
						e.parentNode.style.position = "relative";

					oHeight = e.clientHeight;
					oWidth = e.clientWidth;

					if ( parPos == "static" )
						e.parentNode.style.position = "static";

					e.parentNode.removeChild(e);
				}
			});

			return p == "height" ? oHeight : oWidth;
		}

		return jQuery.curCSS( e, p );
	},

	curCSS: function(elem, prop, force) {
		var ret, stack = [], swap = [];

		// A helper method for determining if an element's values are broken
		function color(a){
			if ( !jQuery.browser.safari )
				return false;

			var ret = document.defaultView.getComputedStyle(a,null);
			return !ret || ret.getPropertyValue("color") == "";
		}

		if (prop == "opacity" && jQuery.browser.msie) {
			ret = jQuery.attr(elem.style, "opacity");
			return ret == "" ? "1" : ret;
		}
		
		if (prop.match(/float/i))
			prop = styleFloat;

		if (!force && elem.style[prop])
			ret = elem.style[prop];

		else if (document.defaultView && document.defaultView.getComputedStyle) {

			if (prop.match(/float/i))
				prop = "float";

			prop = prop.replace(/([A-Z])/g,"-$1").toLowerCase();
			var cur = document.defaultView.getComputedStyle(elem, null);

			if ( cur && !color(elem) )
				ret = cur.getPropertyValue(prop);

			// If the element isn't reporting its values properly in Safari
			// then some display: none elements are involved
			else {
				// Locate all of the parent display: none elements
				for ( var a = elem; a && color(a); a = a.parentNode )
					stack.unshift(a);

				// Go through and make them visible, but in reverse
				// (It would be better if we knew the exact display type that they had)
				for ( a = 0; a < stack.length; a++ )
					if ( color(stack[a]) ) {
						swap[a] = stack[a].style.display;
						stack[a].style.display = "block";
					}

				// Since we flip the display style, we have to handle that
				// one special, otherwise get the value
				ret = prop == "display" && swap[stack.length-1] != null ?
					"none" :
					document.defaultView.getComputedStyle(elem,null).getPropertyValue(prop) || "";

				// Finally, revert the display styles back
				for ( a = 0; a < swap.length; a++ )
					if ( swap[a] != null )
						stack[a].style.display = swap[a];
			}

			if ( prop == "opacity" && ret == "" )
				ret = "1";

		} else if (elem.currentStyle) {
			var newProp = prop.replace(/\-(\w)/g,function(m,c){return c.toUpperCase();});
			ret = elem.currentStyle[prop] || elem.currentStyle[newProp];

			// From the awesome hack by Dean Edwards
			// http://erik.eae.net/archives/2007/07/27/18.54.15/#comment-102291

			// If we're not dealing with a regular pixel number
			// but a number that has a weird ending, we need to convert it to pixels
			if ( !/^\d+(px)?$/i.test(ret) && /^\d/.test(ret) ) {
				var style = elem.style.left;
				var runtimeStyle = elem.runtimeStyle.left;
				elem.runtimeStyle.left = elem.currentStyle.left;
				elem.style.left = ret || 0;
				ret = elem.style.pixelLeft + "px";
				elem.style.left = style;
				elem.runtimeStyle.left = runtimeStyle;
			}
		}

		return ret;
	},
	
	clean: function(a, doc) {
		var r = [];
		doc = doc || document;

		jQuery.each( a, function(i,arg){
			if ( !arg ) return;

			if ( arg.constructor == Number )
				arg = arg.toString();
			
			// Convert html string into DOM nodes
			if ( typeof arg == "string" ) {
				// Fix "XHTML"-style tags in all browsers
				arg = arg.replace(/(<(\w+)[^>]*?)\/>/g, function(m, all, tag){
					return tag.match(/^(abbr|br|col|img|input|link|meta|param|hr|area)$/i)? m : all+"></"+tag+">";
				});

				// Trim whitespace, otherwise indexOf won't work as expected
				var s = jQuery.trim(arg).toLowerCase(), div = doc.createElement("div"), tb = [];

				var wrap =
					// option or optgroup
					!s.indexOf("<opt") &&
					[1, "<select>", "</select>"] ||
					
					!s.indexOf("<leg") &&
					[1, "<fieldset>", "</fieldset>"] ||
					
					s.match(/^<(thead|tbody|tfoot|colg|cap)/) &&
					[1, "<table>", "</table>"] ||
					
					!s.indexOf("<tr") &&
					[2, "<table><tbody>", "</tbody></table>"] ||
					
				 	// <thead> matched above
					(!s.indexOf("<td") || !s.indexOf("<th")) &&
					[3, "<table><tbody><tr>", "</tr></tbody></table>"] ||
					
					!s.indexOf("<col") &&
					[2, "<table><tbody></tbody><colgroup>", "</colgroup></table>"] ||

					// IE can't serialize <link> and <script> tags normally
					jQuery.browser.msie &&
					[1, "div<div>", "</div>"] ||
					
					[0,"",""];

				// Go to html and back, then peel off extra wrappers
				div.innerHTML = wrap[1] + arg + wrap[2];
				
				// Move to the right depth
				while ( wrap[0]-- )
					div = div.lastChild;
				
				// Remove IE's autoinserted <tbody> from table fragments
				if ( jQuery.browser.msie ) {
					
					// String was a <table>, *may* have spurious <tbody>
					if ( !s.indexOf("<table") && s.indexOf("<tbody") < 0 ) 
						tb = div.firstChild && div.firstChild.childNodes;
						
					// String was a bare <thead> or <tfoot>
					else if ( wrap[1] == "<table>" && s.indexOf("<tbody") < 0 )
						tb = div.childNodes;

					for ( var n = tb.length-1; n >= 0 ; --n )
						if ( jQuery.nodeName(tb[n], "tbody") && !tb[n].childNodes.length )
							tb[n].parentNode.removeChild(tb[n]);
	
					// IE completely kills leading whitespace when innerHTML is used	
					if ( /^\s/.test(arg) )	
						div.insertBefore( doc.createTextNode( arg.match(/^\s*/)[0] ), div.firstChild );

				}
				
				arg = jQuery.makeArray( div.childNodes );
			}

			if ( 0 === arg.length && (!jQuery.nodeName(arg, "form") && !jQuery.nodeName(arg, "select")) )
				return;

			if ( arg[0] == undefined || jQuery.nodeName(arg, "form") || arg.options )
				r.push( arg );
			else
				r = jQuery.merge( r, arg );

		});

		return r;
	},
	
	attr: function(elem, name, value){
		var fix = jQuery.isXMLDoc(elem) ? {} : jQuery.props;

		// Safari mis-reports the default selected property of a hidden option
		// Accessing the parent's selectedIndex property fixes it
		if ( name == "selected" && jQuery.browser.safari )
			elem.parentNode.selectedIndex;
		
		// Certain attributes only work when accessed via the old DOM 0 way
		if ( fix[name] ) {
			if ( value != undefined ) elem[fix[name]] = value;
			return elem[fix[name]];
		} else if ( jQuery.browser.msie && name == "style" )
			return jQuery.attr( elem.style, "cssText", value );

		else if ( value == undefined && jQuery.browser.msie && jQuery.nodeName(elem, "form") && (name == "action" || name == "method") )
			return elem.getAttributeNode(name).nodeValue;

		// IE elem.getAttribute passes even for style
		else if ( elem.tagName ) {

			if ( value != undefined ) {
				if ( name == "type" && jQuery.nodeName(elem,"input") && elem.parentNode )
					throw "type property can't be changed";
				elem.setAttribute( name, value );
			}

			if ( jQuery.browser.msie && /href|src/.test(name) && !jQuery.isXMLDoc(elem) ) 
				return elem.getAttribute( name, 2 );

			return elem.getAttribute( name );

		// elem is actually elem.style ... set the style
		} else {
			// IE actually uses filters for opacity
			if ( name == "opacity" && jQuery.browser.msie ) {
				if ( value != undefined ) {
					// IE has trouble with opacity if it does not have layout
					// Force it by setting the zoom level
					elem.zoom = 1; 
	
					// Set the alpha filter to set the opacity
					elem.filter = (elem.filter || "").replace(/alpha\([^)]*\)/,"") +
						(parseFloat(value).toString() == "NaN" ? "" : "alpha(opacity=" + value * 100 + ")");
				}
	
				return elem.filter ? 
					(parseFloat( elem.filter.match(/opacity=([^)]*)/)[1] ) / 100).toString() : "";
			}
			name = name.replace(/-([a-z])/ig,function(z,b){return b.toUpperCase();});
			if ( value != undefined ) elem[name] = value;
			return elem[name];
		}
	},
	
	trim: function(t){
		return (t||"").replace(/^\s+|\s+$/g, "");
	},

	makeArray: function( a ) {
		var r = [];

		// Need to use typeof to fight Safari childNodes crashes
		if ( typeof a != "array" )
			for ( var i = 0, al = a.length; i < al; i++ )
				r.push( a[i] );
		else
			r = a.slice( 0 );

		return r;
	},

	inArray: function( b, a ) {
		for ( var i = 0, al = a.length; i < al; i++ )
			if ( a[i] == b )
				return i;
		return -1;
	},

	merge: function(first, second) {
		// We have to loop this way because IE & Opera overwrite the length
		// expando of getElementsByTagName

		// Also, we need to make sure that the correct elements are being returned
		// (IE returns comment nodes in a '*' query)
		if ( jQuery.browser.msie ) {
			for ( var i = 0; second[i]; i++ )
				if ( second[i].nodeType != 8 )
					first.push(second[i]);
		} else
			for ( var i = 0; second[i]; i++ )
				first.push(second[i]);

		return first;
	},

	unique: function(first) {
		var r = [], done = {};

		try {
			for ( var i = 0, fl = first.length; i < fl; i++ ) {
				var id = jQuery.data(first[i]);
				if ( !done[id] ) {
					done[id] = true;
					r.push(first[i]);
				}
			}
		} catch(e) {
			r = first;
		}

		return r;
	},

	grep: function(elems, fn, inv) {
		// If a string is passed in for the function, make a function
		// for it (a handy shortcut)
		if ( typeof fn == "string" )
			fn = eval("false||function(a,i){return " + fn + "}");

		var result = [];

		// Go through the array, only saving the items
		// that pass the validator function
		for ( var i = 0, el = elems.length; i < el; i++ )
			if ( !inv && fn(elems[i],i) || inv && !fn(elems[i],i) )
				result.push( elems[i] );

		return result;
	},

	map: function(elems, fn) {
		// If a string is passed in for the function, make a function
		// for it (a handy shortcut)
		if ( typeof fn == "string" )
			fn = eval("false||function(a){return " + fn + "}");

		var result = [];

		// Go through the array, translating each of the items to their
		// new value (or values).
		for ( var i = 0, el = elems.length; i < el; i++ ) {
			var val = fn(elems[i],i);

			if ( val !== null && val != undefined ) {
				if ( val.constructor != Array ) val = [val];
				result = result.concat( val );
			}
		}

		return result;
	}
});

var userAgent = navigator.userAgent.toLowerCase();

// Figure out what browser is being used
jQuery.browser = {
	version: (userAgent.match(/.+(?:rv|it|ra|ie)[\/: ]([\d.]+)/) || [])[1],
	safari: /webkit/.test(userAgent),
	opera: /opera/.test(userAgent),
	msie: /msie/.test(userAgent) && !/opera/.test(userAgent),
	mozilla: /mozilla/.test(userAgent) && !/(compatible|webkit)/.test(userAgent)
};

var styleFloat = jQuery.browser.msie ? "styleFloat" : "cssFloat";
	
jQuery.extend({
	// Check to see if the W3C box model is being used
	boxModel: !jQuery.browser.msie || document.compatMode == "CSS1Compat",
	
	styleFloat: jQuery.browser.msie ? "styleFloat" : "cssFloat",
	
	props: {
		"for": "htmlFor",
		"class": "className",
		"float": styleFloat,
		cssFloat: styleFloat,
		styleFloat: styleFloat,
		innerHTML: "innerHTML",
		className: "className",
		value: "value",
		disabled: "disabled",
		checked: "checked",
		readonly: "readOnly",
		selected: "selected",
		maxlength: "maxLength"
	}
});

jQuery.each({
	parent: "a.parentNode",
	parents: "jQuery.dir(a,'parentNode')",
	next: "jQuery.nth(a,2,'nextSibling')",
	prev: "jQuery.nth(a,2,'previousSibling')",
	nextAll: "jQuery.dir(a,'nextSibling')",
	prevAll: "jQuery.dir(a,'previousSibling')",
	siblings: "jQuery.sibling(a.parentNode.firstChild,a)",
	children: "jQuery.sibling(a.firstChild)",
	contents: "jQuery.nodeName(a,'iframe')?a.contentDocument||a.contentWindow.document:jQuery.makeArray(a.childNodes)"
}, function(i,n){
	jQuery.fn[ i ] = function(a) {
		var ret = jQuery.map(this,n);
		if ( a && typeof a == "string" )
			ret = jQuery.multiFilter(a,ret);
		return this.pushStack( jQuery.unique(ret) );
	};
});

jQuery.each({
	appendTo: "append",
	prependTo: "prepend",
	insertBefore: "before",
	insertAfter: "after",
	replaceAll: "replaceWith"
}, function(i,n){
	jQuery.fn[ i ] = function(){
		var a = arguments;
		return this.each(function(){
			for ( var j = 0, al = a.length; j < al; j++ )
				jQuery(a[j])[n]( this );
		});
	};
});

jQuery.each( {
	removeAttr: function( key ) {
		jQuery.attr( this, key, "" );
		this.removeAttribute( key );
	},
	addClass: function(c){
		jQuery.className.add(this,c);
	},
	removeClass: function(c){
		jQuery.className.remove(this,c);
	},
	toggleClass: function( c ){
		jQuery.className[ jQuery.className.has(this,c) ? "remove" : "add" ](this, c);
	},
	remove: function(a){
		if ( !a || jQuery.filter( a, [this] ).r.length ) {
			jQuery.removeData( this );
			this.parentNode.removeChild( this );
		}
	},
	empty: function() {
		// Clean up the cache
		jQuery("*", this).each(function(){ jQuery.removeData(this); });

		while ( this.firstChild )
			this.removeChild( this.firstChild );
	}
}, function(i,n){
	jQuery.fn[ i ] = function() {
		return this.each( n, arguments );
	};
});

jQuery.each( [ "Height", "Width" ], function(i,name){
	var n = name.toLowerCase();
	
	jQuery.fn[ n ] = function(h) {
		return this[0] == window ?
			jQuery.browser.safari && self["inner" + name] ||
			jQuery.boxModel && Math.max(document.documentElement["client" + name], document.body["client" + name]) ||
			document.body["client" + name] :
		
			this[0] == document ?
				Math.max( document.body["scroll" + name], document.body["offset" + name] ) :
        
				h == undefined ?
					( this.length ? jQuery.css( this[0], n ) : null ) :
					this.css( n, h.constructor == String ? h : h + "px" );
	};
});

var chars = jQuery.browser.safari && parseInt(jQuery.browser.version) < 417 ?
		"(?:[\\w*_-]|\\\\.)" :
		"(?:[\\w\u0128-\uFFFF*_-]|\\\\.)",
	quickChild = new RegExp("^>\\s*(" + chars + "+)"),
	quickID = new RegExp("^(" + chars + "+)(#)(" + chars + "+)"),
	quickClass = new RegExp("^([#.]?)(" + chars + "*)");

jQuery.extend({
	expr: {
		"": "m[2]=='*'||jQuery.nodeName(a,m[2])",
		"#": "a.getAttribute('id')==m[2]",
		":": {
			// Position Checks
			lt: "i<m[3]-0",
			gt: "i>m[3]-0",
			nth: "m[3]-0==i",
			eq: "m[3]-0==i",
			first: "i==0",
			last: "i==r.length-1",
			even: "i%2==0",
			odd: "i%2",

			// Child Checks
			"first-child": "a.parentNode.getElementsByTagName('*')[0]==a",
			"last-child": "jQuery.nth(a.parentNode.lastChild,1,'previousSibling')==a",
			"only-child": "!jQuery.nth(a.parentNode.lastChild,2,'previousSibling')",

			// Parent Checks
			parent: "a.firstChild",
			empty: "!a.firstChild",

			// Text Check
			contains: "(a.textContent||a.innerText||jQuery(a).text()||'').indexOf(m[3])>=0",

			// Visibility
			visible: '"hidden"!=a.type&&jQuery.css(a,"display")!="none"&&jQuery.css(a,"visibility")!="hidden"',
			hidden: '"hidden"==a.type||jQuery.css(a,"display")=="none"||jQuery.css(a,"visibility")=="hidden"',

			// Form attributes
			enabled: "!a.disabled",
			disabled: "a.disabled",
			checked: "a.checked",
			selected: "a.selected||jQuery.attr(a,'selected')",

			// Form elements
			text: "'text'==a.type",
			radio: "'radio'==a.type",
			checkbox: "'checkbox'==a.type",
			file: "'file'==a.type",
			password: "'password'==a.type",
			submit: "'submit'==a.type",
			image: "'image'==a.type",
			reset: "'reset'==a.type",
			button: '"button"==a.type||jQuery.nodeName(a,"button")',
			input: "/input|select|textarea|button/i.test(a.nodeName)",

			// :has()
			has: "jQuery.find(m[3],a).length",

			// :header
			header: "/h\\d/i.test(a.nodeName)",

			// :animated
			animated: "jQuery.grep(jQuery.timers,function(fn){return a==fn.elem;}).length"
		}
	},
	
	// The regular expressions that power the parsing engine
	parse: [
		// Match: [@value='test'], [@foo]
		/^(\[) *@?([\w-]+) *([!*$^~=]*) *('?"?)(.*?)\4 *\]/,

		// Match: :contains('foo')
		/^(:)([\w-]+)\("?'?(.*?(\(.*?\))?[^(]*?)"?'?\)/,

		// Match: :even, :last-chlid, #id, .class
		new RegExp("^([:.#]*)(" + chars + "+)")
	],

	multiFilter: function( expr, elems, not ) {
		var old, cur = [];

		while ( expr && expr != old ) {
			old = expr;
			var f = jQuery.filter( expr, elems, not );
			expr = f.t.replace(/^\s*,\s*/, "" );
			cur = not ? elems = f.r : jQuery.merge( cur, f.r );
		}

		return cur;
	},

	find: function( t, context ) {
		// Quickly handle non-string expressions
		if ( typeof t != "string" )
			return [ t ];

		// Make sure that the context is a DOM Element
		if ( context && !context.nodeType )
			context = null;

		// Set the correct context (if none is provided)
		context = context || document;

		// Initialize the search
		var ret = [context], done = [], last;

		// Continue while a selector expression exists, and while
		// we're no longer looping upon ourselves
		while ( t && last != t ) {
			var r = [];
			last = t;

			t = jQuery.trim(t);

			var foundToken = false;

			// An attempt at speeding up child selectors that
			// point to a specific element tag
			var re = quickChild;
			var m = re.exec(t);

			if ( m ) {
				var nodeName = m[1].toUpperCase();

				// Perform our own iteration and filter
				for ( var i = 0; ret[i]; i++ )
					for ( var c = ret[i].firstChild; c; c = c.nextSibling )
						if ( c.nodeType == 1 && (nodeName == "*" || c.nodeName.toUpperCase() == nodeName.toUpperCase()) )
							r.push( c );

				ret = r;
				t = t.replace( re, "" );
				if ( t.indexOf(" ") == 0 ) continue;
				foundToken = true;
			} else {
				re = /^([>+~])\s*(\w*)/i;

				if ( (m = re.exec(t)) != null ) {
					r = [];

					var nodeName = m[2], merge = {};
					m = m[1];

					for ( var j = 0, rl = ret.length; j < rl; j++ ) {
						var n = m == "~" || m == "+" ? ret[j].nextSibling : ret[j].firstChild;
						for ( ; n; n = n.nextSibling )
							if ( n.nodeType == 1 ) {
								var id = jQuery.data(n);

								if ( m == "~" && merge[id] ) break;
								
								if (!nodeName || n.nodeName.toUpperCase() == nodeName.toUpperCase() ) {
									if ( m == "~" ) merge[id] = true;
									r.push( n );
								}
								
								if ( m == "+" ) break;
							}
					}

					ret = r;

					// And remove the token
					t = jQuery.trim( t.replace( re, "" ) );
					foundToken = true;
				}
			}

			// See if there's still an expression, and that we haven't already
			// matched a token
			if ( t && !foundToken ) {
				// Handle multiple expressions
				if ( !t.indexOf(",") ) {
					// Clean the result set
					if ( context == ret[0] ) ret.shift();

					// Merge the result sets
					done = jQuery.merge( done, ret );

					// Reset the context
					r = ret = [context];

					// Touch up the selector string
					t = " " + t.substr(1,t.length);

				} else {
					// Optimize for the case nodeName#idName
					var re2 = quickID;
					var m = re2.exec(t);
					
					// Re-organize the results, so that they're consistent
					if ( m ) {
					   m = [ 0, m[2], m[3], m[1] ];

					} else {
						// Otherwise, do a traditional filter check for
						// ID, class, and element selectors
						re2 = quickClass;
						m = re2.exec(t);
					}

					m[2] = m[2].replace(/\\/g, "");

					var elem = ret[ret.length-1];

					// Try to do a global search by ID, where we can
					if ( m[1] == "#" && elem && elem.getElementById && !jQuery.isXMLDoc(elem) ) {
						// Optimization for HTML document case
						var oid = elem.getElementById(m[2]);
						
						// Do a quick check for the existence of the actual ID attribute
						// to avoid selecting by the name attribute in IE
						// also check to insure id is a string to avoid selecting an element with the name of 'id' inside a form
						if ( (jQuery.browser.msie||jQuery.browser.opera) && oid && typeof oid.id == "string" && oid.id != m[2] )
							oid = jQuery('[@id="'+m[2]+'"]', elem)[0];

						// Do a quick check for node name (where applicable) so
						// that div#foo searches will be really fast
						ret = r = oid && (!m[3] || jQuery.nodeName(oid, m[3])) ? [oid] : [];
					} else {
						// We need to find all descendant elements
						for ( var i = 0; ret[i]; i++ ) {
							// Grab the tag name being searched for
							var tag = m[1] == "#" && m[3] ? m[3] : m[1] != "" || m[0] == "" ? "*" : m[2];

							// Handle IE7 being really dumb about <object>s
							if ( tag == "*" && ret[i].nodeName.toLowerCase() == "object" )
								tag = "param";

							r = jQuery.merge( r, ret[i].getElementsByTagName( tag ));
						}

						// It's faster to filter by class and be done with it
						if ( m[1] == "." )
							r = jQuery.classFilter( r, m[2] );

						// Same with ID filtering
						if ( m[1] == "#" ) {
							var tmp = [];

							// Try to find the element with the ID
							for ( var i = 0; r[i]; i++ )
								if ( r[i].getAttribute("id") == m[2] ) {
									tmp = [ r[i] ];
									break;
								}

							r = tmp;
						}

						ret = r;
					}

					t = t.replace( re2, "" );
				}

			}

			// If a selector string still exists
			if ( t ) {
				// Attempt to filter it
				var val = jQuery.filter(t,r);
				ret = r = val.r;
				t = jQuery.trim(val.t);
			}
		}

		// An error occurred with the selector;
		// just return an empty set instead
		if ( t )
			ret = [];

		// Remove the root context
		if ( ret && context == ret[0] )
			ret.shift();

		// And combine the results
		done = jQuery.merge( done, ret );

		return done;
	},

	classFilter: function(r,m,not){
		m = " " + m + " ";
		var tmp = [];
		for ( var i = 0; r[i]; i++ ) {
			var pass = (" " + r[i].className + " ").indexOf( m ) >= 0;
			if ( !not && pass || not && !pass )
				tmp.push( r[i] );
		}
		return tmp;
	},

	filter: function(t,r,not) {
		var last;

		// Look for common filter expressions
		while ( t  && t != last ) {
			last = t;

			var p = jQuery.parse, m;

			for ( var i = 0; p[i]; i++ ) {
				m = p[i].exec( t );

				if ( m ) {
					// Remove what we just matched
					t = t.substring( m[0].length );

					m[2] = m[2].replace(/\\/g, "");
					break;
				}
			}

			if ( !m )
				break;

			// :not() is a special case that can be optimized by
			// keeping it out of the expression list
			if ( m[1] == ":" && m[2] == "not" )
				r = jQuery.filter(m[3], r, true).r;

			// We can get a big speed boost by filtering by class here
			else if ( m[1] == "." )
				r = jQuery.classFilter(r, m[2], not);

			else if ( m[1] == "[" ) {
				var tmp = [], type = m[3];
				
				for ( var i = 0, rl = r.length; i < rl; i++ ) {
					var a = r[i], z = a[ jQuery.props[m[2]] || m[2] ];
					
					if ( z == null || /href|src|selected/.test(m[2]) )
						z = jQuery.attr(a,m[2]) || '';

					if ( (type == "" && !!z ||
						 type == "=" && z == m[5] ||
						 type == "!=" && z != m[5] ||
						 type == "^=" && z && !z.indexOf(m[5]) ||
						 type == "$=" && z.substr(z.length - m[5].length) == m[5] ||
						 (type == "*=" || type == "~=") && z.indexOf(m[5]) >= 0) ^ not )
							tmp.push( a );
				}
				
				r = tmp;

			// We can get a speed boost by handling nth-child here
			} else if ( m[1] == ":" && m[2] == "nth-child" ) {
				var merge = {}, tmp = [],
					test = /(\d*)n\+?(\d*)/.exec(
						m[3] == "even" && "2n" || m[3] == "odd" && "2n+1" ||
						!/\D/.test(m[3]) && "n+" + m[3] || m[3]),
					first = (test[1] || 1) - 0, last = test[2] - 0;

				for ( var i = 0, rl = r.length; i < rl; i++ ) {
					var node = r[i], parentNode = node.parentNode, id = jQuery.data(parentNode);

					if ( !merge[id] ) {
						var c = 1;

						for ( var n = parentNode.firstChild; n; n = n.nextSibling )
							if ( n.nodeType == 1 )
								n.nodeIndex = c++;

						merge[id] = true;
					}

					var add = false;

					if ( first == 1 ) {
						if ( last == 0 || node.nodeIndex == last )
							add = true;
					} else if ( (node.nodeIndex + last) % first == 0 )
						add = true;

					if ( add ^ not )
						tmp.push( node );
				}

				r = tmp;

			// Otherwise, find the expression to execute
			} else {
				var f = jQuery.expr[m[1]];
				if ( typeof f != "string" )
					f = jQuery.expr[m[1]][m[2]];

				// Build a custom macro to enclose it
				f = eval("false||function(a,i){return " + f + "}");

				// Execute it against the current filter
				r = jQuery.grep( r, f, not );
			}
		}

		// Return an array of filtered elements (r)
		// and the modified expression string (t)
		return { r: r, t: t };
	},

	dir: function( elem, dir ){
		var matched = [];
		var cur = elem[dir];
		while ( cur && cur != document ) {
			if ( cur.nodeType == 1 )
				matched.push( cur );
			cur = cur[dir];
		}
		return matched;
	},
	
	nth: function(cur,result,dir,elem){
		result = result || 1;
		var num = 0;

		for ( ; cur; cur = cur[dir] )
			if ( cur.nodeType == 1 && ++num == result )
				break;

		return cur;
	},
	
	sibling: function( n, elem ) {
		var r = [];

		for ( ; n; n = n.nextSibling ) {
			if ( n.nodeType == 1 && (!elem || n != elem) )
				r.push( n );
		}

		return r;
	}
});
/*
 * A number of helper functions used for managing events.
 * Many of the ideas behind this code orignated from 
 * Dean Edwards' addEvent library.
 */
jQuery.event = {

	// Bind an event to an element
	// Original by Dean Edwards
	add: function(element, type, handler, data) {
		// For whatever reason, IE has trouble passing the window object
		// around, causing it to be cloned in the process
		if ( jQuery.browser.msie && element.setInterval != undefined )
			element = window;

		// Make sure that the function being executed has a unique ID
		if ( !handler.guid )
			handler.guid = this.guid++;
			
		// if data is passed, bind to handler 
		if( data != undefined ) { 
        		// Create temporary function pointer to original handler 
			var fn = handler; 

			// Create unique handler function, wrapped around original handler 
			handler = function() { 
				// Pass arguments and context to original handler 
				return fn.apply(this, arguments); 
			};

			// Store data in unique handler 
			handler.data = data;

			// Set the guid of unique handler to the same of original handler, so it can be removed 
			handler.guid = fn.guid;
		}

		// Namespaced event handlers
		var parts = type.split(".");
		type = parts[0];
		handler.type = parts[1];

		// Init the element's event structure
		var events = jQuery.data(element, "events") || jQuery.data(element, "events", {});
		
		var handle = jQuery.data(element, "handle", function(){
			// returned undefined or false
			var val;

			// Handle the second event of a trigger and when
			// an event is called after a page has unloaded
			if ( typeof jQuery == "undefined" || jQuery.event.triggered )
				return val;
			
			val = jQuery.event.handle.apply(element, arguments);
			
			return val;
		});

		// Get the current list of functions bound to this event
		var handlers = events[type];

		// Init the event handler queue
		if (!handlers) {
			handlers = events[type] = {};	
			
			// And bind the global event handler to the element
			if (element.addEventListener)
				element.addEventListener(type, handle, false);
			else
				element.attachEvent("on" + type, handle);
		}

		// Add the function to the element's handler list
		handlers[handler.guid] = handler;

		// Keep track of which events have been used, for global triggering
		this.global[type] = true;
	},

	guid: 1,
	global: {},

	// Detach an event or set of events from an element
	remove: function(element, type, handler) {
		var events = jQuery.data(element, "events"), ret, index;

		// Namespaced event handlers
		if ( typeof type == "string" ) {
			var parts = type.split(".");
			type = parts[0];
		}

		if ( events ) {
			// type is actually an event object here
			if ( type && type.type ) {
				handler = type.handler;
				type = type.type;
			}
			
			if ( !type ) {
				for ( type in events )
					this.remove( element, type );

			} else if ( events[type] ) {
				// remove the given handler for the given type
				if ( handler )
					delete events[type][handler.guid];
				
				// remove all handlers for the given type
				else
					for ( handler in events[type] )
						// Handle the removal of namespaced events
						if ( !parts[1] || events[type][handler].type == parts[1] )
							delete events[type][handler];

				// remove generic event handler if no more handlers exist
				for ( ret in events[type] ) break;
				if ( !ret ) {
					if (element.removeEventListener)
						element.removeEventListener(type, jQuery.data(element, "handle"), false);
					else
						element.detachEvent("on" + type, jQuery.data(element, "handle"));
					ret = null;
					delete events[type];
				}
			}

			// Remove the expando if it's no longer used
			for ( ret in events ) break;
			if ( !ret ) {
				jQuery.removeData( element, "events" );
				jQuery.removeData( element, "handle" );
			}
		}
	},

	trigger: function(type, data, element, donative, extra) {
		// Clone the incoming data, if any
		data = jQuery.makeArray(data || []);

		// Handle a global trigger
		if ( !element ) {
			// Only trigger if we've ever bound an event for it
			if ( this.global[type] )
				jQuery("*").add([window, document]).trigger(type, data);

		// Handle triggering a single element
		} else {
			var val, ret, fn = jQuery.isFunction( element[ type ] || null ),
				// Check to see if we need to provide a fake event, or not
				evt = !data[0] || !data[0].preventDefault;
			
			// Pass along a fake event
			if ( evt )
				data.unshift( this.fix({ type: type, target: element }) );

			// Enforce the right trigger type
			data[0].type = type;

			// Trigger the event
			if ( jQuery.isFunction( jQuery.data(element, "handle") ) )
				val = jQuery.data(element, "handle").apply( element, data );

			// Handle triggering native .onfoo handlers
			if ( !fn && element["on"+type] && element["on"+type].apply( element, data ) === false )
				val = false;

			// Extra functions don't get the custom event object
			if ( evt )
				data.shift();

			// Handle triggering of extra function
			if ( extra && extra.apply( element, data ) === false )
				val = false;

			// Trigger the native events (except for clicks on links)
			if ( fn && donative !== false && val !== false && !(jQuery.nodeName(element, 'a') && type == "click") ) {
				this.triggered = true;
				element[ type ]();
			}

			this.triggered = false;
		}

		return val;
	},

	handle: function(event) {
		// returned undefined or false
		var val;

		// Empty object is for triggered events with no data
		event = jQuery.event.fix( event || window.event || {} ); 

		// Namespaced event handlers
		var parts = event.type.split(".");
		event.type = parts[0];

		var c = jQuery.data(this, "events") && jQuery.data(this, "events")[event.type], args = Array.prototype.slice.call( arguments, 1 );
		args.unshift( event );

		for ( var j in c ) {
			// Pass in a reference to the handler function itself
			// So that we can later remove it
			args[0].handler = c[j];
			args[0].data = c[j].data;

			// Filter the functions by class
			if ( !parts[1] || c[j].type == parts[1] ) {
				var tmp = c[j].apply( this, args );

				if ( val !== false )
					val = tmp;

				if ( tmp === false ) {
					event.preventDefault();
					event.stopPropagation();
				}
			}
		}

		// Clean up added properties in IE to prevent memory leak
		if (jQuery.browser.msie)
			event.target = event.preventDefault = event.stopPropagation =
				event.handler = event.data = null;

		return val;
	},

	fix: function(event) {
		// store a copy of the original event object 
		// and clone to set read-only properties
		var originalEvent = event;
		event = jQuery.extend({}, originalEvent);
		
		// add preventDefault and stopPropagation since 
		// they will not work on the clone
		event.preventDefault = function() {
			// if preventDefault exists run it on the original event
			if (originalEvent.preventDefault)
				originalEvent.preventDefault();
			// otherwise set the returnValue property of the original event to false (IE)
			originalEvent.returnValue = false;
		};
		event.stopPropagation = function() {
			// if stopPropagation exists run it on the original event
			if (originalEvent.stopPropagation)
				originalEvent.stopPropagation();
			// otherwise set the cancelBubble property of the original event to true (IE)
			originalEvent.cancelBubble = true;
		};
		
		// Fix target property, if necessary
		if ( !event.target && event.srcElement )
			event.target = event.srcElement;
				
		// check if target is a textnode (safari)
		if (jQuery.browser.safari && event.target.nodeType == 3)
			event.target = originalEvent.target.parentNode;

		// Add relatedTarget, if necessary
		if ( !event.relatedTarget && event.fromElement )
			event.relatedTarget = event.fromElement == event.target ? event.toElement : event.fromElement;

		// Calculate pageX/Y if missing and clientX/Y available
		if ( event.pageX == null && event.clientX != null ) {
			var e = document.documentElement, b = document.body;
			event.pageX = event.clientX + (e && e.scrollLeft || b.scrollLeft || 0);
			event.pageY = event.clientY + (e && e.scrollTop || b.scrollTop || 0);
		}
			
		// Add which for key events
		if ( !event.which && (event.charCode || event.keyCode) )
			event.which = event.charCode || event.keyCode;
		
		// Add metaKey to non-Mac browsers (use ctrl for PC's and Meta for Macs)
		if ( !event.metaKey && event.ctrlKey )
			event.metaKey = event.ctrlKey;

		// Add which for click: 1 == left; 2 == middle; 3 == right
		// Note: button is not normalized, so don't use it
		if ( !event.which && event.button )
			event.which = (event.button & 1 ? 1 : ( event.button & 2 ? 3 : ( event.button & 4 ? 2 : 0 ) ));
			
		return event;
	}
};

jQuery.fn.extend({
	bind: function( type, data, fn ) {
		return type == "unload" ? this.one(type, data, fn) : this.each(function(){
			jQuery.event.add( this, type, fn || data, fn && data );
		});
	},
	
	one: function( type, data, fn ) {
		return this.each(function(){
			jQuery.event.add( this, type, function(event) {
				jQuery(this).unbind(event);
				return (fn || data).apply( this, arguments);
			}, fn && data);
		});
	},

	unbind: function( type, fn ) {
		return this.each(function(){
			jQuery.event.remove( this, type, fn );
		});
	},

	trigger: function( type, data, fn ) {
		return this.each(function(){
			jQuery.event.trigger( type, data, this, true, fn );
		});
	},

	triggerHandler: function( type, data, fn ) {
		if ( this[0] )
			return jQuery.event.trigger( type, data, this[0], false, fn );
	},

	toggle: function() {
		// Save reference to arguments for access in closure
		var a = arguments;

		return this.click(function(e) {
			// Figure out which function to execute
			this.lastToggle = 0 == this.lastToggle ? 1 : 0;
			
			// Make sure that clicks stop
			e.preventDefault();
			
			// and execute the function
			return a[this.lastToggle].apply( this, [e] ) || false;
		});
	},

	hover: function(f,g) {
		
		// A private function for handling mouse 'hovering'
		function handleHover(e) {
			// Check if mouse(over|out) are still within the same parent element
			var p = e.relatedTarget;
	
			// Traverse up the tree
			while ( p && p != this ) try { p = p.parentNode; } catch(e) { p = this; };
			
			// If we actually just moused on to a sub-element, ignore it
			if ( p == this ) return false;
			
			// Execute the right function
			return (e.type == "mouseover" ? f : g).apply(this, [e]);
		}
		
		// Bind the function to the two event listeners
		return this.mouseover(handleHover).mouseout(handleHover);
	},
	
	ready: function(f) {
		// Attach the listeners
		bindReady();

		// If the DOM is already ready
		if ( jQuery.isReady )
			// Execute the function immediately
			f.apply( document, [jQuery] );
			
		// Otherwise, remember the function for later
		else
			// Add the function to the wait list
			jQuery.readyList.push( function() { return f.apply(this, [jQuery]); } );
	
		return this;
	}
});

jQuery.extend({
	/*
	 * All the code that makes DOM Ready work nicely.
	 */
	isReady: false,
	readyList: [],
	
	// Handle when the DOM is ready
	ready: function() {
		// Make sure that the DOM is not already loaded
		if ( !jQuery.isReady ) {
			// Remember that the DOM is ready
			jQuery.isReady = true;
			
			// If there are functions bound, to execute
			if ( jQuery.readyList ) {
				// Execute all of them
				jQuery.each( jQuery.readyList, function(){
					this.apply( document );
				});
				
				// Reset the list of functions
				jQuery.readyList = null;
			}
			// Remove event listener to avoid memory leak
			if ( jQuery.browser.mozilla || jQuery.browser.opera )
				document.removeEventListener( "DOMContentLoaded", jQuery.ready, false );
			
			// Remove script element used by IE hack
			if( !window.frames.length ) // don't remove if frames are present (#1187)
				jQuery(window).load(function(){ jQuery("#__ie_init").remove(); });
		}
	}
});

jQuery.each( ("blur,focus,load,resize,scroll,unload,click,dblclick," +
	"mousedown,mouseup,mousemove,mouseover,mouseout,change,select," + 
	"submit,keydown,keypress,keyup,error").split(","), function(i,o){
	
	// Handle event binding
	jQuery.fn[o] = function(f){
		return f ? this.bind(o, f) : this.trigger(o);
	};
});

var readyBound = false;

function bindReady(){
	if ( readyBound ) return;
	readyBound = true;

	// If Mozilla is used
	if ( jQuery.browser.mozilla || jQuery.browser.opera )
		// Use the handy event callback
		document.addEventListener( "DOMContentLoaded", jQuery.ready, false );
	
	// If IE is used, use the excellent hack by Matthias Miller
	// http://www.outofhanwell.com/blog/index.php?title=the_window_onload_problem_revisited
	else if ( jQuery.browser.msie ) {
	
		// Only works if you document.write() it
		document.write("<scr" + "ipt id=__ie_init defer=true " + 
			"src=//:><\/script>");
	
		// Use the defer script hack
		var script = document.getElementById("__ie_init");
		
		// script does not exist if jQuery is loaded dynamically
		if ( script ) 
			script.onreadystatechange = function() {
				if ( this.readyState != "complete" ) return;
				jQuery.ready();
			};
	
		// Clear from memory
		script = null;
	
	// If Safari  is used
	} else if ( jQuery.browser.safari )
		// Continually check to see if the document.readyState is valid
		jQuery.safariTimer = setInterval(function(){
			// loaded and complete are both valid states
			if ( document.readyState == "loaded" || 
				document.readyState == "complete" ) {
	
				// If either one are found, remove the timer
				clearInterval( jQuery.safariTimer );
				jQuery.safariTimer = null;
	
				// and execute any waiting functions
				jQuery.ready();
			}
		}, 10); 

	// A fallback to window.onload, that will always work
	jQuery.event.add( window, "load", jQuery.ready );
}
jQuery.fn.extend({
	load: function( url, params, callback ) {
		if ( jQuery.isFunction( url ) )
			return this.bind("load", url);

		var off = url.indexOf(" ");
		if ( off >= 0 ) {
			var selector = url.slice(off, url.length);
			url = url.slice(0, off);
		}

		callback = callback || function(){};

		// Default to a GET request
		var type = "GET";

		// If the second parameter was provided
		if ( params )
			// If it's a function
			if ( jQuery.isFunction( params ) ) {
				// We assume that it's the callback
				callback = params;
				params = null;

			// Otherwise, build a param string
			} else {
				params = jQuery.param( params );
				type = "POST";
			}

		var self = this;

		// Request the remote document
		jQuery.ajax({
			url: url,
			type: type,
			data: params,
			complete: function(res, status){
				// If successful, inject the HTML into all the matched elements
				if ( status == "success" || status == "notmodified" )
					// See if a selector was specified
					self.html( selector ?
						// Create a dummy div to hold the results
						jQuery("<div/>")
							// inject the contents of the document in, removing the scripts
							// to avoid any 'Permission Denied' errors in IE
							.append(res.responseText.replace(/<script(.|\s)*?\/script>/g, ""))

							// Locate the specified elements
							.find(selector) :

						// If not, just inject the full result
						res.responseText );

				// Add delay to account for Safari's delay in globalEval
				setTimeout(function(){
					self.each( callback, [res.responseText, status, res] );
				}, 13);
			}
		});
		return this;
	},

	serialize: function() {
		return jQuery.param(this.serializeArray());
	},
	serializeArray: function() {
		return this.map(function(){
			return jQuery.nodeName(this, "form") ?
				jQuery.makeArray(this.elements) : this;
		})
		.filter(function(){
			return this.name && !this.disabled && 
				(this.checked || /select|textarea/i.test(this.nodeName) || 
					/text|hidden|password/i.test(this.type));
		})
		.map(function(i, elem){
			var val = jQuery(this).val();
			return val == null ? null :
				val.constructor == Array ?
					jQuery.map( val, function(val, i){
						return {name: elem.name, value: val};
					}) :
					{name: elem.name, value: val};
		}).get();
	}
});

// Attach a bunch of functions for handling common AJAX events
jQuery.each( "ajaxStart,ajaxStop,ajaxComplete,ajaxError,ajaxSuccess,ajaxSend".split(","), function(i,o){
	jQuery.fn[o] = function(f){
		return this.bind(o, f);
	};
});

var jsc = (new Date).getTime();

jQuery.extend({
	get: function( url, data, callback, type ) {
		// shift arguments if data argument was ommited
		if ( jQuery.isFunction( data ) ) {
			callback = data;
			data = null;
		}
		
		return jQuery.ajax({
			type: "GET",
			url: url,
			data: data,
			success: callback,
			dataType: type
		});
	},

	getScript: function( url, callback ) {
		return jQuery.get(url, null, callback, "script");
	},

	getJSON: function( url, data, callback ) {
		return jQuery.get(url, data, callback, "json");
	},

	post: function( url, data, callback, type ) {
		if ( jQuery.isFunction( data ) ) {
			callback = data;
			data = {};
		}

		return jQuery.ajax({
			type: "POST",
			url: url,
			data: data,
			success: callback,
			dataType: type
		});
	},

	ajaxSetup: function( settings ) {
		jQuery.extend( jQuery.ajaxSettings, settings );
	},

	ajaxSettings: {
		global: true,
		type: "GET",
		timeout: 0,
		contentType: "application/x-www-form-urlencoded",
		processData: true,
		async: true,
		data: null
	},
	
	// Last-Modified header cache for next request
	lastModified: {},

	ajax: function( s ) {
		var jsonp, jsre = /=(\?|%3F)/g, status, data;

		// Extend the settings, but re-extend 's' so that it can be
		// checked again later (in the test suite, specifically)
		s = jQuery.extend(true, s, jQuery.extend(true, {}, jQuery.ajaxSettings, s));

		// convert data if not already a string
		if ( s.data && s.processData && typeof s.data != "string" )
			s.data = jQuery.param(s.data);

		// Handle JSONP Parameter Callbacks
		if ( s.dataType == "jsonp" ) {
			if ( s.type.toLowerCase() == "get" ) {
				if ( !s.url.match(jsre) )
					s.url += (s.url.match(/\?/) ? "&" : "?") + (s.jsonp || "callback") + "=?";
			} else if ( !s.data || !s.data.match(jsre) )
				s.data = (s.data ? s.data + "&" : "") + (s.jsonp || "callback") + "=?";
			s.dataType = "json";
		}

		// Build temporary JSONP function
		if ( s.dataType == "json" && (s.data && s.data.match(jsre) || s.url.match(jsre)) ) {
			jsonp = "jsonp" + jsc++;

			// Replace the =? sequence both in the query string and the data
			if ( s.data )
				s.data = s.data.replace(jsre, "=" + jsonp);
			s.url = s.url.replace(jsre, "=" + jsonp);

			// We need to make sure
			// that a JSONP style response is executed properly
			s.dataType = "script";

			// Handle JSONP-style loading
			window[ jsonp ] = function(tmp){
				data = tmp;
				success();
				complete();
				// Garbage collect
				window[ jsonp ] = undefined;
				try{ delete window[ jsonp ]; } catch(e){}
			};
		}

		if ( s.dataType == "script" && s.cache == null )
			s.cache = false;

		if ( s.cache === false && s.type.toLowerCase() == "get" )
			s.url += (s.url.match(/\?/) ? "&" : "?") + "_=" + (new Date()).getTime();

		// If data is available, append data to url for get requests
		if ( s.data && s.type.toLowerCase() == "get" ) {
			s.url += (s.url.match(/\?/) ? "&" : "?") + s.data;

			// IE likes to send both get and post data, prevent this
			s.data = null;
		}

		// Watch for a new set of requests
		if ( s.global && ! jQuery.active++ )
			jQuery.event.trigger( "ajaxStart" );

		// If we're requesting a remote document
		// and trying to load JSON or Script
		if ( !s.url.indexOf("http") && s.dataType == "script" ) {
			var head = document.getElementsByTagName("head")[0];
			var script = document.createElement("script");
			script.src = s.url;

			// Handle Script loading
			if ( !jsonp && (s.success || s.complete) ) {
				var done = false;

				// Attach handlers for all browsers
				script.onload = script.onreadystatechange = function(){
					if ( !done && (!this.readyState || 
							this.readyState == "loaded" || this.readyState == "complete") ) {
						done = true;
						success();
						complete();
						head.removeChild( script );
					}
				};
			}

			head.appendChild(script);

			// We handle everything using the script element injection
			return;
		}

		var requestDone = false;

		// Create the request object; Microsoft failed to properly
		// implement the XMLHttpRequest in IE7, so we use the ActiveXObject when it is available
		var xml = window.ActiveXObject ? new ActiveXObject("Microsoft.XMLHTTP") : new XMLHttpRequest();

		// Open the socket
		xml.open(s.type, s.url, s.async);

		// Set the correct header, if data is being sent
		if ( s.data )
			xml.setRequestHeader("Content-Type", s.contentType);

		// Set the If-Modified-Since header, if ifModified mode.
		if ( s.ifModified )
			xml.setRequestHeader("If-Modified-Since",
				jQuery.lastModified[s.url] || "Thu, 01 Jan 1970 00:00:00 GMT" );

		// Set header so the called script knows that it's an XMLHttpRequest
		xml.setRequestHeader("X-Requested-With", "XMLHttpRequest");

		// Allow custom headers/mimetypes
		if ( s.beforeSend )
			s.beforeSend(xml);
			
		if ( s.global )
		    jQuery.event.trigger("ajaxSend", [xml, s]);

		// Wait for a response to come back
		var onreadystatechange = function(isTimeout){
			// The transfer is complete and the data is available, or the request timed out
			if ( !requestDone && xml && (xml.readyState == 4 || isTimeout == "timeout") ) {
				requestDone = true;
				
				// clear poll interval
				if (ival) {
					clearInterval(ival);
					ival = null;
				}
				
				status = isTimeout == "timeout" && "timeout" ||
					!jQuery.httpSuccess( xml ) && "error" ||
					s.ifModified && jQuery.httpNotModified( xml, s.url ) && "notmodified" ||
					"success";

				if ( status == "success" ) {
					// Watch for, and catch, XML document parse errors
					try {
						// process the data (runs the xml through httpData regardless of callback)
						data = jQuery.httpData( xml, s.dataType );
					} catch(e) {
						status = "parsererror";
					}
				}

				// Make sure that the request was successful or notmodified
				if ( status == "success" ) {
					// Cache Last-Modified header, if ifModified mode.
					var modRes;
					try {
						modRes = xml.getResponseHeader("Last-Modified");
					} catch(e) {} // swallow exception thrown by FF if header is not available
	
					if ( s.ifModified && modRes )
						jQuery.lastModified[s.url] = modRes;

					// JSONP handles its own success callback
					if ( !jsonp )
						success();	
				} else
					jQuery.handleError(s, xml, status);

				// Fire the complete handlers
				complete();

				// Stop memory leaks
				if ( s.async )
					xml = null;
			}
		};
		
		if ( s.async ) {
			// don't attach the handler to the request, just poll it instead
			var ival = setInterval(onreadystatechange, 13); 

			// Timeout checker
			if ( s.timeout > 0 )
				setTimeout(function(){
					// Check to see if the request is still happening
					if ( xml ) {
						// Cancel the request
						xml.abort();
	
						if( !requestDone )
							onreadystatechange( "timeout" );
					}
				}, s.timeout);
		}
			
		// Send the data
		try {
			xml.send(s.data);
		} catch(e) {
			jQuery.handleError(s, xml, null, e);
		}
		
		// firefox 1.5 doesn't fire statechange for sync requests
		if ( !s.async )
			onreadystatechange();
		
		// return XMLHttpRequest to allow aborting the request etc.
		return xml;

		function success(){
			// If a local callback was specified, fire it and pass it the data
			if ( s.success )
				s.success( data, status );

			// Fire the global callback
			if ( s.global )
				jQuery.event.trigger( "ajaxSuccess", [xml, s] );
		}

		function complete(){
			// Process result
			if ( s.complete )
				s.complete(xml, status);

			// The request was completed
			if ( s.global )
				jQuery.event.trigger( "ajaxComplete", [xml, s] );

			// Handle the global AJAX counter
			if ( s.global && ! --jQuery.active )
				jQuery.event.trigger( "ajaxStop" );
		}
	},

	handleError: function( s, xml, status, e ) {
		// If a local callback was specified, fire it
		if ( s.error ) s.error( xml, status, e );

		// Fire the global callback
		if ( s.global )
			jQuery.event.trigger( "ajaxError", [xml, s, e] );
	},

	// Counter for holding the number of active queries
	active: 0,

	// Determines if an XMLHttpRequest was successful or not
	httpSuccess: function( r ) {
		try {
			return !r.status && location.protocol == "file:" ||
				( r.status >= 200 && r.status < 300 ) || r.status == 304 ||
				jQuery.browser.safari && r.status == undefined;
		} catch(e){}
		return false;
	},

	// Determines if an XMLHttpRequest returns NotModified
	httpNotModified: function( xml, url ) {
		try {
			var xmlRes = xml.getResponseHeader("Last-Modified");

			// Firefox always returns 200. check Last-Modified date
			return xml.status == 304 || xmlRes == jQuery.lastModified[url] ||
				jQuery.browser.safari && xml.status == undefined;
		} catch(e){}
		return false;
	},

	httpData: function( r, type ) {
		var ct = r.getResponseHeader("content-type");
		var xml = type == "xml" || !type && ct && ct.indexOf("xml") >= 0;
		var data = xml ? r.responseXML : r.responseText;

		if ( xml && data.documentElement.tagName == "parsererror" )
			throw "parsererror";

		// If the type is "script", eval it in global context
		if ( type == "script" )
			jQuery.globalEval( data );

		// Get the JavaScript object, if JSON is used.
		if ( type == "json" )
			data = eval("(" + data + ")");

		return data;
	},

	// Serialize an array of form elements or a set of
	// key/values into a query string
	param: function( a ) {
		var s = [];

		// If an array was passed in, assume that it is an array
		// of form elements
		if ( a.constructor == Array || a.jquery )
			// Serialize the form elements
			jQuery.each( a, function(){
				s.push( encodeURIComponent(this.name) + "=" + encodeURIComponent( this.value ) );
			});

		// Otherwise, assume that it's an object of key/value pairs
		else
			// Serialize the key/values
			for ( var j in a )
				// If the value is an array then the key names need to be repeated
				if ( a[j] && a[j].constructor == Array )
					jQuery.each( a[j], function(){
						s.push( encodeURIComponent(j) + "=" + encodeURIComponent( this ) );
					});
				else
					s.push( encodeURIComponent(j) + "=" + encodeURIComponent( a[j] ) );

		// Return the resulting serialization
		return s.join("&").replace(/%20/g, "+");
	}

});
jQuery.fn.extend({
	show: function(speed,callback){
		return speed ?
			this.animate({
				height: "show", width: "show", opacity: "show"
			}, speed, callback) :
			
			this.filter(":hidden").each(function(){
				this.style.display = this.oldblock ? this.oldblock : "";
				if ( jQuery.css(this,"display") == "none" )
					this.style.display = "block";
			}).end();
	},
	
	hide: function(speed,callback){
		return speed ?
			this.animate({
				height: "hide", width: "hide", opacity: "hide"
			}, speed, callback) :
			
			this.filter(":visible").each(function(){
				this.oldblock = this.oldblock || jQuery.css(this,"display");
				if ( this.oldblock == "none" )
					this.oldblock = "block";
				this.style.display = "none";
			}).end();
	},

	// Save the old toggle function
	_toggle: jQuery.fn.toggle,
	
	toggle: function( fn, fn2 ){
		return jQuery.isFunction(fn) && jQuery.isFunction(fn2) ?
			this._toggle( fn, fn2 ) :
			fn ?
				this.animate({
					height: "toggle", width: "toggle", opacity: "toggle"
				}, fn, fn2) :
				this.each(function(){
					jQuery(this)[ jQuery(this).is(":hidden") ? "show" : "hide" ]();
				});
	},
	
	slideDown: function(speed,callback){
		return this.animate({height: "show"}, speed, callback);
	},
	
	slideUp: function(speed,callback){
		return this.animate({height: "hide"}, speed, callback);
	},

	slideToggle: function(speed, callback){
		return this.animate({height: "toggle"}, speed, callback);
	},
	
	fadeIn: function(speed, callback){
		return this.animate({opacity: "show"}, speed, callback);
	},
	
	fadeOut: function(speed, callback){
		return this.animate({opacity: "hide"}, speed, callback);
	},
	
	fadeTo: function(speed,to,callback){
		return this.animate({opacity: to}, speed, callback);
	},
	
	animate: function( prop, speed, easing, callback ) {
		var opt = jQuery.speed(speed, easing, callback);

		return this[ opt.queue === false ? "each" : "queue" ](function(){
			opt = jQuery.extend({}, opt);
			var hidden = jQuery(this).is(":hidden"), self = this;
			
			for ( var p in prop ) {
				if ( prop[p] == "hide" && hidden || prop[p] == "show" && !hidden )
					return jQuery.isFunction(opt.complete) && opt.complete.apply(this);

				if ( p == "height" || p == "width" ) {
					// Store display property
					opt.display = jQuery.css(this, "display");

					// Make sure that nothing sneaks out
					opt.overflow = this.style.overflow;
				}
			}

			if ( opt.overflow != null )
				this.style.overflow = "hidden";

			opt.curAnim = jQuery.extend({}, prop);
			
			jQuery.each( prop, function(name, val){
				var e = new jQuery.fx( self, opt, name );

				if ( /toggle|show|hide/.test(val) )
					e[ val == "toggle" ? hidden ? "show" : "hide" : val ]( prop );
				else {
					var parts = val.toString().match(/^([+-]=)?([\d+-.]+)(.*)$/),
						start = e.cur(true) || 0;

					if ( parts ) {
						var end = parseFloat(parts[2]),
							unit = parts[3] || "px";

						// We need to compute starting value
						if ( unit != "px" ) {
							self.style[ name ] = (end || 1) + unit;
							start = ((end || 1) / e.cur(true)) * start;
							self.style[ name ] = start + unit;
						}

						// If a +=/-= token was provided, we're doing a relative animation
						if ( parts[1] )
							end = ((parts[1] == "-=" ? -1 : 1) * end) + start;

						e.custom( start, end, unit );
					} else
						e.custom( start, val, "" );
				}
			});

			// For JS strict compliance
			return true;
		});
	},
	
	queue: function(type, fn){
		if ( jQuery.isFunction(type) ) {
			fn = type;
			type = "fx";
		}

		if ( !type || (typeof type == "string" && !fn) )
			return queue( this[0], type );

		return this.each(function(){
			if ( fn.constructor == Array )
				queue(this, type, fn);
			else {
				queue(this, type).push( fn );
			
				if ( queue(this, type).length == 1 )
					fn.apply(this);
			}
		});
	},

	stop: function(){
		var timers = jQuery.timers;

		return this.each(function(){
			for ( var i = 0; i < timers.length; i++ )
				if ( timers[i].elem == this )
					timers.splice(i--, 1);
		}).dequeue();
	}

});

var queue = function( elem, type, array ) {
	if ( !elem )
		return;

	var q = jQuery.data( elem, type + "queue" );

	if ( !q || array )
		q = jQuery.data( elem, type + "queue", 
			array ? jQuery.makeArray(array) : [] );

	return q;
};

jQuery.fn.dequeue = function(type){
	type = type || "fx";

	return this.each(function(){
		var q = queue(this, type);

		q.shift();

		if ( q.length )
			q[0].apply( this );
	});
};

jQuery.extend({
	
	speed: function(speed, easing, fn) {
		var opt = speed && speed.constructor == Object ? speed : {
			complete: fn || !fn && easing || 
				jQuery.isFunction( speed ) && speed,
			duration: speed,
			easing: fn && easing || easing && easing.constructor != Function && easing
		};

		opt.duration = (opt.duration && opt.duration.constructor == Number ? 
			opt.duration : 
			{ slow: 600, fast: 200 }[opt.duration]) || 400;
	
		// Queueing
		opt.old = opt.complete;
		opt.complete = function(){
			jQuery(this).dequeue();
			if ( jQuery.isFunction( opt.old ) )
				opt.old.apply( this );
		};
	
		return opt;
	},
	
	easing: {
		linear: function( p, n, firstNum, diff ) {
			return firstNum + diff * p;
		},
		swing: function( p, n, firstNum, diff ) {
			return ((-Math.cos(p*Math.PI)/2) + 0.5) * diff + firstNum;
		}
	},
	
	timers: [],

	fx: function( elem, options, prop ){
		this.options = options;
		this.elem = elem;
		this.prop = prop;

		if ( !options.orig )
			options.orig = {};
	}

});

jQuery.fx.prototype = {

	// Simple function for setting a style value
	update: function(){
		if ( this.options.step )
			this.options.step.apply( this.elem, [ this.now, this ] );

		(jQuery.fx.step[this.prop] || jQuery.fx.step._default)( this );

		// Set display property to block for height/width animations
		if ( this.prop == "height" || this.prop == "width" )
			this.elem.style.display = "block";
	},

	// Get the current size
	cur: function(force){
		if ( this.elem[this.prop] != null && this.elem.style[this.prop] == null )
			return this.elem[ this.prop ];

		var r = parseFloat(jQuery.curCSS(this.elem, this.prop, force));
		return r && r > -10000 ? r : parseFloat(jQuery.css(this.elem, this.prop)) || 0;
	},

	// Start an animation from one number to another
	custom: function(from, to, unit){
		this.startTime = (new Date()).getTime();
		this.start = from;
		this.end = to;
		this.unit = unit || this.unit || "px";
		this.now = this.start;
		this.pos = this.state = 0;
		this.update();

		var self = this;
		function t(){
			return self.step();
		}

		t.elem = this.elem;

		jQuery.timers.push(t);

		if ( jQuery.timers.length == 1 ) {
			var timer = setInterval(function(){
				var timers = jQuery.timers;
				
				for ( var i = 0; i < timers.length; i++ )
					if ( !timers[i]() )
						timers.splice(i--, 1);

				if ( !timers.length )
					clearInterval( timer );
			}, 13);
		}
	},

	// Simple 'show' function
	show: function(){
		// Remember where we started, so that we can go back to it later
		this.options.orig[this.prop] = jQuery.attr( this.elem.style, this.prop );
		this.options.show = true;

		// Begin the animation
		this.custom(0, this.cur());

		// Make sure that we start at a small width/height to avoid any
		// flash of content
		if ( this.prop == "width" || this.prop == "height" )
			this.elem.style[this.prop] = "1px";
		
		// Start by showing the element
		jQuery(this.elem).show();
	},

	// Simple 'hide' function
	hide: function(){
		// Remember where we started, so that we can go back to it later
		this.options.orig[this.prop] = jQuery.attr( this.elem.style, this.prop );
		this.options.hide = true;

		// Begin the animation
		this.custom(this.cur(), 0);
	},

	// Each step of an animation
	step: function(){
		var t = (new Date()).getTime();

		if ( t > this.options.duration + this.startTime ) {
			this.now = this.end;
			this.pos = this.state = 1;
			this.update();

			this.options.curAnim[ this.prop ] = true;

			var done = true;
			for ( var i in this.options.curAnim )
				if ( this.options.curAnim[i] !== true )
					done = false;

			if ( done ) {
				if ( this.options.display != null ) {
					// Reset the overflow
					this.elem.style.overflow = this.options.overflow;
				
					// Reset the display
					this.elem.style.display = this.options.display;
					if ( jQuery.css(this.elem, "display") == "none" )
						this.elem.style.display = "block";
				}

				// Hide the element if the "hide" operation was done
				if ( this.options.hide )
					this.elem.style.display = "none";

				// Reset the properties, if the item has been hidden or shown
				if ( this.options.hide || this.options.show )
					for ( var p in this.options.curAnim )
						jQuery.attr(this.elem.style, p, this.options.orig[p]);
			}

			// If a callback was provided, execute it
			if ( done && jQuery.isFunction( this.options.complete ) )
				// Execute the complete function
				this.options.complete.apply( this.elem );

			return false;
		} else {
			var n = t - this.startTime;
			this.state = n / this.options.duration;

			// Perform the easing function, defaults to swing
			this.pos = jQuery.easing[this.options.easing || (jQuery.easing.swing ? "swing" : "linear")](this.state, n, 0, 1, this.options.duration);
			this.now = this.start + ((this.end - this.start) * this.pos);

			// Perform the next step of the animation
			this.update();
		}

		return true;
	}

};

jQuery.fx.step = {
	scrollLeft: function(fx){
		fx.elem.scrollLeft = fx.now;
	},

	scrollTop: function(fx){
		fx.elem.scrollTop = fx.now;
	},

	opacity: function(fx){
		jQuery.attr(fx.elem.style, "opacity", fx.now);
	},

	_default: function(fx){
		fx.elem.style[ fx.prop ] = fx.now + fx.unit;
	}
};
// The Offset Method
// Originally By Brandon Aaron, part of the Dimension Plugin
// http://jquery.com/plugins/project/dimensions
jQuery.fn.offset = function() {
	var left = 0, top = 0, elem = this[0], results;
	
	if ( elem ) with ( jQuery.browser ) {
		var	absolute     = jQuery.css(elem, "position") == "absolute", 
		    parent       = elem.parentNode, 
		    offsetParent = elem.offsetParent, 
		    doc          = elem.ownerDocument,
		    safari2      = safari && parseInt(version) < 522;
	
		// Use getBoundingClientRect if available
		if ( elem.getBoundingClientRect ) {
			box = elem.getBoundingClientRect();
		
			// Add the document scroll offsets
			add(
				box.left + Math.max(doc.documentElement.scrollLeft, doc.body.scrollLeft),
				box.top  + Math.max(doc.documentElement.scrollTop,  doc.body.scrollTop)
			);
		
			// IE adds the HTML element's border, by default it is medium which is 2px
			// IE 6 and IE 7 quirks mode the border width is overwritable by the following css html { border: 0; }
			// IE 7 standards mode, the border is always 2px
			if ( msie ) {
				var border = jQuery("html").css("borderWidth");
				border = (border == "medium" || jQuery.boxModel && parseInt(version) >= 7) && 2 || border;
				add( -border, -border );
			}
	
		// Otherwise loop through the offsetParents and parentNodes
		} else {
		
			// Initial element offsets
			add( elem.offsetLeft, elem.offsetTop );
		
			// Get parent offsets
			while ( offsetParent ) {
				// Add offsetParent offsets
				add( offsetParent.offsetLeft, offsetParent.offsetTop );
			
				// Mozilla and Safari > 2 does not include the border on offset parents
				// However Mozilla adds the border for table cells
				if ( mozilla && /^t[d|h]$/i.test(parent.tagName) || !safari2 )
					border( offsetParent );
				
				// Safari <= 2 doubles body offsets with an absolutely positioned element or parent
				if ( safari2 && !absolute && jQuery.css(offsetParent, "position") == "absolute" )
					absolute = true;
			
				// Get next offsetParent
				offsetParent = offsetParent.offsetParent;
			}
		
			// Get parent scroll offsets
			while ( parent.tagName && !/^body|html$/i.test(parent.tagName) ) {
				// Work around opera inline/table scrollLeft/Top bug
				if ( !/^inline|table-row.*$/i.test(jQuery.css(parent, "display")) )
					// Subtract parent scroll offsets
					add( -parent.scrollLeft, -parent.scrollTop );
			
				// Mozilla does not add the border for a parent that has overflow != visible
				if ( mozilla && jQuery.css(parent, "overflow") != "visible" )
					border( parent );
			
				// Get next parent
				parent = parent.parentNode;
			}
		
			// Safari doubles body offsets with an absolutely positioned element or parent
			if ( safari2 && absolute )
				add( -doc.body.offsetLeft, -doc.body.offsetTop );
		}

		// Return an object with top and left properties
		results = { top: top, left: left };
	}

	return results;

	function border(elem) {
		add( jQuery.css(elem, "borderLeftWidth"), jQuery.css(elem, "borderTopWidth") );
	}

	function add(l, t) {
		left += parseInt(l) || 0;
		top += parseInt(t) || 0;
	}
};
})();

;

jQuery.noConflict();

;

/*------------------------------------------------------------------------------
Jemplate - Template Toolkit for JavaScript

DESCRIPTION - This module provides the runtime JavaScript support for
compiled Jemplate templates.

AUTHOR - Ingy döt Net <ingy@cpan.org>

Copyright 2006 Ingy döt Net. All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
------------------------------------------------------------------------------*/

//------------------------------------------------------------------------------
// Main Jemplate class
//------------------------------------------------------------------------------

if (typeof Jemplate == 'undefined') {
    Jemplate = function() {
        this.init.apply(this, arguments);
    };
}

if (! Jemplate.templateMap)
    Jemplate.templateMap = {};

Jemplate.process = function() {
    var jemplate = new Jemplate();
    return jemplate.process.apply(jemplate, arguments);
}

proto = Jemplate.prototype;

proto.init = function(config) {
    this.config = config ||
    {
        AUTO_RESET: true,
        BLOCKS: {},
        CONTEXT: null,
        DEBUG_UNDEF: false,
        DEFAULT: null,
        ERROR: null,
        EVAL_JAVASCRIPT: false,
        FILTERS: {},
        INCLUDE_PATH: [''],
        INTERPOLATE: false,
        OUTPUT: null,
        PLUGINS: {},
        POST_PROCESS: [],
        PRE_PROCESS: [],
        PROCESS: null,
        RECURSION: false,
        STASH: null,
        TOLERANT: null,
        VARIABLES: {},
        WRAPPER: []
    };
}

proto.process = function(template, data, output) {
    var context = this.config.CONTEXT || new Jemplate.Context();
    context.config = this.config;

    context.stash = this.config.STASH || new Jemplate.Stash();
    context.stash.__config__ = this.config;

    context.__filter__ = new Jemplate.Filter();
    context.__filter__.config = this.config;

    var result;

    var proc = function(input) {
        try {
            result = context.process(template, input);
        }
        catch(e) {
            if (! String(e).match(/Jemplate\.STOP\n/))
                throw(e);
            result = e.toString().replace(/Jemplate\.STOP\n/, '');
        }

        if (typeof output == 'undefined')
            return result;
        if (typeof output == 'function') {
            output(result);
            return;
        }
        if (typeof(output) == 'string' || output instanceof String) {
            if (output.match(/^#[\w\-]+$/)) {
                var id = output.replace(/^#/, '');
                var element = document.getElementById(id);
                if (typeof element == 'undefined')
                    throw('No element found with id="' + id + '"');
                element.innerHTML = result;
                return;
            }
        }
        else {
            output.innerHTML = result;
            return;
        }

        throw("Invalid arguments in call to Jemplate.process");

        return 1;
    }

    if (typeof data == 'function')
        data = data();
    else if (typeof data == 'string') {
        Ajax.get(data, function(r) { proc(JSON.parse(r)) });
        return;
    }

    return proc(data);
}

//------------------------------------------------------------------------------
// Jemplate.Context class
//------------------------------------------------------------------------------
if (typeof Jemplate.Context == 'undefined')
    Jemplate.Context = function() {};

proto = Jemplate.Context.prototype;

proto.include = function(template, args) {
    return this.process(template, args, true);
}

proto.process = function(template, args, localise) {
    if (localise)
        this.stash.clone(args);
    else
        this.stash.update(args);
    var func = Jemplate.templateMap[template];
    if (typeof func == 'undefined')
        throw('No Jemplate template named "' + template + '" available');
    var output = func(this);
    if (localise)
        this.stash.declone();
    return output;
}

proto.set_error = function(error, output) {
    this._error = [error, output];
    return error;
}

proto.filter = function(text, name, args) {
    if (name == 'null')
        name = "null_filter";
    if (typeof this.__filter__.filters[name] == "function")
        return this.__filter__.filters[name](text, args, this);
    else
        throw "Unknown filter name ':" + name + "'";
}

//------------------------------------------------------------------------------
// Jemplate.Filter class
//------------------------------------------------------------------------------
if (typeof Jemplate.Filter == 'undefined') {
    Jemplate.Filter = function() { };
}

proto = Jemplate.Filter.prototype;

proto.filters = {};

proto.filters.null_filter = function(text) {
    return '';
}

proto.filters.upper = function(text) {
    return text.toUpperCase();
}

proto.filters.lower = function(text) {
    return text.toLowerCase();
}

proto.filters.ucfirst = function(text) {
    var first = text.charAt(0);
    var rest = text.substr(1);
    return first.toUpperCase() + rest;
}

proto.filters.lcfirst = function(text) {
    var first = text.charAt(0);
    var rest = text.substr(1);
    return first.toLowerCase() + rest;
}

proto.filters.trim = function(text) {
    return text.replace( /^\s+/g, "" ).replace( /\s+$/g, "" );
}

proto.filters.collapse = function(text) {
    return text.replace( /^\s+/g, "" ).replace( /\s+$/g, "" ).replace(/\s+/, " ");
}

proto.filters.html = function(text) {
    text = text.replace(/&/g, '&amp;');
    text = text.replace(/</g, '&lt;');
    text = text.replace(/>/g, '&gt;');
    text = text.replace(/"/g, '&quot;'); // " end quote for emacs
    return text;
}

proto.filters.html_para = function(text) {
    var lines = text.split(/(?:\r?\n){2,}/);
    return "<p>\n" + lines.join("\n</p>\n\n<p>\n") + "</p>\n";
}

proto.filters.html_break = function(text) {
    return text.replace(/(\r?\n){2,}/g, "$1<br />$1<br />$1");
}

proto.filters.html_line_break = function(text) {
    return text.replace(/(\r?\n)/g, "$1<br />$1");
}

proto.filters.uri = function(text) {
    return encodeURI(text);
}

proto.filters.indent = function(text, args) {
    var pad = args[0];
    if (! text) return;
    if (typeof pad == 'undefined')
        pad = 4;

    var finalpad = '';
    if (typeof pad == 'number' || String(pad).match(/^\d$/)) {
        for (var i = 0; i < pad; i++) {
            finalpad += ' ';
        }
    } else {
        finalpad = pad;
    }
    var output = text.replace(/^/gm, finalpad);
    return output;
}

proto.filters.truncate = function(text, args) {
    var len = args[0];
    if (! text) return;
    if (! len)
        len = 32;
    // This should probably be <=, but TT just uses <
    if (text.length < len)
        return text;
    var newlen = len - 3;
    return text.substr(0,newlen) + '...';
}

proto.filters.repeat = function(text, iter) {
    if (! text) return;
    if (! iter || iter == 0)
        iter = 1;
    if (iter == 1) return text

    var output = text;
    for (var i = 1; i < iter; i++) {
        output += text;
    }
    return output;
}

proto.filters.replace = function(text, args) {
    if (! text) return;
    var re_search = args[0];
    var text_replace = args[1];
    if (! re_search)
        re_search = '';
    if (! text_replace)
        text_replace = '';
    var re = new RegExp(re_search, 'g');
    return text.replace(re, text_replace);
}

//------------------------------------------------------------------------------
// Jemplate.Stash class
//------------------------------------------------------------------------------
if (typeof Jemplate.Stash == 'undefined') {
    Jemplate.Stash = function() {
        this.data = {};
    };
}

proto = Jemplate.Stash.prototype;

proto.clone = function(args) {
    var data = this.data;
    this.data = {};
    this.update(data);
    this.update(args);
    this.data._PARENT = data;
}

proto.declone = function(args) {
    this.data = this.data._PARENT || this.data;
}

proto.update = function(args) {
    if (typeof args == 'undefined') return;
    for (var key in args) {
        var value = args[key];
        this.set(key, value);
    }
}

proto.get = function(key) {
    var root = this.data;
    if (key instanceof Array) {
        for (var i = 0; i < key.length; i += 2) {
            var args = key.slice(i, i+2);
            args.unshift(root);
            value = this._dotop.apply(this, args);
            if (typeof value == 'undefined')
                break;
            root = value;
        }
    }
    else {
        value = this._dotop(root, key);
    }

    if (typeof value == 'undefined') {
        if (this.__config__.DEBUG_UNDEF)
            throw("undefined value found while using DEGUG_UNDEF");
        value = '';
    }

    return value;
}

proto.set = function(key, value, set_default) {
    if (key instanceof Array) {
        var data = this.get(key[0]) || {};
        key = key[2];
    }
    else {
        data = this.data;
    }
    if (! (set_default && (typeof data[key] != 'undefined')))
        data[key] = value;
}

proto._dotop = function(root, item, args) {
    if (typeof item == 'undefined' ||
        typeof item == 'string' && item.match(/^[\._]/)) {
        return undefined;
    }

    if ((! args) &&
        (typeof root == 'object') &&
        (!(root instanceof Array) || (typeof item == 'number')) &&
        (typeof root[item] != 'undefined')) {
        var value = root[item];
        if (typeof value == 'function')
            value = value();
        return value;
    }

    if (typeof root == 'string' && this.string_functions[item])
        return this.string_functions[item](root, args);
    if (root instanceof Array && this.list_functions[item])
        return this.list_functions[item](root, args);
    if (typeof root == 'object' && this.hash_functions[item])
        return this.hash_functions[item](root, args);
    if (typeof root[item] == 'function')
        return root[item].apply(root, args);

    return undefined;
}

proto.string_functions = {};

// chunk(size)     negative size chunks from end
proto.string_functions.chunk = function(string, args) {
    var size = args[0];
    var list = new Array();
    if (! size)
        size = 1;
    if (size < 0) {
        size = 0 - size;
        for (i = string.length - size; i >= 0; i = i - size)
            list.unshift(string.substr(i, size));
        if (string.length % size)
            list.unshift(string.substr(0, string.length % size));
    }
    else
        for (i = 0; i < string.length; i = i + size)
            list.push(string.substr(i, size));
    return list;
}

// defined         is value defined?
proto.string_functions.defined = function(string) {
    return 1;
}

// hash            treat as single-element hash with key value
proto.string_functions.hash = function(string) {
    return { 'value': string };
}

// length          length of string representation
proto.string_functions.length = function(string) {
    return string.length;
}

// list            treat as single-item list
proto.string_functions.list = function(string) {
    return [ string ];
}

// match(re)       get list of matches
proto.string_functions.match = function(string, args) {
    var regexp = new RegExp(args[0], 'gm');
    var list = string.match(regexp);
    return list;
}

// repeat(n)       repeated n times
proto.string_functions.repeat = function(string, args) {
    var n = args[0] || 1;
    var output = '';
    for (var i = 0; i < n; i++) {
        output += string;
    }
    return output;
}

// replace(re, sub)    replace instances of re with sub
proto.string_functions.replace = function(string, args) {
    var regexp = new RegExp(args[0], 'gm');
    var sub = args[1];
    if (! sub)
        sub  = '';
    var output = string.replace(regexp, sub);
    return output;
}

// search(re)      true if value matches re
proto.string_functions.search = function(string, args) {
    var regexp = new RegExp(args[0]);
    return (string.search(regexp) >= 0) ? 1 : 0;
}

// size            returns 1, as if a single-item list
proto.string_functions.size = function(string) {
    return 1;
}

// split(re)       split string on re
proto.string_functions.split = function(string, args) {
    var regexp = new RegExp(args[0]);
    var list = string.split(regexp);
    return list;
}



proto.list_functions = {};

proto.list_functions.join = function(list, args) {
    return list.join(args[0]);
};

proto.list_functions.sort = function(list,key) {
    if( typeof(key) != 'undefined' && key != "" ) {
        // we probably have a list of hashes
        // and need to sort based on hash key
        return list.sort(
            function(a,b) {
                if( a[key] == b[key] ) {
                    return 0;
                }
                else if( a[key] > b[key] ) {
                    return 1;
                }
                else {
                    return -1;
                }
            }
        );
    }
    return list.sort();
}

proto.list_functions.nsort = function(list) {
    return list.sort(function(a, b) { return (a-b) });
}

proto.list_functions.grep = function(list, args) {
    var regexp = new RegExp(args[0]);
    var result = [];
    for (var i = 0; i < list.length; i++) {
        if (list[i].match(regexp))
            result.push(list[i]);
    }
    return result;
}

proto.list_functions.unique = function(list) {
    var result = [];
    var seen = {};
    for (var i = 0; i < list.length; i++) {
        var elem = list[i];
        if (! seen[elem])
            result.push(elem);
        seen[elem] = true;
    }
    return result;
}

proto.list_functions.reverse = function(list) {
    var result = [];
    for (var i = list.length - 1; i >= 0; i--) {
        result.push(list[i]);
    }
    return result;
}

proto.list_functions.merge = function(list, args) {
    var result = [];
    var push_all = function(elem) {
        if (elem instanceof Array) {
            for (var j = 0; j < elem.length; j++) {
                result.push(elem[j]);
            }
        }
        else {
            result.push(elem);
        }
    }
    push_all(list);
    for (var i = 0; i < args.length; i++) {
        push_all(args[i]);
    }
    return result;
}

proto.list_functions.slice = function(list, args) {
    return list.slice(args[0], args[1]);
}

proto.list_functions.splice = function(list, args) {
    if (args.length == 1)
        return list.splice(args[0]);
    if (args.length == 2)
        return list.splice(args[0], args[1]);
    if (args.length == 3)
        return list.splice(args[0], args[1], args[2]);
}

proto.list_functions.push = function(list, args) {
    list.push(args[0]);
    return list;
}

proto.list_functions.pop = function(list) {
    return list.pop();
}

proto.list_functions.unshift = function(list, args) {
    list.unshift(args[0]);
    return list;
}

proto.list_functions.shift = function(list) {
    return list.shift();
}

proto.list_functions.first = function(list) {
    return list[0];
}

proto.list_functions.size = function(list) {
    return list.length;
}

proto.list_functions.max = function(list) {
    return list.length - 1;
}

proto.list_functions.last = function(list) {
    return list.slice(-1);
}

proto.hash_functions = {};


// each            list of alternating keys/values
proto.hash_functions.each = function(hash) {
    var list = new Array();
    for ( var key in hash )
        list.push(key, hash[key]);
    return list;
}

// exists(key)     does key exist?
proto.hash_functions.exists = function(hash, args) {
    return ( typeof( hash[args[0]] ) == "undefined" ) ? 0 : 1;
}

// FIXME proto.hash_functions.import blows everything up
//
// import(hash2)   import contents of hash2
// import          import into current namespace hash
//proto.hash_functions.import = function(hash, args) {
//    var hash2 = args[0];
//    for ( var key in hash2 )
//        hash[key] = hash2[key];
//    return '';
//}

// keys            list of keys
proto.hash_functions.keys = function(hash) {
    var list = new Array();
    for ( var key in hash )
        list.push(key);
    return list;
}

// list            returns alternating key, value
proto.hash_functions.list = function(hash, args) {
    var what = '';
    if ( args )
        var what = args[0];

    var list = new Array();
    if (what == 'keys')
        for ( var key in hash )
            list.push(key);
    else if (what == 'values')
        for ( var key in hash )
            list.push(hash[key]);
    else if (what == 'each')
        for ( var key in hash )
            list.push(key, hash[key]);
    else
        for ( var key in hash )
            list.push({ 'key': key, 'value': hash[key] });

    return list;
}

// nsort           keys sorted numerically
proto.hash_functions.nsort = function(hash) {
    var list = new Array();
    for (var key in hash)
        list.push(key);
    return list.sort(function(a, b) { return (a-b) });
}

// size            number of pairs
proto.hash_functions.size = function(hash) {
    var size = 0;
    for (var key in hash)
        size++;
    return size;
}


// sort            keys sorted alphabetically
proto.hash_functions.sort = function(hash) {
    var list = new Array();
    for (var key in hash)
        list.push(key);
    return list.sort();
}

// values          list of values
proto.hash_functions.values = function(hash) {
    var list = new Array();
    for ( var key in hash )
        list.push(hash[key]);
    return list;
}



//------------------------------------------------------------------------------
// Jemplate.Iterator class
//------------------------------------------------------------------------------
if (typeof Jemplate.Iterator == 'undefined') {
    Jemplate.Iterator = function(object) {
        if( object instanceof Array ) {
            this.object = object;
            this.size = object.length;
            this.max  = this.size -1;
        }
        else if ( object instanceof Object ) {
            this.object = object;
            var object_keys = new Array;
            for( var key in object ) {
                object_keys[object_keys.length] = key;
            }
            this.object_keys = object_keys.sort();
            this.size = object_keys.length;
            this.max  = this.size -1;
        }
    }
}

proto = Jemplate.Iterator.prototype;

proto.get_first = function() {
    this.index = 0;
    this.first = 1;
    this.last  = 0;
    this.count = 1;
    return this.get_next(1);
}

proto.get_next = function(should_init) {
    var object = this.object;
    var index;
    if( typeof(should_init) != 'undefined' && should_init ) {
        index = this.index;
    } else {
        index = ++this.index;
        this.first = 0;
        this.count = this.index + 1;
        if( this.index == this.size -1 ) {
            this.last = 1;
        }
    }
    if (typeof object == 'undefined')
        throw('No object to iterate');
    if( this.object_keys ) {
        if (index < this.object_keys.length) {
            this.prev = index > 0 ? this.object_keys[index - 1] : "";
            this.next = index < this.max ? this.object_keys[index + 1] : "";
            return [this.object_keys[index], false];
        }
    } else {
        if (index < object.length) {
            this.prev = index > 0 ? object[index - 1] : "";
            this.next = index < this.max ? object[index +1] : "";
            return [object[index], false];
        }
    }
    return [null, true];
}

//------------------------------------------------------------------------------
// Debugging Support
//------------------------------------------------------------------------------

function XXX(msg) {
    if (! confirm(msg))
        throw("terminated...");
    return msg;
}

function JJJ(obj) {
    return XXX(JSON.stringify(obj));
}

//------------------------------------------------------------------------------
// Ajax support
//------------------------------------------------------------------------------
if (! this.Ajax) Ajax = {};

Ajax.get = function(url, callback) {
    var req = new XMLHttpRequest();
    req.open('GET', url, Boolean(callback));
    return Ajax._send(req, null, callback);
}

Ajax.post = function(url, data, callback) {
    var req = new XMLHttpRequest();
    req.open('POST', url, Boolean(callback));
    req.setRequestHeader(
        'Content-Type',
        'application/x-www-form-urlencoded'
    );
    return Ajax._send(req, data, callback);
}

Ajax._send = function(req, data, callback) {
    if (callback) {
        req.onreadystatechange = function() {
            if (req.readyState == 4) {
                if(req.status == 200)
                    callback(req.responseText);
            }
        };
    }
    req.send(data);
    if (!callback) {
        if (req.status != 200)
            throw('Request for "' + url +
                  '" failed with status: ' + req.status);
        return req.responseText;
    }
}

//------------------------------------------------------------------------------
// Cross-Browser XMLHttpRequest v1.1
//------------------------------------------------------------------------------
/*
Emulate Gecko 'XMLHttpRequest()' functionality in IE and Opera. Opera requires
the Sun Java Runtime Environment <http://www.java.com/>.

by Andrew Gregory
http://www.scss.com.au/family/andrew/webdesign/xmlhttprequest/

This work is licensed under the Creative Commons Attribution License. To view a
copy of this license, visit http://creativecommons.org/licenses/by/1.0/ or send
a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305,
USA.
*/

// IE support
if (window.ActiveXObject && !window.XMLHttpRequest) {
  window.XMLHttpRequest = function() {
    return new ActiveXObject((navigator.userAgent.toLowerCase().indexOf('msie 5') != -1) ? 'Microsoft.XMLHTTP' : 'Msxml2.XMLHTTP');
  };
}

// Opera support
if (window.opera && !window.XMLHttpRequest) {
  window.XMLHttpRequest = function() {
    this.readyState = 0; // 0=uninitialized,1=loading,2=loaded,3=interactive,4=complete
    this.status = 0; // HTTP status codes
    this.statusText = '';
    this._headers = [];
    this._aborted = false;
    this._async = true;
    this.abort = function() {
      this._aborted = true;
    };
    this.getAllResponseHeaders = function() {
      return this.getAllResponseHeader('*');
    };
    this.getAllResponseHeader = function(header) {
      var ret = '';
      for (var i = 0; i < this._headers.length; i++) {
        if (header == '*' || this._headers[i].h == header) {
          ret += this._headers[i].h + ': ' + this._headers[i].v + '\n';
        }
      }
      return ret;
    };
    this.setRequestHeader = function(header, value) {
      this._headers[this._headers.length] = {h:header, v:value};
    };
    this.open = function(method, url, async, user, password) {
      this.method = method;
      this.url = url;
      this._async = true;
      this._aborted = false;
      if (arguments.length >= 3) {
        this._async = async;
      }
      if (arguments.length > 3) {
        // user/password support requires a custom Authenticator class
        opera.postError('XMLHttpRequest.open() - user/password not supported');
      }
      this._headers = [];
      this.readyState = 1;
      if (this.onreadystatechange) {
        this.onreadystatechange();
      }
    };
    this.send = function(data) {
      if (!navigator.javaEnabled()) {
        alert("XMLHttpRequest.send() - Java must be installed and enabled.");
        return;
      }
      if (this._async) {
        setTimeout(this._sendasync, 0, this, data);
        // this is not really asynchronous and won't execute until the current
        // execution context ends
      } else {
        this._sendsync(data);
      }
    }
    this._sendasync = function(req, data) {
      if (!req._aborted) {
        req._sendsync(data);
      }
    };
    this._sendsync = function(data) {
      this.readyState = 2;
      if (this.onreadystatechange) {
        this.onreadystatechange();
      }
      // open connection
      var url = new java.net.URL(new java.net.URL(window.location.href), this.url);
      var conn = url.openConnection();
      for (var i = 0; i < this._headers.length; i++) {
        conn.setRequestProperty(this._headers[i].h, this._headers[i].v);
      }
      this._headers = [];
      if (this.method == 'POST') {
        // POST data
        conn.setDoOutput(true);
        var wr = new java.io.OutputStreamWriter(conn.getOutputStream());
        wr.write(data);
        wr.flush();
        wr.close();
      }
      // read response headers
      // NOTE: the getHeaderField() methods always return nulls for me :(
      var gotContentEncoding = false;
      var gotContentLength = false;
      var gotContentType = false;
      var gotDate = false;
      var gotExpiration = false;
      var gotLastModified = false;
      for (var i = 0; ; i++) {
        var hdrName = conn.getHeaderFieldKey(i);
        var hdrValue = conn.getHeaderField(i);
        if (hdrName == null && hdrValue == null) {
          break;
        }
        if (hdrName != null) {
          this._headers[this._headers.length] = {h:hdrName, v:hdrValue};
          switch (hdrName.toLowerCase()) {
            case 'content-encoding': gotContentEncoding = true; break;
            case 'content-length'  : gotContentLength   = true; break;
            case 'content-type'    : gotContentType     = true; break;
            case 'date'            : gotDate            = true; break;
            case 'expires'         : gotExpiration      = true; break;
            case 'last-modified'   : gotLastModified    = true; break;
          }
        }
      }
      // try to fill in any missing header information
      var val;
      val = conn.getContentEncoding();
      if (val != null && !gotContentEncoding) this._headers[this._headers.length] = {h:'Content-encoding', v:val};
      val = conn.getContentLength();
      if (val != -1 && !gotContentLength) this._headers[this._headers.length] = {h:'Content-length', v:val};
      val = conn.getContentType();
      if (val != null && !gotContentType) this._headers[this._headers.length] = {h:'Content-type', v:val};
      val = conn.getDate();
      if (val != 0 && !gotDate) this._headers[this._headers.length] = {h:'Date', v:(new Date(val)).toUTCString()};
      val = conn.getExpiration();
      if (val != 0 && !gotExpiration) this._headers[this._headers.length] = {h:'Expires', v:(new Date(val)).toUTCString()};
      val = conn.getLastModified();
      if (val != 0 && !gotLastModified) this._headers[this._headers.length] = {h:'Last-modified', v:(new Date(val)).toUTCString()};
      // read response data
      var reqdata = '';
      var stream = conn.getInputStream();
      if (stream) {
        var reader = new java.io.BufferedReader(new java.io.InputStreamReader(stream));
        var line;
        while ((line = reader.readLine()) != null) {
          if (this.readyState == 2) {
            this.readyState = 3;
            if (this.onreadystatechange) {
              this.onreadystatechange();
            }
          }
          reqdata += line + '\n';
        }
        reader.close();
        this.status = 200;
        this.statusText = 'OK';
        this.responseText = reqdata;
        this.readyState = 4;
        if (this.onreadystatechange) {
          this.onreadystatechange();
        }
        if (this.onload) {
          this.onload();
        }
      } else {
        // error
        this.status = 404;
        this.statusText = 'Not Found';
        this.responseText = '';
        this.readyState = 4;
        if (this.onreadystatechange) {
          this.onreadystatechange();
        }
        if (this.onerror) {
          this.onerror();
        }
      }
    };
  };
}
// ActiveXObject emulation
if (!window.ActiveXObject && window.XMLHttpRequest) {
  window.ActiveXObject = function(type) {
    switch (type.toLowerCase()) {
      case 'microsoft.xmlhttp':
      case 'msxml2.xmlhttp':
        return new XMLHttpRequest();
    }
    return null;
  };
}


//------------------------------------------------------------------------------
// JSON Support
//------------------------------------------------------------------------------

/*
Copyright (c) 2005 JSON.org
*/
var JSON = function () {
    var m = {
            '\b': '\\b',
            '\t': '\\t',
            '\n': '\\n',
            '\f': '\\f',
            '\r': '\\r',
            '"' : '\\"',
            '\\': '\\\\'
        },
        s = {
            'boolean': function (x) {
                return String(x);
            },
            number: function (x) {
                return isFinite(x) ? String(x) : 'null';
            },
            string: function (x) {
                if (/["\\\x00-\x1f]/.test(x)) {
                    x = x.replace(/([\x00-\x1f\\"])/g, function(a, b) {
                        var c = m[b];
                        if (c) {
                            return c;
                        }
                        c = b.charCodeAt();
                        return '\\u00' +
                            Math.floor(c / 16).toString(16) +
                            (c % 16).toString(16);
                    });
                }
                return '"' + x + '"';
            },
            object: function (x) {
                if (x) {
                    var a = [], b, f, i, l, v;
                    if (x instanceof Array) {
                        a[0] = '[';
                        l = x.length;
                        for (i = 0; i < l; i += 1) {
                            v = x[i];
                            f = s[typeof v];
                            if (f) {
                                v = f(v);
                                if (typeof v == 'string') {
                                    if (b) {
                                        a[a.length] = ',';
                                    }
                                    a[a.length] = v;
                                    b = true;
                                }
                            }
                        }
                        a[a.length] = ']';
                    } else if (x instanceof Object) {
                        a[0] = '{';
                        for (i in x) {
                            v = x[i];
                            f = s[typeof v];
                            if (f) {
                                v = f(v);
                                if (typeof v == 'string') {
                                    if (b) {
                                        a[a.length] = ',';
                                    }
                                    a.push(s.string(i), ':', v);
                                    b = true;
                                }
                            }
                        }
                        a[a.length] = '}';
                    } else {
                        return;
                    }
                    return a.join('');
                }
                return 'null';
            }
        };
    return {
        copyright: '(c)2005 JSON.org',
        license: 'http://www.crockford.com/JSON/license.html',
        stringify: function (v) {
            var f = s[typeof v];
            if (f) {
                v = f(v);
                if (typeof v == 'string') {
                    return v;
                }
            }
            return null;
        },
        parse: function (text) {
            try {
                return !(/[^,:{}\[\]0-9.\-+Eaeflnr-u \n\r\t]/.test(
                        text.replace(/"(\\.|[^"\\])*"/g, ''))) &&
                    eval('(' + text + ')');
            } catch (e) {
                return false;
            }
        }
    };
}();

;

/*
   This JavaScript code was generated by Jemplate, the JavaScript
   Template Toolkit. Any changes made to this file will be lost the next
   time the templates are compiled.

   Copyright 2006 - Ingy döt Net - All rights reserved.
*/

if (typeof(Jemplate) == 'undefined')
    throw('Jemplate.js must be loaded before any Jemplate template files');

Jemplate.templateMap['select.html'] = function(context) {
    if (! context) throw('Jemplate function called without context\n');
    var stash = context.stash;
    var output = '';

    try {
output += '<div>\n    <h3 style="margin-top: 0;">Select a Socialtext Skin:</h3>\n    <form id="skin-select-form" onsubmit="return false;">\n        <select name="skin-name">\n            ';
//line 7 "select.html"

// FOREACH 
(function() {
    var list = stash.get('skins');
    list = new Jemplate.Iterator(list);
    var retval = list.get_first();
    var value = retval[0];
    var done = retval[1];
    var oldloop;
    try { oldloop = stash.get('loop') } finally {}
    stash.set('loop', list);
    try {
        while (! done) {
            stash.data['skin'] = value;
output += '\n            <option value="';
//line 6 "select.html"
output += stash.get('skin');
output += '">';
//line 6 "select.html"
output += stash.get('skin');
output += '</option>\n            ';;
            retval = list.get_next();
            value = retval[0];
            done = retval[1];
        }
    }
    catch(e) {
        throw(context.set_error(e, output));
    }
    stash.set('loop', oldloop);
})();

output += '\n        </select>\n        <br />\n        <br />\n        <input name="select" type="submit" value="Select" />&nbsp;\n        <input name="cancel" type="submit" value="Cancel" />\n    </form>\n    <p style="font-size: smaller; font-weight: bold; font-style: italic;">Note: this will change the Socialtext Skin only for your browser and only on this particular workspace. Nobody else will be affected and you can change it back at any time.</p>\n</div>\n';
    }
    catch(e) {
        var error = context.set_error(e, output);
        throw(error);
    }

    return output;
}


;

// Cookie handling functions

Cookie = {};

Cookie.get = function(name) {
    var cookieStart = document.cookie.indexOf(name + "=");
    if (cookieStart == -1) return null;
    var valueStart = document.cookie.indexOf('=', cookieStart) + 1;
    var valueEnd = document.cookie.indexOf(';', valueStart);
    if (valueEnd == -1) valueEnd = document.cookie.length;
    var val = document.cookie.substring(valueStart, valueEnd);
    return val == null
        ? null
        : unescape(document.cookie.substring(valueStart, valueEnd));
}

Cookie.set = function(name, val, expiration) {
    // Default to 25 year expiry if not specified by the caller.
    if (typeof(expiration) == 'undefined') {
        expiration = new Date(
            new Date().getTime() + 25 * 365 * 24 * 60 * 60 * 1000
        )
    }
    var str = name + '=' + escape(val) +
        '; expires=' + expiration.toGMTString();
    document.cookie = str;
}

Cookie['delete'] = function(name) {
    Cookie.set(name, '', new Date(new Date().getTime() - 1));
}


;

AllSkins = [
    "s2 - Socialtext Classic Skin",
"abcwiki - ABC, it's as easy as 123",
"angel - Angel.com",
"angel2 - Angel.com",
"atsu - A.T. Still University",
"cex - Socialtext Customer Exchange",
"defragCon",
"drkw - Dresdner Kleinwort",
"dvp - DVP",
"dymo - Newell Rubbermaid",
"ebsworth - Ebsworth & Ebsworth",
"euriki - Euriki - Eurogroup Consulting Alliance",
"greenmountain - GreenMountain Engineering",
"humana - HUMANA",
"humanity - Humanity United",
"ideo - IDEO",
"infosys - CII Knowledge",
"law-wiki - Law Wiki",
"lp - Loan Performance",
"mosaic - Mosaic Knowledge Exchange",
"netapp - NetApp",
"netappacc - NetApp accenture",
"netappbp - NetApp BearingPoint",
"netapppqr - NetApp PQR (Partner Quarterly Roadshows)",
"netel - tel3.com",
"netsuite - NETSUITE Professional Services",
"newsgator - NewsGator",
"ogilvypr - 360º Digital Influence",
"omidyar - Omidyar Network",
"open - Socialtext OPEN",
"orrick - Orrick",
"pbwt - Patterson Belnap Webb & Taylor",
"pearson - Pearson",
"pinstripe - Pinstripe",
"referencemd - ReferenceMD - For Physicians by Physicians",
"rhio - RHIO",
"s2 - Socialtext Classic Skin",
"sap - SAP",
"symantec - Symantec",
"target - Target",
"tenacity - Tenacity Solutions Inc",
"unicef-education - Unicef Education",
"unicef-emergency - Unicef Emergency",
"uohio - Ohio Metaversity",
"vanilla - Proof of Concept REST API Skin",
"versalogic - VersaLogic Corporation",
"wapo - Washington Post",
"wikinomics - WIKINOMICS",
"wired - Wired Magazine"
];

;

if (typeof JSAN == 'undefined') JSAN = {};

JSAN.use = function() {};

if ( typeof DOM == "undefined" ) DOM = {};

DOM.Ready = {};

DOM.Ready.VERSION = '0.14';

DOM.Ready.finalTimeout = 15;
DOM.Ready.timerInterval = 50;

/* This works for Mozilla */
if ( document.addEventListener ) {
    document.addEventListener
        ( "DOMContentLoaded", function () { DOM.Ready._isDone = 1; }, false );
}

DOM.Ready._checkDOMReady = function () {
    if ( DOM.Ready._isReady ) return DOM.Ready._isReady;

    if (    typeof document.getElementsByTagName != 'undefined'
         && typeof document.getElementById != 'undefined' 
         && ( document.getElementsByTagName('body')[0] != null
              || document.body != null ) ) {

        DOM.Ready._isReady = 1;
    }

    return DOM.Ready._isReady;

};

DOM.Ready._checkDOMDone = function () {
    /* IE (and Opera?) only */
    if ( document.readyState
         && ( document.readyState == "interactive"
              || document.readyState == "complete" ) ) {
        return 1;
    }

    return DOM.Ready._isDone;
};

DOM.Ready.onDOMReady = function (callback) {
    if ( DOM.Ready._checkDOMReady() ) {
        callback();
    }
    else {
        DOM.Ready._onDOMReadyCallbacks.push(callback);
    }
}

DOM.Ready.onDOMDone = function (callback) {
    if ( DOM.Ready._checkDOMDone() ) {
        callback();
    }
    else {
        DOM.Ready._onDOMDoneCallbacks.push(callback);
    }
}

DOM.Ready.onIdReady = function ( id, callback ) {
    if ( DOM.Ready._checkDOMReady() ) {
        var elt = document.getElementById(id);
        if (elt) {
            callback(elt);
            return;
        }
    }

    var callback_array = DOM.Ready._onIdReadyCallbacks[id];
    if ( ! callback_array ) {
        callback_array = [];
    }
    callback_array.push(callback);

    DOM.Ready._onIdReadyCallbacks[id] = callback_array;
}

DOM.Ready._runDOMReadyCallbacks = function () {
    for ( var i = 0; i < DOM.Ready._onDOMReadyCallbacks.length; i++ ) {
        DOM.Ready._onDOMReadyCallbacks[i]();
    }

    DOM.Ready._onDOMReadyCallbacks = [];
}

DOM.Ready._runDOMDoneCallbacks = function () {
    for ( var i = 0; i < DOM.Ready._onDOMDoneCallbacks.length; i++ ) {
        DOM.Ready._onDOMDoneCallbacks[i]();
    }

    DOM.Ready._onDOMDoneCallbacks = [];
}

DOM.Ready._runIdCallbacks = function () {
    for ( var id in DOM.Ready._onIdReadyCallbacks ) {
        // protect against changes to Object (ala prototype's extend)
        if ( ! DOM.Ready._onIdReadyCallbacks.hasOwnProperty(id) ) {
            continue;
        }

        var elt = document.getElementById(id);

        if (elt) {
            for ( var i = 0; i < DOM.Ready._onIdReadyCallbacks[id].length; i++) {
                DOM.Ready._onIdReadyCallbacks[id][i](elt);
            }

            delete DOM.Ready._onIdReadyCallbacks[id];
        }
    }
}

DOM.Ready._runReadyCallbacks = function () {
    if ( DOM.Ready._inRunReadyCallbacks ) return;

    DOM.Ready._inRunReadyCallbacks = 1;

    if ( DOM.Ready._checkDOMReady() ) {
        DOM.Ready._runDOMReadyCallbacks();

        DOM.Ready._runIdCallbacks();
    }

    if ( DOM.Ready._checkDOMDone() ) {
        DOM.Ready._runDOMDoneCallbacks();
    }

    DOM.Ready._timePassed += DOM.Ready._lastTimerInterval;

    if ( ( DOM.Ready._timePassed / 1000 ) >= DOM.Ready.finalTimeout ) {
        DOM.Ready._stopTimer();
    }

    DOM.Ready._inRunReadyCallbacks = 0;
}

DOM.Ready._startTimer = function () {
    DOM.Ready._lastTimerInterval = DOM.Ready.timerInterval;
    DOM.Ready._intervalId = setInterval( DOM.Ready._runReadyCallbacks, DOM.Ready.timerInterval );
};

DOM.Ready._stopTimer = function () {
    clearInterval( DOM.Ready._intervalId );
    DOM.Ready._intervalId = null;
}

DOM.Ready._resetClass = function () {
    DOM.Ready._stopTimer();

    DOM.Ready._timePassed = 0;

    DOM.Ready._isReady = 0;
    DOM.Ready._isDone = 0;

    DOM.Ready._onDOMReadyCallbacks = [];
    DOM.Ready._onDOMDoneCallbacks = [];
    DOM.Ready._onIdReadyCallbacks = {};

    DOM.Ready._startTimer();
}

DOM.Ready._resetClass();

DOM.Ready.runCallbacks = function () { DOM.Ready._runReadyCallbacks() };


/*

*/
/**

=head1 NAME

DOM.Events - Event registration abstraction layer

=head1 SYNOPSIS

  JSAN.use("DOM.Events");

  function handleClick(e) {
      e.currentTarget.style.backgroundColor = "#68b";
  }

  DOM.Events.addListener(window, "load", function () {
      alert("The page is loaded.");
  });

  DOM.Events.addListener(window, "load", function () {
      // this listener won't interfere with the first one
      var divs = document.getElementsByTagName("div");
      for(var i=0; i<divs.length; i++) {
          DOM.Events.addListener(divs[i], "click", handleClick);
      }
  });

=head1 DESCRIPTION

This library lets you use a single interface to listen for and handle all DOM events
to reduce browser-specific code branching.  It also helps in dealing with Internet
Explorer's memory leak problem by automatically unsetting all event listeners when
the page is unloaded (for IE only).

=cut

*/

(function () {
	if(typeof DOM == "undefined") DOM = {};
	DOM.Events = {};
	
    DOM.Events.VERSION = "0.02";
	DOM.Events.EXPORT = [];
	DOM.Events.EXPORT_OK = ["addListener", "removeListener"];
	DOM.Events.EXPORT_TAGS = {
		":common": DOM.Events.EXPORT,
		":all": [].concat(DOM.Events.EXPORT, DOM.Events.EXPORT_OK)
	};
	
	// list of event listeners set by addListener
	// offset 0 is null to prevent 0 from being used as a listener identifier
	var listenerList = [null];
	
/**

=head2 Functions

All functions are kept inside the namespace C<DOM.Events> and aren't exported
automatically.

=head3 addListener( S<I<HTMLElement> element,> S<I<string> eventType,>
S<I<Function> handler> S<[, I<boolean> makeCompatible = true] )>

Registers an event listener/handler on an element.  The C<eventType> string should
I<not> be prefixed with "on" (e.g. "mouseover" not "onmouseover"). If C<makeCompatible>
is C<true> (the default), the handler is put inside a wrapper that lets you handle the
events using parts of the DOM Level 2 Events model, even in Internet Explorer (and
behave-alikes). Specifically:

=over

=item *

The event object is passed as the first argument to the event handler, so you don't
have to access it through C<window.event>.

=item *

The event object has the properties C<target>, C<currentTarget>, and C<relatedTarget>
and the methods C<preventDefault()> and C<stopPropagation()> that behave as described
in the DOM Level 2 Events specification (for the most part).

=item *

If possible, the event object for mouse events will have the properties C<pageX> and
C<pageY> that contain the mouse's position relative to the document at the time the
event occurred.

=item *

If you attempt to set a duplicate event handler on an element, the duplicate will
still be added (this is different from the DOM2 Events model, where duplicates are
discarded).

=back

If C<makeCompatible> is C<false>, the arguments are simply passed to the browser's
native event registering facilities, which means you'll have to deal with event
incompatibilities yourself. However, if you don't need to access the event information,
doing it this way can be slightly faster and it gives you the option of unsetting the
handler with a different syntax (see below).

The return value is a positive integer identifier for the listener that can be used to
unregister it later on in your script.

=cut

*/
    
	DOM.Events.addListener = function(elt, ev, func, makeCompatible) {
		var usedFunc = func;
        var id = listenerList.length;
		if(makeCompatible == true || makeCompatible == undefined) {
			usedFunc = makeCompatibilityWrapper(elt, ev, func);
		}
		if(elt.addEventListener) {
			elt.addEventListener(ev, usedFunc, false);
			listenerList[id] = [elt, ev, usedFunc];
			return id;
		}
		else if(elt.attachEvent) {
			elt.attachEvent("on" + ev, usedFunc);
			listenerList[id] = [elt, ev, usedFunc];
			return id;
		}
		else return false;
	};
	
/**

=head3 removeListener( S<I<integer> identifier> )

Unregisters the event listener associated with the given identifier so that it will
no longer be called when the event fires.

  var listener = DOM.Events.addListener(myElement, "mousedown", myHandler);
  // later on ...
  DOM.Events.removeListener(listener);

=head3 removeListener( S<I<HTMLElement> element,> S<I<string> eventType,> S<I<Function> handler )>

This alternative syntax can be also be used to unset an event listener, but it can only
be used if C<makeCompatible> was C<false> when it was set.

=cut

*/

	DOM.Events.removeListener = function() {
		var elt, ev, func;
		if(arguments.length == 1 && listenerList[arguments[0]]) {
			elt  = listenerList[arguments[0]][0];
			ev   = listenerList[arguments[0]][1];
			func = listenerList[arguments[0]][2];
			delete listenerList[arguments[0]];
		}
		else if(arguments.length == 3) {
			elt  = arguments[0];
			ev   = arguments[1];
			func = arguments[2];
		}
		else return;
		
		if(elt.removeEventListener) {
			elt.removeEventListener(ev, func, false);
		}
		else if(elt.detachEvent) {
			elt.detachEvent("on" + ev, func);
		}
	};
	
    var rval;
    
    function makeCompatibilityWrapper(elt, ev, func) {
        return function (e) {
            rval = true;
            if(e == undefined && window.event != undefined)
                e = window.event;
            if(e.target == undefined && e.srcElement != undefined)
                e.target = e.srcElement;
            if(e.currentTarget == undefined)
                e.currentTarget = elt;
            if(e.relatedTarget == undefined) {
                if(ev == "mouseover" && e.fromElement != undefined)
                    e.relatedTarget = e.fromElement;
                else if(ev == "mouseout" && e.toElement != undefined)
                    e.relatedTarget = e.toElement;
            }
            if(e.pageX == undefined) {
                if(document.body.scrollTop != undefined) {
                    e.pageX = e.clientX + document.body.scrollLeft;
                    e.pageY = e.clientY + document.body.scrollTop;
                }
                if(document.documentElement != undefined
                && document.documentElement.scrollTop != undefined) {
                    if(document.documentElement.scrollTop > 0
                    || document.documentElement.scrollLeft > 0) {
                        e.pageX = e.clientX + document.documentElement.scrollLeft;
                        e.pageY = e.clientY + document.documentElement.scrollTop;
                    }
                }
            }
            if(e.stopPropagation == undefined)
                e.stopPropagation = IEStopPropagation;
            if(e.preventDefault == undefined)
                e.preventDefault = IEPreventDefault;
            if(e.cancelable == undefined) e.cancelable = true;
            func(e);
            return rval;
        };
    }
    
    function IEStopPropagation() {
        if(window.event) window.event.cancelBubble = true;
    }
    
    function IEPreventDefault() {
        rval = false;
    }

	function cleanUpIE () {
		for(var i=0; i<listenerList.length; i++) {
			var listener = listenerList[i];
			if(listener) {
				var elt = listener[0];
                var ev = listener[1];
                var func = listener[2];
				elt.detachEvent("on" + ev, func);
			}
		}
        listenerList = null;
	}

	if(!window.addEventListener && window.attachEvent) {
		window.attachEvent("onunload", cleanUpIE);
	}

})();

/**

=head1 SEE ALSO

DOM Level 2 Events Specification,
L<http://www.w3.org/TR/DOM-Level-2-Events/>

Understanding and Solving Internet Explorer Leak Patterns,
L<http://msdn.microsoft.com/library/default.asp?url=/library/en-us/IETechCol/dnwebgen/ie_leak_patterns.asp>

=head1 AUTHOR

Justin Constantino, <F<goflyapig@gmail.com>>.

=head1 COPYRIGHT

  Copyright (c) 2005 Justin Constantino.  All rights reserved.
  This module is free software; you can redistribute it and/or modify it
  under the terms of the GNU Lesser General Public Licence.

=cut

*/JSAN.use("DOM.Events");

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

;

(
function() {
    if (window.SkinSelectInProgress) return;
    window.SkinSelectInProgress = true;
    AllSkins.unshift('default - Reset to Default Skin');
    var data = {
        skins: AllSkins
    };
    var html = Jemplate.process('select.html', data);
    var box = Widget.Lightbox.show(html);

    var finish = function() {
        box.hide();
        window.SkinSelectInProgress = false;
        return false;
    };

    var submit = function() {
        var skin_name =
            jQuery('form#skin-select-form select[@name=skin-name]')[0].
                value;
        skin_name = skin_name.replace(/ .*/, '');
        if (skin_name == 'default')
            Cookie['delete']('socialtext-skin');
        else
            Cookie.set('socialtext-skin', skin_name);
        location.reload();
        return finish();
    };

    jQuery('form#skin-select-form select[@name=skin-name]').change(submit);
    jQuery('form#skin-select-form input[@name=select]').click(submit);

    jQuery('form#skin-select-form input[@name=cancel]').click(
        function() { return finish() }
    );
}
)();
