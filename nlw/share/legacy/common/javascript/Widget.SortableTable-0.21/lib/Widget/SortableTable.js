JSAN.use("DOM.Ready");
JSAN.use("DOM.Events");

if ( typeof Widget == "undefined" ) Widget = {};

Widget.SortableTable = function (params) {
    this._initialize(params);
};

Widget.SortableTable.VERSION = "0.21";

Widget.SortableTable.prototype._initialize = function (params) {
    if ( ! params ) {
        throw new Error("Cannot create a new Widget.SortableTable without parameters");
    }

    if ( ! params.tableId ) {
        throw new Error("Widget.SortableTable requires a tableId parameter");
    }

    this._initialSortColumn = params.initialSortColumn;
    if ( ! this._initialSortColumn ) {
        this._initialSortColumn = 0;
    }
    this._col_specs = [];
    if ( params.columnSpecs ) {
        for ( var i = 0; i < params.columnSpecs.length; i++ ) {
            if ( params.columnSpecs[i] ) {
                this._col_specs[i] = params.columnSpecs[i];
            }
        }
    }

    this._noInitialSort = params.noInitialSort;

    this._onSortRowCallback = params.onSortRowCallback;

    if ( ! params.secondarySortColumn ) {
        this._secondarySortColumn = 0;
    }
    else {
        this._secondarySortColumn = params.secondarySortColumn;
    }

    var self = this;
    DOM.Ready.onIdReady( params.tableId,
                         function (elt) { self._instrumentTable(elt) }
                       );
};

Widget.SortableTable._seenId = {};

Widget.SortableTable.prototype._instrumentTable = function (table) {
    this._table = table;

    var head = table.rows[0];

    if ( ! head ) {
        return;
    }

    for ( var i = 0; i < head.cells.length; i++ ) {
        if ( this._col_specs[i] && this._col_specs[i].skip ) {
            continue;
        }

        if ( ! Widget.SortableTable._seenId[ table.id ] ) {
            this._makeColumnSortable( head.cells[i], i );
        }

        this._removeCSSClass( head.cells[i], "w-st-desc-column-header" );
        this._removeCSSClass( head.cells[i], "w-st-asc-column-header" );
        this._addCSSClass( head.cells[i], "w-st-unsorted-column-header" );
    }

    if ( this._noInitialSort ) {
        this._setRowCSS();
    }
    else {
        this.sortOnColumn( this._initialSortColumn );
    }

    Widget.SortableTable._seenId[ table.id ] = true;
};

Widget.SortableTable.prototype._makeColumnSortable = function (cell, idx) {
    var href = document.createElement("a");
    href.setAttribute( "href", "#" );
    href.setAttribute( "onClick", "return false;" );
    href.className = "w-st-resort-column";

    this._moveChildTree( cell, href );
    cell.appendChild(href);

    var self = this;
    DOM.Events.addListener( href,
                            "click",
                            function () { self.sortOnColumn(idx); return false; }
                          );
};

Widget.SortableTable.prototype._moveChildTree = function (from, to) {
    if ( document.implementation.hasFeature( "Range", "2.0" ) ) {
        var range = document.createRange();
        range.selectNodeContents(from);

        to.appendChild( range.extractContents() );
    }
    else {
        /* XXX - this is gross but seems to work */
        to.innerHTML = from.innerHTML;
        from.innerHTML = "";
    }
};

Widget.SortableTable.prototype.sortOnColumn = function (idx) {
    if (! this._table ) {
        return;
    }

    if ( this._table.rows.length == 1 ) {
        return;
    }

    var cell_data = [];
    var rows = [];
    /* start at 1 to ignore the header row when sorting */
    for ( var i = 1; i < this._table.rows.length; i++ ) {
        var text = this._getAllText( this._table.rows[i].cells[idx] );
        var cell_info = { "primaryText": text, "rowNumber": i - 1 };
        if ( idx != this._secondarySortColumn ) {
            cell_info.secondaryText =
                this._getAllText( this._table.rows[i].cells[ this._secondarySortColumn ] );
        }

        cell_data.push(cell_info);
        rows.push( this._table.rows[i] );
    }

    var sort_info = this._sortFor( idx, cell_data[0].primaryText );
    if ( idx != this._secondarySortColumn ) {
        var sec_sort_info = this._sortFor( this._secondarySortColumn, cell_data[0].secondaryText );
        sort_info.secondaryFunc = sec_sort_info.func;
    }

    cell_data.sort( Widget.SortableTable._makeCellDataSorter
                        ( sort_info.func, sort_info.secondaryFunc ) );

    if ( sort_info.dir == "desc" ) {
        cell_data.reverse();
    }

    this._resortTable( cell_data, rows );

    this._updateCSSClasses( idx, sort_info.dir );

    this._lastSort = { "index": idx,
                       "dir":   sort_info.dir };
}

/* More or less copied from
 * http://www.kryogenix.org/code/browser/sorttable/sorttable.js
 */
Widget.SortableTable.prototype._getAllText = function (elt) {
    if ( typeof elt == "string") {
        return elt;
    }
    if ( typeof elt == "undefined") {
        return "";
    }

    var text = "";
	
    var children = elt.childNodes;
    for ( var i = 0; i < children.length; i++ ) {
        switch ( children[i].nodeType) {
        case 1: /* ELEMENT_NODE */
            text += this._getAllText( children[i] );
            break;
        case 3:	/* TEXT_NODE */
            text += children[i].nodeValue;
            break;
        }
    }

    return text;
};

Widget.SortableTable.prototype._sortFor = function (idx, content) {
    var func;
    var type; if ( this._col_specs[idx] && this._col_specs[idx].sort ) {
        if ( typeof this._col_specs[idx].sort == "function" ) {
            func = this._col_specs[idx].sort;
        }
        else {
            var sort_name = this._col_specs[idx].sort;
            type = sort_name;
            func = Widget.SortableTable._sortFunctionsByType[sort_name];
        }
    }

    if ( ! func ) {
        if ( content.match( /^\s*[\$\u20AC]\s*\d+(?:\.\d+)?\s*$/ ) ) {
            type = "currency";
            func = Widget.SortableTable._sortFunctionsByType.currency;
        }
        else if ( content.match( /^\s*\d+(?:\.\d+)?\s*$/ ) ) {
            type = "number";
            func = Widget.SortableTable._sortFunctionsByType.number;
        }
        else if ( content.match( /^\s*\d\d\d\d[^\d]+\d\d[^\d]+\d\d\s*$/ ) ) {
            type = "date";
            func = Widget.SortableTable._sortFunctionsByType.date;
        }
        else {
            type = "text";
            func = Widget.SortableTable._sortFunctionsByType.text;
        }
    }

    var dir;
    if ( this._col_specs[idx] && this._col_specs[idx].defaultDir ) {
        dir = this._col_specs[idx].defaultDir;
    }
    else if (type)  {
        dir = Widget.SortableTable._defaultDirByType[type];
    }
    else {
        dir = "asc";
    }

    if ( this._lastSort
         && this._lastSort.index == idx
         && this._lastSort.dir   == dir ) {
        dir = dir == "asc" ? "desc" : "asc";
    }

    return { "func": func,
             "dir":  dir };
};

Widget.SortableTable._sortCurrency = function (a, b) {
    var a_num = parseFloat( a.replace( /[^\d\.]/g, "" ) )
    var b_num = parseFloat( b.replace( /[^\d\.]/g, "" ) )

    return Widget.SortableTable._sortNumberOrNaN(a_num, b_num);
};

Widget.SortableTable._sortNumber = function (a, b) {
    var a_num = parseFloat(a);
    var b_num = parseFloat(b);

    return Widget.SortableTable._sortNumberOrNaN(a_num, b_num);
};

Widget.SortableTable._sortNumberOrNaN = function (a, b) {
    if ( isNaN(a) && isNaN(b) ) {
        return 0;
    }
    else if ( isNaN(a) ) {
        return -1;
    }
    else if ( isNaN(b) ) {
        return 1;
    }
    else if ( a < b ) {
        return -1;
    }
    else if ( a > b ) {
        return 1;
    }
    else {
        return 0;
    }
};

Widget.SortableTable._sortDate = function (a, b) {
    var a_match = a.match( /(\d\d\d\d)[^\d]+(\d\d)[^\d]+(\d\d)/ );
    var b_match = b.match( /(\d\d\d\d)[^\d]+(\d\d)[^\d]+(\d\d)/ );

    if ( ! a_match ) {
        a_match = [ "", -9999, 1, 1 ];
    }

    if ( ! b_match ) {
        b_match = [ "", -9999, 1, 1 ];
    }

    var a_date = new Date( a_match[1], a_match[2], a_match[3] );
    var b_date = new Date( b_match[1], b_match[2], b_match[3] );

    if ( a_date < b_date ) {
        return -1;
    }
    else if ( a_date > b_date ) {
        return 1;
    }
    else {
        return 0;
    }
};

Widget.SortableTable._sortText = function (a, b) {
    var a_text = a.toLowerCase();
    var b_text = b.toLowerCase();

    if ( a_text < b_text ) {
        return -1;
    }
    else if ( a_text > b_text ) {
        return 1;
    }
    else {
        return 0;
    }
};

Widget.SortableTable._sortFunctionsByType = {
    "currency": Widget.SortableTable._sortCurrency,
    "number":   Widget.SortableTable._sortNumber,
    "date":     Widget.SortableTable._sortDate,
    "text":     Widget.SortableTable._sortText
};

Widget.SortableTable._defaultDirByType = {
    "currency": "asc",
    "number":   "asc",
    "date":     "desc",
    "text":     "asc"
};

Widget.SortableTable._makeCellDataSorter = function ( real_func, secondary_func ) {
    return function(a, b) {
        var sort = real_func( a.primaryText, b.primaryText );
        if ( sort == 0 && secondary_func ) {
            return secondary_func( a.secondaryText, b.secondaryText );
        }
        return sort;
    };
};

Widget.SortableTable.prototype._resortTable = function (cell_data, rows) {
    for ( var i = 0; i < cell_data.length; i++ ) {
        var row = rows[ cell_data[i].rowNumber ];
        if ( i % 2 ) {
            this._removeCSSClass( row, "w-st-even-row" );
            this._addCSSClass( row, "w-st-odd-row" );
        }
        else {
            this._removeCSSClass( row, "w-st-odd-row" );
            this._addCSSClass( row, "w-st-even-row" );
        }

        if ( this._onSortRowCallback ) {
            this._onSortRowCallback( row, i + 1 );
        }

        this._table.tBodies[0].appendChild(row);
    }
};

Widget.SortableTable.prototype._setRowCSS = function () {
    for ( var i = 0; i < this._table.rows.length; i++ ) {
        if ( i % 2 ) {
            this._addCSSClass( this._table.rows[i], "w-st-even-row" );
            this._removeCSSClass( this._table.rows[i], "w-st-odd-row" );
        }
        else {
            this._addCSSClass( this._table.rows[i], "w-st-odd-row" );
            this._removeCSSClass( this._table.rows[i], "w-st-even-row" );
        }
    }
};

Widget.SortableTable.prototype._updateCSSClasses = function (idx, dir) {
    if ( ( ! this._lastSort )
         ||
         ( this._lastSort && this._lastSort.index != idx ) ) {

        for ( var i = 0; i < this._table.rows.length; i++ ) {
            this._addCSSClass( this._table.rows[i].cells[idx], "w-st-current-sorted-column" );
            if ( this._lastSort ) {
                old_idx = this._lastSort.index;
                this._removeCSSClass( this._table.rows[i].cells[old_idx], "w-st-current-sorted-column" );
            }
        }
    }

    if ( this._lastSort ) {
        var old_header_cell = this._table.rows[0].cells[ this._lastSort.index ];
        this._removeCSSClass(
            old_header_cell,
            this._lastSort.dir == "asc" ? "w-st-asc-column-header" : "w-st-desc-column-header" );
        this._addCSSClass( old_header_cell, "w-st-unsorted-column-header" );
    }

    var header_cell = this._table.rows[0].cells[idx];
    if ( this._lastSort && this._lastSort.index == idx ) {
        var old_dir = this._lastSort.dir;
        this._removeCSSClass( header_cell,
                              "w-st-" + old_dir + "-column-header" );
    }
    else {
        this._removeCSSClass( header_cell, "w-st-unsorted-column-header" );
    }
    this._addCSSClass( header_cell, "w-st-" + dir + "-column-header" );
};

Widget.SortableTable.prototype._addCSSClass = function (elt, add_class) {
    var class_regex = new RegExp(add_class);
    if ( ! elt.className.match(class_regex) ) {
        elt.className = elt.className + (elt.className.length ? " " : "" ) + add_class;
    }
};

Widget.SortableTable.prototype._removeCSSClass = function (elt, remove_class) {
    var class_regex = new RegExp( "\\s*" + remove_class );
    elt.className = elt.className.replace( class_regex, "" );
}


/*

*/
