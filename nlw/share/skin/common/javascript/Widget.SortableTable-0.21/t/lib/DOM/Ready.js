if ( typeof DOM == "undefined" ) DOM = {};

DOM.Ready = {};

DOM.Ready.VERSION = '0.12';

DOM.Ready.finalTimeout = 15;
DOM.Ready.timerInterval = 50;
DOM.Ready._timePassed = 0;

DOM.Ready._isReady = 0;

DOM.Ready._onDOMReadyCallbacks = [];

DOM.Ready._onIdReadyCallbacks = {};

DOM.Ready._checkDOM = function () {
    if ( DOM.Ready._isReady ) return DOM.Ready._isReady;

    if (    typeof document.getElementsByTagName != 'undefined'
         && typeof document.getElementById != 'undefined' 
         && ( document.getElementsByTagName('body')[0] != null
              || document.body != null ) ) {

        DOM.Ready._isReady = 1;
    }

    return DOM.Ready._isReady;

};

DOM.Ready.onDOMReady = function (callback) {
    if ( DOM.Ready._checkDOM() ) {
        callback();
    }
    else {
        DOM.Ready._onDOMReadyCallbacks.push(callback);
    }
}

DOM.Ready.onIdReady = function ( id, callback ) {
    if ( DOM.Ready._checkDOM() ) {
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

DOM.Ready._runDOMCallbacks = function () {
    for ( var i = 0; i < DOM.Ready._onDOMReadyCallbacks.length; i++ ) {
        DOM.Ready._onDOMReadyCallbacks[i]();
    }

    DOM.Ready._onDOMReadyCallbacks = [];
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

    if ( ! DOM.Ready._checkDOM() ) return;

    DOM.Ready._runDOMCallbacks();

    DOM.Ready._runIdCallbacks();

    DOM.Ready._timePassed += DOM.Ready._lastTimerInterval;

    if ( ( DOM.Ready._timePassed / 1000 ) >= DOM.Ready.finalTimeout ) {
        DOM.Ready._clearTimer();
    }

    DOM.Ready._inRunReadyCallbacks = 0;
}

DOM.Ready._setTimer = function () {
    DOM.Ready._lastTimerInterval = DOM.Ready.timerInterval;
    DOM.Ready._intervalId = setInterval( DOM.Ready._runReadyCallbacks, DOM.Ready.timerInterval );
};

DOM.Ready._clearTimer = function () {
    clearInterval( DOM.Ready._intervalId );
    DOM.Ready._intervalId = null;
}

DOM.Ready._setTimer();

DOM.Ready.runCallbacks = function () { DOM.Ready._runReadyCallbacks() };
