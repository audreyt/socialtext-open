var email_page_source;
var email_page_dest;
var email_page_add;
var email_page_submit_buttons;
window.onload = email_page_info;
function email_page_info() {
    form_email_page = document.forms.email_page_form;
    if (!form_email_page) return;
    email_page_source = form_email_page.elements['email_page_user_source'];
    email_page_dest = form_email_page.elements['email_page_user_choices'];
    email_page_add = form_email_page.elements['email_page_add_one'];
    email_page_submit_buttons = document.getElementById('st-popup-emailpage-buttons')
    email_page_error_div = $('st-popup-emailpage-errormessage');
    Element.hide(email_page_error_div);
}

function email_page_clear_element(element, compare) {
    if (element.value == compare) {
        // unfortunately this causes an XUL error in firefox
        // as attepts to update auto-fill dropdown info
        element.value = ''
    }
    return false
}


// Regular expression for validating email addresses. Not perfect,
// but close enough to eliminate the majority of invalid addresses,
// which erring on the side of caution. Adapted from here:
//
// http://fightingforalostcause.net/misc/2006/compare-email-regex.php
//
var EMAIL_ADDRESS_REGEX = new RegExp(
    "^"
    + "([a-zA-Z0-9_'+*$%\\^&!\\.\\-])+"
    + "@"
    + "(([a-zA-Z0-9\\-])+\\.)+"
    + "([a-zA-Z0-9:]{2,4})+"
    + "$"
    , "i"
);

function email_page_check_address(email_address) {
    return EMAIL_ADDRESS_REGEX.test(email_address);
}





function email_page_error_message(message) {
    email_page_error_div.innerHTML = message;
    Element.show(email_page_error_div);
}

// move the text input email address to the selected list
function email_page_validate_add() {
    var address = email_page_add.value
    if (address == '')
        return false
    if (!email_page_check_address(address)) {
        email_page_error_message(loc('error -> "[_1]" is not a valid email address', address))
        return false
    }
    email_page_dest[email_page_dest.length] = new Option(address)
    email_page_add.value = ''
    email_page_error_message('&nbsp;')
}
    
// move all the options to chosen
function email_page_all() {
    for (i = 0; i < email_page_source.length; i++)
        email_page_source.options[i].selected = 1
    email_page_move()
}

// remove all the chosen
function email_page_none() {
    for (i = 0; i < email_page_dest.length; i++)
        email_page_dest.options[i].selected = 1
    email_page_remove()
}

// move whatever is selected in choices to chosen
function email_page_move() {
    var new_dest = new Array()
    var new_from = new Array()
    for (i = 0; i < email_page_source.length; i++) {
        if (email_page_source.options[i].value == -1) continue
        if (email_page_source.options[i].selected) {
            new_dest.push(email_page_source.options[i].text)
        } else
            new_from.push(email_page_source.options[i].text)
    }
    for (i = 0; i < email_page_dest.length; i++)
        new_dest.push(email_page_dest.options[i].text)
    email_page_reset(new_from, new_dest)
}

// remove whatever is selected in chosen and return to choices
function email_page_remove() {
    var new_dest = new Array()
    var new_from = new Array()
    for (i = 0; i < email_page_dest.length; i++) {
        if (email_page_dest.options[i].value == -1) continue
        if (email_page_dest.options[i].selected)
            new_from.push(email_page_dest.options[i].text)
        else
            new_dest.push(email_page_dest.options[i].text)
    }
    for (i = 0; i < email_page_source.length; i++)
        new_from.push(email_page_source.options[i].text)
    email_page_reset(new_from, new_dest)
}

// reset the values of the two select boxes
function email_page_reset(source, destination) {
    source.sort()
    destination.sort()
    email_page_source.length = 0;
    email_page_dest.length = 0;
    for (i = 0; i < source.length; i++)
        email_page_source[i] = new Option(source[i])
    for (i = 0; i < destination.length; i++)
        email_page_dest[i] = new Option(destination[i])
}

function email_page_clear(element) {
    if (email_page_element_fresh(element))
        element.value = ''
}

function email_page_element_fresh(element) {
    return (element.value.match(email_page_element_re[element.name]))
}

function email_page_select_all() {
    for (i = 0; i < email_page_source.length; i++)
        email_page_source[i].selected = 1;
    for (i = 0; i < email_page_dest.length; i++)
        email_page_dest[i].selected = 1;
}

function email_page_validate() {
    if (email_page_dest.length < 1) {
        email_page_error_message(
            loc('error -> To send email, you must specify a recipient'))
        return false
    }
    email_page_submit_buttons.style.display = 'none'
    email_page_select_all()
    form_email_page.submit()
    return true;
}
