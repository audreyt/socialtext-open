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
