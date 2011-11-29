Socialtext.prototype.setupListview = (function($){
    return function(query_start) {
        $('#sort-picker')
            .dropdown()
            .live('change', function() {
                var selected = jQuery('select#sort-picker').val();
                window.location = query_start + ';' + selected;
            });

        $('#st-listtools-export')
            .dropdown()
            .change(function() {
                var $checked = $('.st-listview-selectpage-checkbox:checked');

                switch($(this).val()) {
                    case 'export':
                        return;
                    case 'pdf':
                        if (!$checked.size()) {
                            alert(loc("error.no-page-pdf"));
                        }
                        else {
                            $('#st-listview-action').val('pdf_export')
                            $('#st-listview-filename')
                                .val(st.workspace.name + '.pdf');
                            $('#st-listview-form').submit();
                        }
                        break;
                    case 'rtf':
                        if (!$checked.size()) {
                            alert(loc("error.no-page-doc"));
                        }
                        else {
                            $('#st-listview-action').val('rtf_export')
                            $('#st-listview-filename')
                                .val(st.workspace.name + '.rtf');
                            $('#st-listview-form').submit();
                        }
                        break;
                }
                $(this).dropdownSelectValue('export');
            });

        $('#st-listview-selectall').live('click', function () {
            var self = this;
            $('input[type=checkbox]').each(function() {
                if ( ! $(this).attr('disabled') ) {
                    $(this).attr('checked', self.checked);
                }
            });
            return true;
        });

        $('td.listview-watchlist a[id^=st-watchlist-indicator-]').each(function(){
            $(this).click(
                st.makeWatchHandler(
                    $(this).attr('id').replace(/^st-watchlist-indicator-/, '')
                )
            );
        });

    };
})(jQuery);
