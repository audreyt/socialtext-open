(function($) {
var ST = window.ST || {};

ST.SelfJoinWorkspace = function() {}
var proto = ST.SelfJoinWorkspace.prototype = new ST.Lightbox;

proto.divID     = '#st-self-join-workspaceinterface';
proto.contentID = '#st-self-join-workspaceinterface .content';
proto.errorID   = '#st-self-join-workspaceinterface .error';
proto.closeID   = '#st-self-join-workspace-closebutton'

proto.show = function(groups) {
    var self = this;

    if (!$(self.divID).size()) {
        self.process('self_join_workspace.tt2');
    }

    var $html;
    if (groups.length == 1) {
        $html = Jemplate.process(
            'self_join_single.tt2', { group: groups[0], loc: loc });
    }
    else {
        $html = Jemplate.process(
            'self_join_many.tt2', { groups: groups, loc: loc });
    }
    $(self.contentID).html($html);

    self.showButtons();
    $(self.errorID).hide();
    self.addHandlers();

    $.showLightbox({
        content: self.divID,
        close: self.closeID
    });
};

proto.showButtons = function() {
    $(this.divID + '.loading').hide();
    $(this.divID + '.widgetButton').show();
};

proto.loading = function() {
    $(this.divID + '.widgetButton').hide();
    $(this.divID + '.loading').show();
};

proto.addHandlers = function() {
    var self = this;

    $('#st-self-join-workspace-action a').unbind('click').click(function() {
        var selected = $(self.divID + ' input:checked');

        if (selected.length == 0) {
            $(self.errorID)
               .text(loc('error.choose-group')).show();
            return false;
        }
        //self.loading();

        var user   = new Socialtext.User({user_id: Socialtext.real_user_id});
        var groups = [];
        $(selected).each(function() {
            groups.push({ id: $(this).attr('value') });
        });

        user.addToGroups(groups, function() {
            $.hideLightbox();
            window.location.reload();
        });
        return false;
    });
};

})(jQuery);

window.SelfJoinWorkspace = window.SelfJoinWorkspace || new ST.SelfJoinWorkspace;
