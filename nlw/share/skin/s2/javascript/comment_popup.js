/* 
COPYRIGHT NOTICE:
    Copyright (c) 2004-2005 Socialtext Corporation 
    235 Churchill Ave 
    Palo Alto, CA 94301 U.S.A.
    All rights reserved.
*/

var ge
function init_guiedit() {
    // XXX Get past an error caused by combining js files into one.
    try {
        ge = new GuiEdit()
        ge.init('st-commentui-textarea','','edname',nlw_make_s2_path('/images/'))
    }
    catch(e) {
        // Ignore this error that doesn't seem to happen in Safari
        // which is the only place we use GuiEdit
        // alert('error: ' + e);
    }
}

function comment_popup(page_name, action, height) {
    var display_width = elem('page-center-control-content').offsetWidth 
    var comment_window = window.open('index.cgi?action=enter_comment;page_name=' + page_name + ';caller_action=' + action, '_blank', 'toolbar=no, location=no, directories=no, status=no, menubar=no, titlebar=no, scrollbars=yes, resizable=yes, width=' + display_width + ', height=' + height + ', left=' + 50 + ', top=' + 200)
}

function comment_popup_setup() {
    init_guiedit()
    window.focus()
    var textarea = elem('st-commentui-textarea')
    comment_focus_textarea(textarea)
}

function comment_focus_textarea(textarea) {
    textarea.focus()
}

function submit_comment(comment_window) {
    var my_array = document.getElementsByTagName('input')
    var textarea = elem('st-commentui-textarea')
    toolbar_warning(elem('st-commentui-controls'), loc('Saving...'))
    if (my_array.length > 3) {
         textarea.value = '\n\n' + loc('Comment:') + ' ' + textarea.value 
    }
    for (var i = my_array.length; i >= 0; i--) { 
        if ( (my_array[i]) &&
                (my_array[i].name != 'action') &&
                (my_array[i].name != 'page_name') &&
                (my_array[i].name != 'caller_action') ) {
            textarea.value = my_array[i].name + ": " + 
                my_array[i].value + '\n' + 
                textarea.value
        }
    }                                                                                
    document.forms['comment_form'].submit()
}

function cancel_comment() {
    if ((elem('st-commentui-textarea').value == '') ||
        confirm(loc("If you click 'OK', all comment changes will be lost!"))
       ) window.close()
}

