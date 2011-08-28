/*
 * ST.TemplateField class
 *
 * This class wraps two DOM nodes. One node is a display node -- its content
 * is updated by the class. The other node contains the template (Trimpath)
 * used to generate the content for the display node.
 */
ST.TemplateField = function (template, target) {
    this._template_tag = template;
    this._update_tag = target;
    this._template_jst = this._JST(template);
};


ST.TemplateField.prototype = {
    _template_tag: '',
    _update_tag: '',
    _template_jst: '',

    clear: function () {
        Element.update(this._update_tag, '');
    },

    hide: function () {
        $(this._update_tag).style.display = 'none';
    },

    html: function (data) {
        return this._template_jst.process(data);
    },

    set_text: function (html) {
        Element.update(this._update_tag, html);
    },

    show: function () {
        $(this._update_tag).style.display = 'block';
    },

    update: function (data) {
        Element.update(this._update_tag, this.html(data));
    },

    _JST: function (elem) {
        return TrimPath.parseDOMTemplate(elem);
    }
};
