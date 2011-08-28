
/*==============================================================================
Ajax - Simple Ajax Support Library

DESCRIPTION:

This library defines simple cross-browser functions for rudimentary Ajax
support.

AUTHORS:

    Ingy döt Net <ingy@cpan.org>
    Kang-min Liu <gugod@gugod.org>
    Chris Dent <cdent@burningchrome.com>

COPYRIGHT:

Copyright Ingy döt Net 2006. All rights reserved.

Ajax.js is free software. 

This library is free software; you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation; either version 2.1 of the License, or (at
your option) any later version.

This library is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser
General Public License for more details.

    http://www.gnu.org/copyleft/lesser.txt

 =============================================================================*/

/* NOTE: This code has been made to coexist with prototype.js which is
 * notorious for NOT PLAYING WELL WITH OTHERS! However, this library must be
 * imported *after* prototype.js, or it will be clobbered. :\
 */

if (! this.Ajax) Ajax = {};

Ajax.VERSION = '0.10';

// The simple user interface function to GET/PUT/POST. If no callback is
// used, the function is synchronous.

Ajax.get = function(url, callback, params) {
    if (! params) params = {};
    params.url = url;
    params.onComplete = callback;
    return (new Ajax.Req()).get(params);
}

Ajax.put = function(url, data, callback, params) {
    if (! params) params = {};
    params.url = url;
    params.data = data;
    params.onComplete = callback;
    return (new Ajax.Req()).put(params);
}

Ajax.post = function(url, data, callback, params) {
    if (! params) params = {};
    params.url = url;
    params.data = data;
    params.onComplete = callback;
    if (! params.contentType)
        params.contentType = 'application/x-www-form-urlencoded';
    return (new Ajax.Req()).post(params);
}

if (this.Ajax.Req)
    throw("Oh no, somebody else is using the Ajax.Req namespace!");

Ajax.Req = function () {};
proto = Ajax.Req.prototype;

// Allows one to override with something more drastic.
// Can even be done "on the fly" using a bookmarklet.
// As an example, the test suite overrides this to test error conditions.
proto.die = function(e) { throw(e) };

// Object interface
proto.get = function(params) {
    return this._send(params, 'GET', 'Accept');
}

proto.put = function(params) {
    return this._send(params, 'PUT', 'Content-Type');
}

proto.post = function(params) {
    return this._send(params, 'POST', 'Content-Type');
}

// Set up the Ajax object with a working XHR object.
proto._init_object = function(params) {
    for (key in params) {
        if (! key.match(/^url|data|onComplete|contentType$/))
            throw("Invalid Ajax parameter: " + key);
        this[key] = params[key];
    }

    if (! this.contentType)
        this.contentType = 'application/json';

    if (! this.url)
        throw("'url' required for Ajax get/post method");

    if (this.request)
        throw("Don't yet support multiple requests on the same Ajax object");

    this.request = new XMLHttpRequest();

    if (! this.request)
        return this.die("Your browser doesn't do Ajax");
    if (this.request.readyState != 0)
        return this.die("Ajax readyState should be 0");

    return this;
}

proto._send = function(params, request_type, header) {
    this._init_object(params);
    this.request.open(request_type, this.url, Boolean(this.onComplete));
    this.request.setRequestHeader(header, this.contentType);

    var self = this;
    if (this.onComplete) {
        this.request.onreadystatechange = function() {
            self._check_asynchronous();
        };
    }
    this.request.send(this.data);
    return Boolean(this.onComplete)
        ? this
        : this._check_synchronous();
}

// TODO Allow handlers for various readyStates and statusCodes.
// Make these be the default handlers.
proto._check_status = function() {
    var status = String(this.request.status);
    if (status.match('^50[0-9]')) {
        return this.die(
            'Ajax request for "' + this.url +
            '" failed with status: ' + status
        );
    }
}

proto._check_synchronous = function() {
    var status = this._check_status();
    return { text: this.request.responseText, status: status };
}

proto._check_asynchronous = function() {
    if (this.request.readyState != 4) return;
    var status = this._check_status();
    this.onComplete({ text: this.request.responseText, status: status});
}

// IE support
if (window.ActiveXObject && !window.XMLHttpRequest) {
    window.XMLHttpRequest = function() {
        var name = (navigator.userAgent.toLowerCase().indexOf('msie 5') != -1)
            ? 'Microsoft.XMLHTTP' : 'Msxml2.XMLHTTP';
        return new ActiveXObject(name);
    }
}

/* A collection of routines, on one object, for manipulating a wikipage
 * constructed from javascript requests to the REST API.
 * 
 * Someday should add some of this sauce:
 * http://www.onjava.com/pub/a/onjava/2005/10/26/ajax-handling-bookmarks-and-back-button.html
 */
if (! this.STJS) STJS = function () {};
stproto = STJS.prototype; // needed?

stproto.workspaces_uri = function() {
    return '/data/workspaces';
}

stproto.workspace_uri = function() {
    return this.workspaces_uri() + '/' + this.workspace;
}
stproto.page_list_uri = function() {
    return this.workspace_uri() + '/pages';
}
stproto.tag_list_uri = function() {
    return this.workspace_uri() + '/tags';
}

stproto.clear = function(infobox) {
    infobox.innerHTML = '<div></div>';
}

stproto.listAttachments = function(infobox, uri) {
    var self = this;
    Ajax.get(
        uri,
        function(response) {
            var json = eval(response);
            var list = document.createElement('ul');
            infobox.replaceChild(list, infobox.childNodes[0]);
            for (var i = 0; i < json.length; i++) {
                var item = document.createElement('li');
                var link = document.createElement('a');
                var text = document.createTextNode(json[i].name);
                link.setAttribute('href', json[i].uri);
                link.setAttribute('target', '_other');
                item.appendChild(link);
                link.appendChild(text);
                list.appendChild(item);
            }
        },
        { "contentType": 'application/json' }
    );
    return true;
}


// display a clickable list of items from a collection
// clickFunction: the function to run when one of the items is clicked
// addItemStyle: an optional post process to run on all the items, to
// for example, add some stytle
stproto.listCollection = function(infobox, uri, clickFunction, addItemStyle) {
    var self = this;
    Ajax.get(
        uri,
        function(response) {
            var json = eval (response);
            var list = document.createElement('ul');
            infobox.replaceChild(list, infobox.childNodes[0]);
            var items = [];
            for (var i = 0; i < json.length ;i++) {
                var item = document.createElement('li');
                var text = document.createTextNode(json[i].name);
                items.push({'item': item, 'json': json[i]});
                item.appendChild(text);
                /* FIXME: use css classes to make this true */
                item.onmouseover = function() {
                    this.style.textDecoration = 'underline';
                }
                item.onmouseout = function() {
                    this.style.textDecoration = 'none';
                }
                item.onclick = function() {
                    clickFunction(this.innerHTML);
                    return false;
                }
                list.appendChild(item);
            }
            if (addItemStyle) {
                addItemStyle(items);
            }
        },
        { "contentType": 'application/json' }
    );
    return true;
}

// List clickable pages in a div, give a uri to fetch them
stproto.listPages = function(infobox, uri) {
    var self = this;
    this.listCollection(infobox, uri,
            function(name) {self.loadPage(name)});
}

// List recent changes in the 'changes' div
stproto.listChanges = function() {
    var uri = this.page_list_uri() + '?order=newest;count=10';
    this.listPages(document.getElementById('changes'), uri);
}


// List recent changes in the main div
stproto.listFullChanges = function() {
    document.getElementById('menuitems').style.display = 'block';
    if (! this.buttonsActive ) {
        this.activateButtons();
    }
    var uri = this.page_list_uri() + '?order=newest;count=20';
    var wikidiv = document.getElementById('wikipage');
    this.listPages(wikidiv, uri);
    var wikititle = document.getElementById('wikititle');
    wikititle.innerHTML = "Recent Changes";
    this.clear(document.getElementById('backlinks'));
    this.clear(document.getElementById('tags'));
    this.clear(document.getElementById('attachments'));
    document.getElementById('editbutton').style.display = 'none';
}

stproto.add_click_event = function(clickable, eventFunction) {
    if (document.all)  {
        clickable.attachEvent("onclick", eventFunction);
    } else {
        clickable.addEventListener("click", eventFunction, true);
    }
}

// Go home by discovering the title of the workspace
stproto.goHome = function() {
    var uri = this.workspace_uri();
    response = Ajax.get(uri, null, {'contentType': 'application/json'});
    // NOTE the necessary () around the response
    var json = eval('(' + response + ')');
    var title = json.title;
    this.loadPage(title);
}

stproto.activateButtons = function() {
    var self = this;
    this.add_click_event(
            document.getElementById('workspacesbutton'),
            function(event) { self.listWorkspaces(); }
    );
    this.add_click_event(
            document.getElementById('homebutton'),
            function(event) { self.goHome(); }
    );
    this.add_click_event(
            document.getElementById('changesbutton'),
            function(event) { self.listFullChanges(); }
    );
    this.add_click_event(
            document.getElementById('editbutton'),
            function(event) { self.editPage(); }
    );
    this.buttonsActive = 1;
}

stproto.returnToPage = function() {
    document.getElementById('wikipage').style.display = 'block';
    document.getElementById('wikiedit').style.display = 'none';
}

stproto.putPage = function(pageName, wikitext) {
    var uri = this.page_list_uri() + '/' + encodeURIComponent(pageName);
    Ajax.put(uri,
        wikitext,
        function(response) {true},
        {'contentType' : 'text/x.socialtext-wiki'}
    );
}

stproto.editPage = function() {

    var pageName = document.getElementById('wikititle').innerHTML;
    document.getElementById('wikipage').style.display = 'none';

    var self = this;
    var editform = document.forms.wikiform;
    editform.onsubmit = function() {
        self.putPage(pageName, this.elements['wikitext'].value);
        self.returnToPage();
        self.loadPage(pageName);
        return true;
    }
    editform.onreset =  function() { self.returnToPage(); return true;}
    document.getElementById('wikiedit').style.display = 'block';

    var uri = this.page_list_uri() + '/' + encodeURIComponent(pageName);
    var response = Ajax.get(uri,
        null,
        {'contentType':'text/x.socialtext-wiki'}
    );
    editform.elements['wikitext'].value = response;
}

// display a clickable list of workspaces
stproto.listWorkspaces = function() {
    document.getElementById('menuitems').style.display = 'none';
    document.getElementById('wikititle').innerHTML = 'Workspaces';

    this.clear(document.getElementById('backlinks'));
    this.clear(document.getElementById('changes'));
    this.clear(document.getElementById('tags'));
    this.clear(document.getElementById('attachments'));

    var infobox = document.getElementById('wikipage');
    var uri = this.workspaces_uri() + '?q=selected';
    var self = this;
    this.listCollection(infobox, uri,
            function(name) {
                self.workspace = name;
                self.listFullChanges();
            }
    );
}

stproto.loadAttachments = function(pageName) {
    var infobox = document.getElementById('attachments');
    var uri = this.page_list_uri() + '/'
        + encodeURIComponent(pageName)
        + '/attachments';
    // Attachments are not like the other Collections, as the 'name' is
    // not enough for downloading, and we want _real_ links
    this.listAttachments(infobox, uri);
}

// Load and list tags for a particular page
stproto.loadTags = function(pageName) {
    var infobox = document.getElementById('tags');
    var uri = this.page_list_uri() + '/'
        + encodeURIComponent(pageName)
        + '/tags';
    var self = this;
    this.listCollection(infobox, uri,
            function(name) {self.listTaggedPages(name)},
            function(items) {
                for (var i = 0; i < items.length; i++) {
                    var weight = items[i].json.page_count;
                    var fontsize = (weight * 25) + 100;
                    fontsize = Math.min(fontsize, 250);
                    items[i].item.style.fontSize = fontsize + '%';
                }
            }
    );
}

// List backlist for a particular page
stproto.listBacklinks = function(pageName) {
    var uri = this.page_list_uri()
        + '/' + encodeURIComponent(pageName)
        + '/backlinks?order=newest;count=10';
    this.listPages(document.getElementById('backlinks'), uri);
}

// List the pages belonging to a particular page
stproto.listTaggedPages = function(tagName) {
    var wikidiv = document.getElementById('wikipage');
    var wikititle = document.getElementById('wikititle');
    wikititle.innerHTML = loc("Pages tagged with") + " " + tagName;
    tagName = tagName.replace(/\s+$/m, '');
    var uri = this.tag_list_uri() + '/'
        + encodeURIComponent(tagName)
        + '/pages';
    this.clear(wikidiv);
    this.listPages(wikidiv, uri);
    this.clear(document.getElementById('tags'));
    this.listChanges();
    this.clear(document.getElementById('backlinks'));
    document.getElementById('editbutton').style.display = 'none';
}

// Load a page, display it in the main div, and makes it's links
// clickable. Not asynch. The other things are.
stproto.loadPage = function(pageName) {
    var encodedPageName = encodeURIComponent(pageName);
    var uri = this.page_list_uri() + '/' + encodedPageName;

    var wikidiv = document.getElementById('wikipage');
    var wikititle = document.getElementById('wikititle');
    if (this.displayPage(wikidiv, pageName, uri)) {
        wikititle.innerHTML = pageName
        self.loadTags(pageName);
        self.listChanges();
        self.listBacklinks(pageName);
        self.loadAttachments(pageName);
        self.displayEditButton();
    }
}

stproto.displayPage = function(wikidiv, uri) {
    var self = this;


    var response;
    try {
        response = Ajax.get( uri, null, {'contentType' :'text/html'});
    } catch (e) { 
        if (e.match('404')) {
            response = loc('page does not exist');
        } else {
            response = e;
        }
    }    
    if (response.length) {
        wikidiv.innerHTML = response;
        var links = wikidiv.getElementsByTagName('a');
        for (var i = 0; i < links.length; i++) {
            var link = links[i];
            var href = link.getAttribute('href');
            if (href) {
                if (href.match('^[^#/]+$') && !href.match('mailto')) {
                    link.onclick = function() {
                        self.loadPage(this.innerHTML);
                        return false;
                    }
                }
                else if (href.match('^/data/workspaces/[^/]+/pages/[^/]+$') && !href.match('/exchange/')) {
                    link.onclick = function() {
                        var href = this.getAttribute('href');
                        var matches = href.match('^/data/workspaces/([^/]+)/pages/[^/]+$');
                        self.workspace = matches[1];
                        self.loadPage(this.innerHTML);
                        return false;
                    }
                }
            }
        }
        return 1;
    }
    return 0;
}

stproto.displayEditButton = function() {
    // Safari can't PUT, so no edit
    if (!(navigator.userAgent.indexOf("Safari") > 0)) {
        document.getElementById('editbutton').style.display = 'inline';
    }
}

// END

