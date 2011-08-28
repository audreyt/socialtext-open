(function ($) {

var ST = window.ST = window.ST || {};

ST.Copy = function () { }
ST.Copy.prototype = new ST.Lightbox;

ST.Copy.prototype.copyLightbox = function () {
    var self = this;
    this.process('copy.tt2');
    this.sel = '#st-copy-lightbox';
    $.ajax({
        url: '/data/workspaces',
        type: 'get',
        cache: false,
        async: false,
        dataType: 'json',
        success: function (list) {
            $('#st-copy-workspace option').remove();
            $.each(list, function () {
                $('<option />')
                    .val(this.id)
                    .html(this.title)
                    .attr('name', this.name)
                    .appendTo('#st-copy-workspace');
            })

            self.show(
                false, // No redirection
                function() {
                    $("#st-copy-workspace").select().focus();
                }
            );
        }
    });
}

})(jQuery);
