// Regular expression for validating email addresses. Not perfect,
// but close enough to eliminate the majority of invalid addresses,
// which erring on the side of caution. Adapted from here:
//
// http://fightingforalostcause.net/misc/2006/compare-email-regex.php
//

Socialtext.prototype.check_email = (function($) {
    var EMAIL_ADDRESS = "([a-zA-Z0-9_'+*$%\\^&!\\.\\-])+"
                      + "@"
                      + "(([a-zA-Z0-9\\-])+\\.)+"
                      + "([a-zA-Z0-9:]{2,4})+";

    var EMAIL_ADDRESS_REGEX = new RegExp(
        "^" + EMAIL_ADDRESS + "$", "i"
    );

    var EMAIL_WITH_NAME_REGEX = new RegExp(
        "^[^<]+<" + EMAIL_ADDRESS + ">$", "i"
    )

    return function(email_address) {
        return EMAIL_ADDRESS_REGEX.test(email_address) ||
               EMAIL_WITH_NAME_REGEX.test(email_address);
    };
})(jQuery);
