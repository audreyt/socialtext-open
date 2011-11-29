(function ($) {

socialtext.dialog.register('groups-create', function(opts) {
    var dialog = socialtext.dialog.createDialog({
        html: Jemplate.process('groups-create.tt2', {
            permission_set: opts ? opts.permission_set : '',
            loc: loc
        }),
        title: opts && opts.permission_set
            ? loc('groups.change-type')
            : loc('groups.create'),
        buttons: [
            {
                text: loc('groups.next-step'),
                id: 'st-create-group-next',
                click: function() {
                    var type = dialog.find('input[name=new-group-type]:checked').val(); 
                    if (opts && $.isFunction(opts.onChange)) {
                        opts.onChange(type);
                        dialog.close();
                    }
                    else {
                        document.location='/st/create_group?type=' + type;
                    }
                }
            },
            {
                text: loc('do.cancel'),
                id: 'st-create-group-cancel',
                click: function() { dialog.close() }
            }
        ]
    });

    dialog.find('.lookahead input').blur().lookahead({
        clearOnHide: true,
        requireMatch: true,
        filterType: 'solr',
        url: '/data/groups',
        showAll: function(term) {
            window.location = "/?action=search_groups&search_term=" + encodeURIComponent(term) + ' OR ' + encodeURIComponent(term) + '*';
        },
        params: {
            discoverable: 'include'
        },
        getEntryThumbnail: function(group) {
            return '/data/groups/' + group.value + '/small_photo';
        },
        linkText: function (group) {
            return [group.name, group.group_id, group.description];
        },
        onAccept: function(id, item) {
            window.open('/st/group/' + id);
        },
        displayAs: function(item) {
            return item.title;
        },
        onFirstType: function(element) {
            self.doneFirstType = true;
        }
    });

    return false;
});

})(jQuery);
