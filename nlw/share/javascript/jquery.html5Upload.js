(function($) {

/* HTML5 file upload */
if ($.browser.webkit && window.XMLHttpRequest && typeof(XMLHttpRequest.prototype) != 'undefined' && !XMLHttpRequest.prototype.sendAsBinary) {
    // For chrome
    XMLHttpRequest.prototype.sendAsBinary = function(datastr) {
        function byteValue(x) {
            return x.charCodeAt(0) & 0xff;
        }
        var ords = Array.prototype.map.call(datastr, byteValue);
        var ui8a = new Uint8Array(ords);
        this.send(ui8a.buffer);
    }
}

$.fn.createUploadDropArea = function(opts) {
    var $dropbox = $(this);

    if (!opts.url) throw new Error('url required');
    
    // Early out on non-wiki-pages or an unsupported browser
    if (!$dropbox.size() || !window.FileReader) return;

    var over_document = false;
    var over_dropbox = false;

    document.addEventListener("dragleave", function (evt) {
        over_document = false;
        setTimeout(function() {
            if (!over_document && !over_dropbox) $dropbox.hide();
        }, 500);
    }, false);
    document.addEventListener("dragover", function (evt) {
        evt.stopPropagation();
        evt.preventDefault();
        over_document = true;
        $dropbox.show();
    }, false);
    document.addEventListener("drop", function (evt) {
        evt.stopPropagation();
        evt.preventDefault();
        $dropbox.hide();
    }, false);

    $dropbox.get(0).addEventListener("dragover", function (evt) {
        evt.stopPropagation();
        evt.preventDefault();
        over_dropbox = true
        $dropbox.show().addClass('over');
    }, false);
    $dropbox.get(0).addEventListener("dragleave", function (evt) {
        evt.stopPropagation();
        evt.preventDefault();
        over_dropbox = false;
        setTimeout(function() {
            if (!over_dropbox) $dropbox.removeClass('over');
        }, 500);
    }, false);

    $dropbox.get(0).addEventListener('drop', function(evt) {
        evt.stopPropagation();
        evt.preventDefault();

        // Hide the dropbox
        $dropbox.hide().removeClass('over');

        // Turn this FileList into an Array
        var uploads = $.map(evt.dataTransfer.files, function(f) { return f });

        $.getJSON(opts.url, function(files) {
            // Determine dups and non-dups
            var dups = [];
            for (var i = uploads.length - 1; i >= 0; i--) {
                $.each(files, function(_, file) {
                    if (file.name == uploads[i].name) {
                        dups = dups.concat(uploads.splice(i, 1));
                        return false;
                    }
                })
            };

            // Non duplicates:
            if (uploads.length) {
                $.each(uploads, function(_, file) {
                    $dropbox.uploadDroppedFile(file, opts.url);
                });
            }

            // Duplicates:
            if (dups.length) {
                st.dialog.show('attachments-duplicate', {
                    files: dups,
                    callback: function(file, r) {
                        $dropbox.uploadDroppedFile(file, opts.url, r);
                    }
                });
            }
        });
    }, false);
};

$.fn.uploadDroppedFile = function(file, url, replace) {
    var $progress = $('<div class="dropbox-progress"></div>');
    $progress.insertAfter(this);
    $progress.progressbar({ value: 0 });

    var reader = new FileReader();  // reader
    var xhr = new XMLHttpRequest(); // writer

    xhr.upload.addEventListener("progress", function(e) {
        var percentage = 0;
        if (e.lengthComputable) {
            percentage = Math.round((e.loaded / e.total) * 100);
        }
        $progress.progressbar({ value: percentage });
    }, false);

    url += '?' + $.param({
        name: file.name,
        replace: replace || 0
    });

    xhr.open('POST', url, true);

    // Transfer files using the application/octet-stream MIME type since
    // the server seems to be much better at determining the actual
    // MIME type than the browser is, or at least than Chrome on Windows
    xhr.setRequestHeader("Content-Type", 'application/octet-stream');

    reader.onload = function(evt) {
        xhr.sendAsBinary(evt.target.result);
    };
    xhr.onreadystatechange = function() {
        if (xhr.readyState == 4) {
            $progress.remove()
            st.attachments.refreshAttachments();
        }
    };
    reader.onloadend = function(evt) {
        $progress.progressbar({ value: 100 });
    };
    reader.readAsBinaryString(file);
};

})(jQuery);
