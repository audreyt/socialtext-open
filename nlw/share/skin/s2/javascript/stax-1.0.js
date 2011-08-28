;(function() {

var Stax = window.Stax = function() {};

if (window.Socialtext)
    Stax.version = Socialtext.version;

if (!Stax.loaded) Stax.loaded = {};

Stax.get_pro_base_uri = function() {
    var $script = jQuery('.stax-pro-hack');
    return $script.length
        ? $script.eq(0).attr('src').replace(/[\w\-]+\/stax\.js$/, '')
        : '';
}

Stax.pro_base_uri = Stax.get_pro_base_uri();

Stax.start = function(hack) {
    var starter = function() {
        var obj = eval('new ' + hack + '()');
        var hack_name = hack.replace(/([a-z])([A-Z])/g, '$1-$2').toLowerCase();
        obj.start(Stax.get_config_entry(hack_name));
    }
    jQuery(starter);
}

Stax.start_each = function(hack) {
    var starter = function() {
        var $insert = jQuery(
            '<span class="nlw_phrase"><div></div><!-- wiki: --></span>'
        )
        .prependTo(".wiki")
        .children(":eq(0)");
        var obj = eval('new ' + hack + '()');
        var hack_name = hack.replace(/([a-z])([A-Z])/g, '$1-$2').toLowerCase();
        obj.start(
            $insert,
            Stax.get_config_entry(hack_name).params
        );
    }
    jQuery(starter);
}

Stax.get_config_entry = function(hack) {
    var config;
    jQuery.each(Socialtext.stax.entries, function() {
        if (this.hack == hack) {
            config = this;
            return false;
        }
    });
    return config;
}

Stax.include_css = function(uri) {
    if (Stax.loaded[uri]) return;
    Stax.loaded[uri] = true;

    var link = '<link rel="stylesheet" type="text/css" href="' + uri +
        '" media="screen" />';

    jQuery(link).appendTo('head');
}


})();
