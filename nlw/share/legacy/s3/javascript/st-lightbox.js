var ST = ST || {};

(function ($) {

ST.Lightbox = function () {};

ST.Lightbox.prototype = {
    newUrl: function (page) {
        var ws = $(this.sel + ' #st-copy-workspace option:selected')
            .attr('name') || Socialtext.wiki_id;
        return '/' + ws + '/' + nlw_name_to_id(page);
    },

    process: function (template) {
        Socialtext.loc = loc;
        $('body').append(
            Jemplate.process(template, Socialtext)
        );
    },

    show: function (do_redirect, callback) {
        var self = this;
        $.showLightbox({
            content: this.sel,
            close: this.sel + ' .close',
            callback: callback 
        });

        $(self.sel + ' .submit').click(function () {
                $(this).parents('form').submit();
        });

        // Clear errors from the previous time around: {bz: 1039}
        $(self.sel + ' .error').html('');

        $(self.sel + ' form').submit(function () {
            $(self.sel + ' a[class~=submit]').parent().addClass('disabled').addClass('loading');

            var formdata = $(this).serializeArray();
            var new_title = this.new_title.value;

            $.ajax({
                url: Page.cgiUrl(),
                data: formdata,
                type: 'post',
                dataType: 'json',
                async: false,
                success: function (data) {
                    $(self.sel + ' a[class~=submit]').parent().removeClass('disabled').removeClass('loading');

                    var error = self.errorString(data, new_title);
                    if (error) {
                        $('<input name="clobber" type="hidden">')
                            .attr('value', new_title)
                            .appendTo(self.sel + ' form');
                        $(self.sel + ' .error').html(error).show();
                    }
                    else {
                        $.hideLightbox();

                        if (do_redirect) {
                            document.location = self.newUrl(new_title);
                        }
                    }
                },
                error: function (xhr, textStatus, errorThrown) {
                    $(self.sel + ' .error').html(textStatus).show();
                    $(self.sel + ' a[class~=submit]').parent().removeClass('disabled').removeClass('loading');
                }
            });

            return false;
        });
    },

    errorString: function (data, new_title, workspace) {
        if (data.page_exists) {
            var button = $(this.sel + ' a[class~=submit]').text();
            return loc(
                'error.page-exists=title,button', new_title, button
            );
        }
        else if (data.page_title_bad) {
            return loc(
                'error.invalid-page-name=title', new_title
            );
        }
        else if (data.page_title_too_long) {
            return loc(
                'error.long-page-name=title', new_title
            );
        }
        else if (data.same_title) {
            return loc(
                'error.same-page-name=title', new_title
            );
        }
    }
};
})(jQuery);
