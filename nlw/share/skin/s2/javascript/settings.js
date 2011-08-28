if (typeof ST == 'undefined') {
    ST = {};
}

ST.uploadSkin = function(evt) {
   var filenameField = $("st-workspaceskin-file");
    if (! filenameField.value) {
        alert("Please click browse and select a file to upload.");
        Event.stop(evt);
        return false;
    }

    return true;
}

ST.hookCssUpload = function() {
    var node = $('st-workspaceskin-uploadform');
    if (node)
        Event.observe(node, 'submit', ST.uploadSkin);
}
