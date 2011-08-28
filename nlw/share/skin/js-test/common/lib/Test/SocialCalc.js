(function() {

proto = Test.Base.newSubclass('Test.SocialCalc', 'Test.Visual');

proto.open_iframe_with_socialcalc = function(url, callback) {
    var t = this;
    this.open_iframe(url, function() {
        t.wait_for_socialcalc(callback);
    });
}

proto.curCell = function(coord) {
    var t = this;
    coord = coord || 'A1';
    if (t.$('#st-spreadsheet-edit #e-cell_'+coord).is(':visible')) {
        return t.$('#st-spreadsheet-edit #e-cell_'+coord);
    }
    if (coord == 'A1') {
        return t.$('#st-spreadsheet-preview td:first');
    }
    else {
        // XXX - Breaks on IE / jQuery 1.4
        return t.$('#st-spreadsheet-preview #cell_'+coord);
    }
}

proto._doCheck = function(meth, key, value, msg, coord) {
    var t = this;
    return function() {
        var curValue = t.curCell(coord)[meth](key);
        if (value === true) {
            t.ok(curValue, msg);
        }
        else if (typeof curValue == 'string') {
            t.is(curValue.replace(/^[\xA0\s]+|[\xA0\s]+$/g, '').replace(/,\s+/g, ','), value, msg);
        }
        else {
            t.is(curValue, value, msg);
        }
        t.callNextStep();
    };
}

proto.doCheckCSS = function(key, value, msg, coord) {
    return this._doCheck('css', key, value, msg, coord);
}

proto.doCheckAttr = function(key, value, msg, coord) {
    return this._doCheck('attr', key, value, msg, coord);
}

proto.doCheckText = function(text, msg, coord) {
    var t = this;
    return function() {
        t.is(t.curCell(coord).text().replace(/^[\xA0\s]+|[\xA0\s]+$/g, ''), text, msg);
        t.callNextStep();
    };
}

proto.callNextStepOnReady = function() {
    var t = this;
    setTimeout(function(){
        t.poll(function(){
            return(!t.ss.editor.busy);
        }, function(){
            t.callNextStep();
        })
    }, 100);
};

proto.doClick = function(selector) {
    var t = this;
    return function() {
        t.click(selector);
        setTimeout(function() {
            t.callNextStepOnReady();
        }, 500);
    };
};

proto.doExec = function(cmd) {
    var t = this;
    return function() {
        t.ss.editor.EditorScheduleSheetCommands(cmd, true, true);
        t.callNextStepOnReady();
    };
};

proto.endAsync = function() {
    var t = this;
    if (! t.asyncId)
        throw("endAsync called out of order");

    var doEndAsync = function() {
        t.builder.endAsync(t.asyncId);
        t.asyncId = 0;
    }

    t.win.confirm = function() { return true };

    if ((typeof t.$ != 'undefined') && t.$('#st-save-button-link').is(':visible')) {
        t.click('#st-save-button-link');
        t.poll( function() {
            return t.$('#st-display-mode-container', t.win.document).is(':visible')
        }, doEndAsync);
    }
    else {
        doEndAsync();
    }
}

proto.richtextModeIsReady = function () { return true }

proto.wait_for_socialcalc = function(callback) {
    var t = this;
    this.$.poll(
        function() {
            return Boolean(
                t.iframe.contentWindow.SocialCalc &&
                t.iframe.contentWindow.SocialCalc.editor_setup_finished
            );
        },
        function() {
            t.ss = t.iframe.contentWindow.ss;
            t.SocialCalc = t.iframe.contentWindow.SocialCalc;

            callback.apply(t);
        },
        250, 15000
    );
}

})();
