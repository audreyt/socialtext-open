st.dialog.register('tag-queue', function(opts) {
    var dialog = st.dialog.createDialog({
        html: st.dialog.process('tag-queue.tt2', {}),
        title: loc('do.add-tags'),
        buttons: [
            {
                id: 'st-tagqueue-close',
                text: loc('do.close'),
                click: function() { dialog.close() }
            }
        ]
    });
    $('#st-tagqueue-addbutton').button();
    $('#st-tagqueue-field').lookahead({
        submitOnClick: true,
        url: "/data/workspaces/" + st.workspace.name + "/tags",
        linkText: function(i) {
            return [i.name, i.name];
        }
    });
    $('#st-tagqueue').submit(function() {
        var $input_field, skip, tag;
        $input_field = $('#st-tagqueue-field');
        tag = $input_field.val();
        if (tag === '') {
            return false;
        }
        $input_field.val('');
        skip = false;
        $('.st-tagqueue-taglist-name').each(function(index, element) {
            var text;
            text = $(element).text();
            text = text.replace(/^, /, '');
            if (tag === text) {
                skip = true;
                return false;
            }
        });
        if (!skip) {
            st.editor.addNewTag(tag);
        }
        return false;
    });
});
