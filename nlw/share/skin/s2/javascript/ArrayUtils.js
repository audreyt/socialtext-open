/*
  Extensions to the JavaScript Array object.
  Author: Sean M. Burke
  Codeblt'd from: http://interglacial.com/hoj/hoj.html

  map, grep, and foreach are added to the Array object

  Examples:

    Get a copy of words with every item uppercase:
        var loudwords = words.map( function(_){ return _.toUpperCase(); } );

    Find all the uppercased words in words:
        function isUpperCase (_) { return _ == _.toUpperCase(); }
        var already_loud = words.grep( isUpperCase);

    Change words in-place:
        words.foreach( function(item, arr, i){arr[i] = item.toUpperCase();} );
*/

Array.prototype.map = function(f) {
    if(!f.apply) {
        var propname = f;
        f = function(_) {
            return _[propname]
        }
    }

    var out = [];
    for(var i = 0; i < this.length; i++) {
        out.push( f( this[i], this, i) );
    }

    return out;
};

Array.prototype.mapc = function(f) {
    if (!f.apply) {
        var propname = f;
        f = function(_) {
            return _[propname]
        }
    }

    var out = [];
    var gotten;
    for (var i = 0; i < this.length; i++) {
        gotten = f( this[i], this, i);
        if ( gotten != undefined )
            out = out.concat( gotten );
    }
    return out;
};


Array.prototype.grep = function(f) {
    if (!f.apply) {
        var propname = f;
        f = function(_) {
            return _[propname]
        }
    }
    var out = [];
    for(var i = 0; i < this.length; i++) {
        if ( f( this[i], this, i) )
            out.push(this[i]);
    }
    return out;
};

Array.prototype.foreach = function(f) {
    if(!f.apply) {
        var propname = f;
        f = function(_,x,i) { x[i] = _[propname] }
    }

    for(var i = 0; i < this.length; i++) {
        f( this[i], this, i );
    }

    return;
};

Array.prototype.deleteElement = function(toDelete) {
    var i;
    for (i=0; i < this.length; i++)
        if (this[i] == toDelete) {
            this.splice(i,1);
            return;
        }
}

Array.prototype.deleteElementIgnoreCase = function(toDelete) {
    var i;
    var lcToDelete = toDelete.toLowerCase();
    for (i=0; i < this.length; i++)
        if (this[i].toLowerCase() == lcToDelete) {
            this.splice(i,1);
            return;
        }
}