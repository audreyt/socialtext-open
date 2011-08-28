/*
Browser.js: Browser Detection Class

usage:

    if (Browser.isMozilla) ...

*/

// XXX - Using an array of one function as the class closure
// syntax seems to not mess up vim syntax hiliting.
// Trying leading semicolons to make it stand out.
;;; [function () {      // Begin the Class.Browser closure

// XXX Still deciding whether to have Browser depend on Subclass
// var proto = new Subclass('Browser');
Browser = function() {}
var proto = Browser.prototype;

proto.new_instance = Browser;
proto.isOpera = navigator.userAgent.indexOf("Opera ") > 0;
proto.isSafari = navigator.userAgent.indexOf("Safari") > 0;

proto.isMozilla = (
    navigator.product == "Gecko" &&
    !Browser.prototype.isSafari
);

proto.isIE = !(
    Browser.prototype.isOpera || 
    Browser.prototype.isSafari || 
    Browser.prototype.isMozilla
);

proto.has_broken_textarea = (
    Browser.prototype.isSafari
);

proto.runs_gui_toolbar = (
    Browser.prototype.isMozilla || Browser.prototype.isIE
);

Browser = new Browser();   // Singleton
}][0]();  // End the Class.Browser closure

