function loc() {
    if (typeof LocalizedStrings == 'undefined')
        LocalizedStrings = {};

    var locale = Socialtext.loc_lang;
    var dict = LocalizedStrings[locale] || LocalizedStrings['en'] || {};
    var str = arguments[0] || "";
    var l10n = dict[str];
    var nstr = "";

    if (locale == 'xx') {
        l10n = str.replace(/[A-Z]/g, 'X').replace(/[a-z]/g, 'x');
    }
    else if (locale == 'xq') {
        l10n = "«" + str + "»";
    }
    else if (locale == 'xr') {
        l10n = str.replace(/a/g, '4')
                  .replace(/e/g, '3')
                  .replace(/o/g, '0')
                  .replace(/t/g, '7')
                  .replace(/b/g, '8')
                  .replace(/qu4n7/g, 'quant')
                  .replace(/<4 hr3f/g, '<a href');
    }

    if (!l10n) {
        /* If the hash-lookup failed, convert " into \\\" and try again. */
        nstr = str.replace(/\"/g, "\\\"");
        l10n = dict[nstr];
        if (!l10n) {
            /* If the hash-lookup failed, convert [_1] into %1 and try again. */
            nstr = nstr.replace(/\[_(\d+)\]/g, "%$1");
            l10n = dict[nstr] || str;
        }
    }

    l10n = l10n.replace(/\\\"/g, "\"");

    /* Convert both %1 and [_1] style vars into the given arguments */
    for (var i = 1; i < arguments.length; i++) {
        var rx = new RegExp("\\[_" + i + "\\]", "g");
        var rx2 = new RegExp("%" + i + "", "g");
        l10n = l10n.replace(rx, arguments[i]);
        l10n = l10n.replace(rx2, arguments[i]);

        var quant = new RegExp("\\[(?:quant|\\*),_" + i + ",([^\\],]+)(?:,([^\\],]+))?(?:,([^\\]]+))?\\]");
        while (quant.exec(l10n)) {
            var num = arguments[i] || 0;
            if (num == 0 && RegExp.$3) { // Empty condition exists
                l10n = l10n.replace(quant, RegExp.$3);
            }
            else if (num == 1) {
                l10n = l10n.replace(quant, num + ' ' + RegExp.$1);
            }
            else {
                l10n = l10n.replace(quant, num + ' ' + (RegExp.$2 || (RegExp.$1 + 's')));
            }
        }
    }

    return l10n;
};

loc.all_widgets = function(){
    $(function(){
        $('span[data-loc_text]').each(function(){
            var $span = $(this);
            $span.text(loc($span.data('loc_text')));
        });
        $('input[data-loc_val]').each(function(){
            var $input = $(this);
            $input.val(loc($input.data('loc_val')));
        });
    });
};
