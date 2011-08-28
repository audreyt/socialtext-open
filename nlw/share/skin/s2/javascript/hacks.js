
/* 
COPYRIGHT NOTICE:
    Copyright (c) 2004-2005 Socialtext Corporation 
    235 Churchill Ave 
    Palo Alto, CA 94301 U.S.A.
    All rights reserved.
*/

/*
 * A collection of external code overrides.
 * /

/* prototype does not deal with the broken handling of HTTP 204 done by
   IE 6.x. transport.status is seen as 1223 rather than 204 as expected.
 */

Ajax.Base.prototype.responseIsSuccess = function() {
    return this.transport.status == undefined
        || this.transport.status == 0
        || this.transport.status == 1223 /* we love you IE! */
        || (this.transport.status >= 200 && this.transport.status < 300);
}
