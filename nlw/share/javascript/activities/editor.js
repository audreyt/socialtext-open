(function($) {

if (typeof(Activities) == 'undefined') Activities = {};

Activities.Editor = function (opts) {
    this.extend(opts);
    this.requires([
        'static_path', 'base_uri', 'network', 'onPost', 'share'
    ]);
    this.find('.post a').button();
};

Activities.Editor.prototype = new Activities.Base();

$.extend(Activities.Editor.prototype, {
    toString: function() { return 'Activities.Editor' },

    _defaults: {
        max_wikiwyg_height: 120,
        max_filesize: 50,
        lastsubmit: 0,
        minHeight: 0,
        _nodes: {}
    },

    wikiwygMode: (typeof WW_ADVANCED_MODE == 'undefined') ? null : (
        ($.browser.safari && parseInt($.browser.version) <= 500)
            || ($.browser.msie && Wikiwyg.is_selenium)
            || (navigator.userAgent.toLowerCase().indexOf('mobile') >= 0)
            || (navigator.userAgent.toLowerCase().indexOf('adobeair') >= 0)
    ) ? WW_ADVANCED_MODE : WW_SIMPLE_MODE,

    // Nodes:
    find: function(selector) {
        if (!this._signals) {
            this._signals = this.node.parents('.signals, .replies');
        }
        if (!this._nodes[selector]) {
            this._nodes[selector] = this._signals.find(selector);
        }
        return this._nodes[selector];
    },

    setupWikiwyg: function() {
        var self = this;
        if (self.set_up) return;
        self.node.css('visibility', 'hidden');

        self.node.html(self.processTemplate('activities/wikiwyg.tt2', {
            wwid: self.node.attr('id'),
            evt: self.evt,
            richText: self.wikiwygMode == WW_SIMPLE_MODE
        }));

        function onload(node) {
            self.startEditMode();

            if (self.node.hasClass('mainWikiwyg') && self.initial_text) {
                var trySetInitialText = function() {
                    try {
                        var mode = self.wikiwyg.current_mode;
                        if (self.wikiwygMode == WW_ADVANCED_MODE) {
                            mode.insert_text_at_cursor(self.initial_text);
                            self.onChange();
                        }
                        else {
                            mode.get_inner_html(function(){
                                setTimeout(function(){
                                    mode.insert_html(
                                        Wikiwyg.htmlEscape(
                                            self.initial_text
                                        )
                                    );
                                    self.onChange();
                                }, 1500);
                            });
                        }
                    } catch (e) {
                        setTimeout(trySetInitialText, 300);
                    }
                };
                setTimeout(trySetInitialText, 300);
            }
            self.set_up = true;
        }

        if (self.wikiwygMode == WW_ADVANCED_MODE) {
            onload();
        }
        else {
            self.node.find('iframe')
                .one('load', function() {
                    $(this.contentWindow.document.body).addClass('signals');
                    onload();
                })
                .attr('src',
                    '/data/accounts/' + st.viewer.primary_account_id
                    + '/theme/wikiwyg.html'
                )
        }

        self.adjustHeight();
    },

    startEditMode: function() {
        var self = this;

        // Wikiwyg configuration
        var myConfig = {
            border: 'none',
            noToolbar: true,
            noTableSorting: true,
            postUrl: '/',
            modeClasses: [ WW_SIMPLE_MODE, WW_ADVANCED_MODE ],
            doubleClickToEdit: false,
            firstMode: this.wikiwygMode,
            justStart: true,
            editHeight: self.node.height(),
            javascriptLocation: '/static/skin/s3/javascript/',
            wysiwyg: {
                clearRegex: '',
                iframeId: self.node.find('iframe').attr('id'),
                editHandler: function(el) {
                    var widget = ($(el).attr('alt') || '').replace(/^st-widget-/, '');
                    if (widget.match(/{hashtag: (.*)}/)) {
                        self.showTagLookahead(el, RegExp.$1);
                    }
                    else if (widget.match(/(?:"(.*)")?{user: (.*)}/)) {
                        self.showMentionLookahead(el, RegExp.$1);
                    }
                    else if (widget.match(/(?:"(.*)")?{video: (.*)}/)) {
                        self.showVideoUI(el, RegExp.$1, RegExp.$2);
                    }
                    // matches `"title"{link: ws [page] section}`
                    else if ( widget.match(/(?:"(.*)")?{link:\s*(\S+)\s*\[(.+)\]\s*(.*)}/)) {
                        self.showLinkUI(el, {
                            label:     RegExp.$1,
                            workspace: RegExp.$2,
                            page:      RegExp.$3,
                            section:   RegExp.$4
                        });
                    }
                }
            },
            wikitext: {
                clearRegex: '',
                textareaId: self.node.find('textarea').attr('id')
            }
        };

        var wikiwyg = self.wikiwyg = new Wikiwyg();

        wikiwyg.createWikiwygArea(self.node.find('div').get(0), myConfig);
        if (! wikiwyg.enabled)
            throw new Error("Failed to initialize the editor");

        wikiwyg.modeButtonMap = {};

        // {bz: 4721}: Force entering editMode(), bypassing the
        // Socialtext.page_type check when launching "Signal This" on
        // SocialCalc spreadsheet pages.
        var originalPageType = Socialtext.page_type;
        Socialtext.page_type = 'wiki';
        wikiwyg.editMode();
        Socialtext.page_type = originalPageType;

        var mode = wikiwyg.current_mode;
        mode.bind('keypress', function(e){
            return self.keyPressHandler(e);
        });
        mode.bind('keyup', function(e){
            self.adjustWikiwygHeight();
            return self.onChange();
        });

        if (self.onBlur) {
            mode.bind('blur', function(e) {
                if (!self._noblur) self.onBlur();
            });
        }

        self.find('.post')
            .show()
            .click(function () {
                self.submitHandler();
                return false;
            })
            .mousedown(function() {
                self.holdBlur();
            });

        // The click handler that loaded wikiwyg has been run already, so
        // unbind said handler and show wikiwyg
        self.node.unbind('click').show();

        // Create proper handlers for toolbar icons
        // For some reason, the textarea isn't showing up in webkit, so
        // show it explicitly here
        if (this.wikiwygMode == WW_ADVANCED_MODE) {
            self.node.find('textarea').show();
            // Focus on the textarea right after .setupToolbar below finishes
            setTimeout(function(){
                self.node.find('textarea').focus();
            }, 600);
        }

        if (this.mention_user_id) this.showProfileMention();

        setTimeout(function() { self.setupToolbar() }, 500 );

        self.node.css('visibility', 'visible');
        self.onChange();
        this.adjustHeight();
    },

    isVisible: function() {
        return this.node.is(':visible');
    },

    click: function() {
        this.node.click();
    },

    setupToolbar: function() {
        var self = this;

        var $toolbar = self.find('.toolbar');
        $toolbar.show();
        $toolbar.find('.insertMention').unbind('click').click(function (){
            self.showMentionLookahead();
            return false;
        });

        // Don't blur wikiwyg when we click a lookahead link
        $toolbar.find('.hideOnBlur')
            .unbind('mousedown').mousedown(function (){
                self.holdBlur();
                return false
            }
        );

        var openDialog = function (cb) {
            if (!$.browser.msie) { return cb(); }

            if (self._wikitext_initialized) {
                return cb();
            }

            // IE Only: Fix {bz: 4779} by delaying the popup until after
            // Wysiwyg mode is fully initialized (which takes 500ms).
            self.getWikitext(function(){
                setTimeout(function(){
                    self._wikitext_initialized = true;
                    return cb();
                }, 600);
            });
        };

        $toolbar.find('.startPrivate').unbind('click').click(function() {
            openDialog(function(){
                self.showPrivateLookahead();
            });
            return false;
        });
        $toolbar.find('.insertTag').unbind('click').click(function() {
            openDialog(function(){
                self.showTagLookahead();
            });
            return false;
        });
        $toolbar.find('.insertFile').unbind('click').click(function() {
            openDialog(function(){
                self.showUploadAttachmentUI();
            });
            return false;
        });
        $toolbar.find('.insertLink').unbind('click').click(function() {
            openDialog(function(){
                self.showLinkUI();
            });
            return false;
        });
        $toolbar.find('.insertVideo').unbind('click').click(function() {
            openDialog(function(){
                self.showVideoUI();
            });
            return false;
        });
    },

    // Prevent the submit from being run for 500ms
    holdSubmit: function() {
        var self = this;
        self._nosubmit = true;
        setTimeout(function() { self._nosubmit = false }, 500);
    },

    // Prevent the blur from being triggered for 500ms
    holdBlur: function() {
        var self = this;
        self._noblur = true;
        setTimeout(function(){ self._noblur = false }, 500);
    },

    keyPressHandler: function (e) {
        var self = this;
        var key = e.charCode || e.keyCode;
        if (key == $.ui.keyCode.ENTER) {
            if (!self._nosubmit) self.submitHandler();
            return false;
        }
        else if (key == "@".charCodeAt(0) && !$.mobile) {
            var typed = self.wikiwyg.current_mode.getInnerText();
            if (typed == '' || /\s$/.test(typed)) {
                self.holdBlur();
                self.showMentionLookahead();
                return false;
            }
        }
    },

    adjustWikiwygHeight: function() {
        if (navigator.userAgent.toLowerCase().indexOf('mobile') >= 0) {
            return;
        }

        // Store the initial min-height
        if (!this.minHeight) {
            this.minHeight = this.node.height();
        }

        // Ensure that signalFrame is big enough to show content
        if (this.wikiwygMode == WW_ADVANCED_MODE) {
            var ta = this.node.find('textarea').get(0)
            $(ta).height(this.node.attr('min-height'));
            var height = Math.max(ta.scrollHeight, ta.clientHeight);
            if (height > ta.clientHeight) {
                var newHeight = Math.min(height + 2, this.max_wikiwyg_height);
                $(ta).parents('.wikiwyg').height(newHeight);
                $(ta).height(newHeight);
            }
        }
        else {
            var body = this.node.find('iframe')
                .get(0).contentWindow.document.body;
            var div = $(body).find('#wysiwyg-editable-div').get(0);
            
            // Make sure IE7 has overflow set to visible so we get
            // scrolling on the body rather than the div!!
            $(div).css('overflow', 'visible');

            // Collapse the frame down to our minHeight, then compensate
            // for any scrolling by resizing the iframe back up to fit all
            // its contents
            this.node.find('iframe').height(this.minHeight);

            var newHeight = Math.min(body.scrollHeight, this.max_wikiwyg_height);
            if (body.scrollHeight > newHeight) {
                this.node.find('iframe').attr('scrolling', 'auto');
            }
            else {
                this.node.find('iframe').attr('scrolling', 'no');
            }

            this.node.find('iframe').height(newHeight);
            this.node.height(newHeight);
        }
    },

    onChange: function() {
        var self = this;
        var $count = self.find('.count');
        if (!$count.size()) {
            return;
        }

        if (!self.node.size() || !this.wikiwyg) {
            $count.text(self.maxSignalLength());
            return 0;
        }

        var err = loc(
            "error.signal-too-long=max-length",
            self.maxSignalLength()
        )

        // update the height
        self.adjustWikiwygHeight();

        // count the chars in the input box
        self.getWikitext(function(wikitext) {
            wikitext = wikitext.replace(
                /(?:"[^"]+")?{(?:user|hashtag|link):[^}]+}/g, '%'
            );
            var remaining = self.maxSignalLength() - wikitext.length;
            $count.text(remaining);
            if (remaining < 0) {
                // XXX Make wikiwyg background #ff6666
                self.showError(err);
                $count.addClass('count_error');
            }
            else {
                self.clearMessages(loc('error.error'));
                self.clearErrors();
                $count.removeClass('count_error');
            }
        });
    },

    checkForLinks: function(wikitext) {
        var self = this;

        if (self.has_link) return;

        var patterns = [
            {
                re: /http:\/\/www.youtube.com\/watch\?v=([^&]+)/,
                getOpts: function(cb) {
                    var video = RegExp.$1;
                    var uri = 'http://gdata.youtube.com/feeds/api/videos'
                            + '?q=' + video + '&v=2&alt=jsonc';
                    self.makeRequest(uri, function(data) {
                        cb({ youtube: video, data: data.data });
                    });
                }
            }
        ];

        var words = wikitext.split(' ');
        words.pop();

        $.each(words, function(i, word) {
            if (!word.match(/^http:\/\//)) return;
            $.each(patterns, function(j, pattern) {
                if (word.match(pattern.re)) {
                    self.has_link = true;
                    pattern.getOpts(function(opts) {
                        var html = self.processTemplate(
                            'activities/links.tt2', opts
                        );
                        self.findId('signals .links .link').html(html);
                        self.link_annotation = { html: html };
                    });
                    return false;
                }
            });
            if (self.has_link) return false;
        });
        if (self.has_link) {
            self.findId('signals .links').show();
            self.findId('signals .links .cancel')
                .click(function() { self.cancelLink(); return false })
                .mouseover(function() { $(this).addClass('hover') })
                .mouseout(function() { $(this).removeClass('hover') });
        }
    },

    cancelLink: function(reset) {
        if (reset) this.has_link = false;
        self.link_annotation = undefined;
        $('.links').hide();
    },

    showProfileMention: function() {
        this.startMention({
            user_id: this.mention_user_id,
            best_full_name: this.mention_user_name
        });
    },

    resetInputField: function (is_reply) {
        var self = this;
        if (this.wikiwygMode == WW_ADVANCED_MODE) {
            // Safari
            this.wikiwyg.current_mode.setTextArea('');
        }
        else if ($.browser.msie) {
            /* {bz: 2369}: IE Stack Overflows when the innerHTML has no
             * text nodes, so we append a trailing newline to create an
             * empty text node.
             *
             * Also, set_inner_html()'s latency fix would wait until editor
             * is fully initialized, but it doesn't apply here (and would
             * actually cause Stack Overflows by itself), so we fallback
             * to a manual .html() call.
             */
             $('#wysiwyg-editable-div',
                self.node.find('iframe').get(0).contentWindow.document
             ).html("\n");
        }
        else {
            // Firefox
            this.wikiwyg.current_mode.set_inner_html('');
        }
        this.cancelLink(true);
        this.onChange();
        this.focus();
        this.cancelAttachments();
    },

    focus: function () {
        this.wikiwyg.current_mode.set_focus();
    },
    blur: function () {
        this.wikiwyg.current_mode.blur();
    },

    submitHandler: function() {
        var self = this; 
        if (this.findId('signalsInput').is(':hidden')) return;

        var lastsubmit = this.lastsubmit;
        var now =  (new Date).getTime();
        if ((now-lastsubmit) < 2000) return;
        this.lastsubmit = (new Date).getTime();

        this.getWikitext(function(wikitext) {
            if (self.signal_this) {
                if (/\S/.test(wikitext)) {
                    wikitext += " >> " + self.signal_this;
                }
                else {
                    wikitext = self.signal_this;
                }
            }

            if (!wikitext.length) return;

            var post_data = self.getPostData();
            post_data.signal = wikitext;
            post_data.attachments = self.attachmentIds();

            self.postWikitext(post_data, function(response) {
                if (self.signal_this) {
                    var $frame = $(self.node).parents('.activitiesWidget');
                    $frame.find('.sent').fadeIn('slow', function(){
                        $frame.fadeOut(function(){$frame.remove()});
                    });
                    return;
                }

                if (self.mention_user_id) self.showProfileMention();
                self.stopPrivate();

                self.resetInputField();

                var signal = response.data;
                if (signal) {
                    signal.num_replies = 0;
                    self.onPost(signal);
                }
            });
        });
    },

    getWikitext: function(callback) {
        var self = this;
        if (!$.isFunction(callback)) throw new Error("callback required");
        if (self.wikiwygMode == WW_ADVANCED_MODE) {
            callback(self.wikiwyg.current_mode.toWikitext());
        }
        else {
            if (!self.wikiwyg.current_mode.get_edit_window()) return;
            var mode = self.wikiwyg.modeByName(WW_ADVANCED_MODE);
            self.wikiwyg.current_mode.toHtml(function(html) {
                // Remove things from the HTML before converting back to
                // wikitext
                html = html
                    .replace(/<\/?pre[^>]*>/,'')
                    .replace(/<br>/,'');

                mode.convertHtmlToWikitext(html, function(wt) {
                    wt = wt.replace(/\n*$/, '');
                    callback(wt);
                });
            });
        }
    },

    setNetwork: function(network) {
        this.network = network;
        this.onChange();
    },

    getRecipient: function() {
        return this.signal_recipient;
    },

    getPostData: function() {
        var reply_to_id = this.node.find('.replyTo').val();
        if (reply_to_id) {
            return {
                in_reply_to: {
                   signal_id: reply_to_id
                },
                account_ids: [],
                group_ids: []
            };
        }
        if (this.signal_recipient) {
            return {
                recipient: {
                    id: this.signal_recipient
                },
                account_ids: [],
                group_ids: []
            };
        }

        var account_ids = [];
        var group_ids = [];
        if (this.network && this.network.value != 'all') {
            if (this.network.account_id) {
                account_ids.push(Number(this.network.account_id));
            }
            else if (this.network.group_id) {
                group_ids.push(Number(this.network.group_id));
            }
        }

        return {
            account_ids: account_ids,
            group_ids: group_ids
        }
    },

    postWikitext: function(post_data, callback) {
        var self = this;

        // Wikiwyg seems to get a \n at the end, which messes with our
        // ability to count characters.
        post_data.signal = post_data.signal
            .replace(/(?:\n|^)\.pre(?:\n|$)/g, '')
            .replace(/\n+$/g, '');

        // Add annotations
        if (this.link_annotation) {
            post_data.annotations = {
                link: this.link_annotation
            };
        }

        // Prefix the username to all mentions. Unfortunately, this
        // means that replies get the username stuck into the signal
        // body. If we don't do that, they won't end up in the user's
        // signals feed and then they won't show up as a reply
        var show_prefix = this.mention_user_id
                        && !post_data.recipient
                        && !post_data.in_reply_to;
        if (show_prefix) {
            var user_wafl = '{user: ' + this.mention_user_id +'}'
            if (!post_data.signal.match(new RegExp('^'+user_wafl))) {
                post_data.signal = user_wafl + ' ' + post_data.signal;
            }
        }

        var params = {};
        params[gadgets.io.RequestParameters.HEADERS] = {
            'Content-Type' : 'application/json'
        };
        params[gadgets.io.RequestParameters.METHOD]
            = gadgets.io.MethodType.POST;
        params[gadgets.io.RequestParameters.POST_DATA]
            = gadgets.json.stringify(post_data);
        params[gadgets.io.RequestParameters.CONTENT_TYPE] = 
            gadgets.io.ContentType.JSON;

        self.node.css('visibility', 'hidden');
        gadgets.io.makeRequest(this.base_uri + '/data/signals', 
            function (data) {
                self.node.css('visibility', 'visible');

                if (data.rc == 201) {
                    callback(data);
                }
                else if (data.rc == 413) {
                    var limit = data.headers['x-signals-size-limit'];
                    self.updateMaxSignalLength(limit);
                    self.showError(
                        loc("error.signal-too-long=max-length", limit)
                    );
                }
                else {
                    var msg;
                    if (data.text && data.text == 'invalid workspace') {
                        msg = loc("error.no-such-wikilink-wiki");
                    }
                    else {
                        msg = data.data
                            || loc("error.send-signal");
                    }
                    self.showError(msg);
                }
            },
            params
        );
    },

    maxSignalLength: function() {
        var limit = this.network.signals_size_limit;
        if (this.signal_this) {
            var wikitext = this.signal_this.replace(
                /(?:"[^"]+")?{(?:user|hashtag|link):[^}]+}/g, '%'
            );
            limit -= (wikitext.length + 4) // " >> "
        }
        return limit;
    },

    updateMaxSignalLength: function(limit) {
        this.network.signals_size_limit = Number(limit);
    },

    startPrivate: function (user_or_evt) {
        var self = this;
        if (this.findId('signals').size()) {
            // XXX this.stopReply();
            this.stopMention();
            this.reply_to_signal = null;
            this.signal_recipient = user_or_evt.user_id
                                 || user_or_evt.actor.id;
            var recipient_name = user_or_evt.best_full_name
                              || user_or_evt.actor.best_full_name;

            this.showMessageNotice({
                best_full_name: recipient_name,
                user_id: this.signal_recipient,
                className: 'private',
                onCancel: function() { self.stopPrivate() }
            });
        }
        // don't re-send already sent events
        else if (!user_or_evt.command) {
            user_or_evt.command = 'private';
            user_or_evt.instance_id = this.instance_id;
        }
    },

    stopPrivate: function() {
        if (this.signal_recipient) {
            this.signal_recipient = null;
            this.resetInputField(this.mainWikiwyg);
            this.clearMessages('private');
        }
    },

    startMention: function(user, isPrivate) {
        var self = this;

        // Don't start messages addressed to yourself
        if (user.user_id == this.viewer_id) return;

        this.mention_user_name = user.best_full_name;
        this.mention_user_id = user.user_id;

        if (isPrivate) {
            this.signal_recipient = user.user_id;
        }

        var $msg = this.showMessageNotice({
            best_full_name: this.mention_user_name,
            user_id: this.mention_user_id,
            className: 'mention',
            isPrivate: isPrivate
        });

        $('.toggle-private', $msg).change(function() {
            self.startMention(user, $(this).is(':checked'))
        });
    },

    stopMention: function() {
        if (this.mention_user_id) {
            this.mention_user_name = null;
            this.mention_user_id = null;
            this.resetInputField(this.mainWikiwyg);
            this.clearMessages('mention');
        }
    },

    escapeHTML: function(text) {
        var result = text.replace(/&/g,'&amp;'); 
        result = result.replace(/>/g,'&gt;');   
        result = result.replace(/</g,'&lt;');  
        result = result.replace(/"/g,'&quot;');
        return result;
    },

    insertWidget: function(widget, el) {
        var self = this;
        var mode = self.wikiwyg.current_mode;
        
        mode.insert_widget(widget, el);
        self.onChange();

        // bind a handler to the wafl so we can call onChange again
        // once it loads.
        if (self.wikiwygMode == WW_SIMPLE_MODE) {
            var imgs = mode.get_edit_document().getElementsByTagName('img');
            $.each(imgs, function(i, image) {
                if (image.widget == widget) {
                    $(image).load(function() {
                        self.onChange();
                    });
                }
            });
        }
    },

    insertUserMention: function(user, el) {
        var widget = '"' + user.best_full_name + '"'
                   + '{user: ' + user.user_id + '}';
        this.insertWidget(widget, el);
    },

    insertTag: function(tag, el) {
        if (!/\S/.test(tag)) { return; }
        var widget = '{hashtag: ' + tag + '}';
        this.insertWidget(widget, el);
    },

    hideLookahead: function($dialog,cb) {
        var self = this;
        $dialog.fadeOut(function() {
            $('.ui-autocomplete-error').hide();
            if ($.isFunction(cb)) cb();
        });
    },

    showLookahead: function(opts) {
        var self = this;
        if (!opts.url) throw new Error("url required");
        if (!opts.callback) throw new Error("callback required");
        if (!opts.message) throw new Error("message required");

        var $dialog = self.find('.lookahead');
        if ($.browser.msie && !self.node.hasClass('mainWikiwyg')) {
            /* {bz: 4803}: IE needs lookahead div placed on the same level as
             * .event elements, otherwise it will overlap with the next element.
             */
            if ($dialog.length) {
                $dialog.show();
                var top = $dialog.offset().top;
                var left = $dialog.offset().left;
                $dialog = $dialog.remove().insertAfter(
                    self.node.parents('.event:first')
                );
                $dialog.css({
                    top: top + 'px',
                    left: left + 'px'
                });
                $dialog.hide();
                self.node.data('lookahead', $dialog);
            }
            else {
                $dialog = self.node.data('lookahead');
            }
        }

        var $input = $('input', $dialog);

        if ($dialog.is(':visible')) {
            return self.hideLookahead($dialog);
        }

        $('.message', $dialog).text(opts.message);

        $dialog.show();

        // Make OK and Cancel buttons
        if (opts.requireMatch) {
            $('.insert', $dialog).hide();
            $('.buttons', $dialog).buttonset();
        }
        else {
            $('.insert', $dialog).show();
            $('.buttons', $dialog).buttonset();
            $('.insert', $dialog).unbind('click').click(function() {
                opts.callback(null, $input.val());
                $input.blur();
                self.focus();
                self.hideLookahead($dialog);
                return false;
            });
        }

        $('.cancel', $dialog).unbind('click').click(function() {
            $input.blur();
            self.focus();
            self.hideLookahead($dialog);
            return false;
        });

        if (opts.value) {
            $input.val(opts.value);
        }
        else {
            $input
                .val(loc("lookahead.start-typing"))
                .addClass('lookahead-prompt')
                .one('mousedown', function() {
                    $(this)
                        .val('')
                        .removeClass("lookahead-prompt");
                })
        }

        $input.lookahead($.extend({
            url: opts.url,
            clearOnHide: true,
            allowMouseClicks: $dialog,
            clickCurrentButton: $('.insert', $dialog),
            getWindow: function() {
                var win = window;
                // Use window if the parent window is cross-domain
                try {
                    // test cross-domain
                    if (window.parent.$) win = window.parent;
                } catch(e) { }
                return win;
            },
            params: {
                accept: 'application/json',
                order: 'name'
            },
            onAccept: function(id, item) {
                $input.blur();
                opts.callback(item, id);
            },
            onBlur: function() {
                $input.val('');
                self.hideLookahead($dialog, function (){
                    self.focus();
                });
            },
            onFirstType: function(element) {
                element.removeClass("lookahead-prompt");
            }
        }, opts)).focus().select();
    },

    cancelAttachments: function() {
        this.find('.attachmentList').html('').hide();
    },

    _attachmentsByAttr: function(attr) {
        var $alist = this.find('.attachmentList');
        var values = [];
        $alist.find('.attachment .' + attr).each(function(i,input) {
            values.push($(input).val());
        });
        return values;
    },

    attachmentIds: function() {
        return this._attachmentsByAttr('id');
    },

    attachmentNames: function() {
        return this._attachmentsByAttr('filename');
    },

    addAttachment: function(filename, temp_id) {
        var self = this;
        var $alist = self.find('.attachmentList');

        // Add the new attachment to the new signal
        $alist.append(
            self.processTemplate('activities/attachment_entry.tt2', {
                filename: filename,
                temp_id: temp_id
            })
        );
        $alist.find('.remove').unbind('click').click(function() {
            // Remove this entry
            $(this.parentNode).remove();

            // Hide the list if it is empty now
            if (!$alist.find('.attachment').size()) $alist.hide();
            return false;
        });
        $alist.show().css('width', '100%');
    },

    showUploadAttachmentUI: function() {
        var self = this;
        socialtext.dialog.show('activities-add-attachment', $.extend({
            callback: function(filename, result) {
                self.addAttachment(filename, result.id);
            }
        }, self));
    },

    showUserLookahead: function(opts) {
        var self = this;
        this.showLookahead($.extend({
            requireMatch: true,
            getEntryThumbnail: function(user) {
                return self.base_uri
                    + '/data/people/' + user.value + '/small_photo';
            },
            linkText: function (user) {
                return [user.display_name, user.user_id];
            },
            displayAs: function(user) {
                return user.title;
            }
        }, opts));
    },

    showLinkUI: function(el, defaults) {
        var self = this;
        
        var wikiwyg = self.wikiwyg.current_mode;

        socialtext.dialog.show('activities-add-link', {
            params: defaults,
            selectionText: wikiwyg.get_selection_text(),
            callback: function(dialog, args) {
                if (args.workspace) {
                    self.make_wikilink({
                        workspace: args.workspace,
                        page:  args.page,
                        label: args.label,
                        section: args.section,
                        element: el,
                        error: function(msg) {
                            dialog.showError(msg);
                        },
                        success: function() {
                            dialog.close();
                        }
                    });
                }
                else {
                    if (!wikiwyg.valid_web_link(args.destination)) {
                        dialog.showError(loc('error.invalid-web-link'));
                        return false;
                    }

                    // check if the link is an internal wikilink
                    var wiki = self.is_wikilink(args.destination);
                    if (wiki) {
                        self.make_wikilink({
                            workspace: wiki.ws,
                            page: wiki.page,
                            label: label,
                            section: wiki.section,
                            error: function(msg) {
                                dialog.showError(msg);
                            },
                            success: function() {
                                dialog.close();
                            }
                        });
                    }
                    else {
                        wikiwyg.make_web_link(args.destination, args.label);
                        self.onChange();
                        dialog.close();
                    }
                }
            }
        });
    },

    is_wikilink: function(destination) {
        var self = this;

        // Basic regex for all nlw urls
        if (destination.match(/^[^:]+:\/+([^\/]+)\/([-_a-z0-9]+)\/((?:index\.cgi)?\?)?([^\/#]+)(?:#(.+))?$/)) {
            var link_host = RegExp.$1;
            var workspace = RegExp.$2;
            var index_cgi = RegExp.$3;
            var page      = RegExp.$4; // needs further manipulation?
            var section   = RegExp.$5;

            if (index_cgi) {
                page = page.replace(/.*\baction=display;is_incipient=1;page_name=/, '');
            }

            if (/=/.test(page)) {
                return false;
            }

            if (/^(?:nlw|challenge|data|feed|js|m|settings|soap|st|wsdl)$/.test(workspace)) {
                return false;
            }

            // remove the protocol
            var app_host = self.base_uri.split('/')[2];
            if (app_host != link_host) return false;
            
            if (/^(?:nlw|challenge|data|feed|js|m|settings|soap|st)$/.test(workspace)) return false;

            return {
                ws: workspace,
                page: decodeURIComponent(page),
                section: decodeURIComponent(section)
            };
        }

        return false;
    },

    make_wikilink: function(opts) {
        var self = this;

        if (opts.workspace.length == 0) {
            opts.error(loc("error.wikilink-wiki-required"));
            return;
        }
        
        if (opts.page.length == 0) {
            opts.error(loc("error.wikilink-page-required"));
            return;
        }

        $.ajax({
            type: ($.browser.webkit ? 'GET' : 'HEAD'), // {bz: 4490}: Chrome's support of HEAD+SSL is broken
            url: self.base_uri + '/data/workspaces/' + opts.workspace,
            error: function() {
                opts.error(loc("error.invalid-wikilink-wiki"));
            },
            success: function() {
                var widget = self.wikiwyg.current_mode.create_link_wafl(
                    opts.label || opts.page,
                    opts.workspace, opts.page, opts.section
                );
                self.wikiwyg.current_mode.insert_widget(widget, opts.element);

                self.onChange();
                opts.success();
            }
        });
    },

    placeInParentWindow: function(html, id) {
        var $popup;

        // Default to window when window.parent is cross-domain
        var win = window;
        try { if (window.parent.$) win = window.parent } catch(e) {}

        if (id) {
            // Try to re-use the old element
            $popup = this.findId(id, win);
            if ($popup.size() == 0) {
                $popup = win.$(html)
                    .attr('id', this.prefix + id)
                    .appendTo('body');
            }
        }

        var width = this.node.width();

        $popup.css({
            // this has to be visible to be positioned, so start it off screen
            top: '-10000px',
            left: '-10000px',
            width: width + 'px'
        });
        $popup.show();
        $popup.position({
            my: "left top",
            at: "left bottom",
            of: this.node,
            collision: "none fit"
        });
        return $popup;
    },

    showVideoUI: function(el, title, url) {
        var self = this;

        var wikiwyg = self.wikiwyg.current_mode;

        socialtext.dialog.show('activities-add-video', {
            params: {
                video_url: url,
                video_title: title
            },
            callback: function(url, title) {
                if (!wikiwyg.valid_web_link(url)) return false;

                if (/^\s*$/.test(title)) title = url;

                var wafl;
                if (title) {
                    wafl = '"' + title.replace(/"/g, '') + '"';
                }
                wafl += '{video: ' + url + '}';

                self.insertWidget(wafl, el);
                self.onChange();
            }
        });
    },

    showTagLookahead: function(el, value) {
        var self = this;

        // Search for signal tags within the target network if we are
        // signalling to a network; search for signal tags within the
        // default network if we are DMing someone.

        // Create the lookahead URL
        var url = this.network.group_id
            ? '/data/groups/' + this.network.group_id + '/signaltags'
            : '/data/accounts/' + this.network.account_name + '/signaltags';

        this.showLookahead({
            url: self.base_uri + url,
            requireMatch: false,
            message: loc('signals.insert-tag:'),
            value: value,
            linkText: function (tag) {
                return tag.name;
            },
            callback: function (item, tag) {
                self.insertTag(tag, el);
                self.holdSubmit();
                self.hideLookahead(self.find('.lookahead'));
            }
        });
    },

    showMentionLookahead: function(el, value) {
        var self = this;
        this.showUserLookahead({
            url: self.base_uri + '/data/users',
            message: loc('signals.insert-mention:'),
            value: value,
            callback: function (item) {
                self.insertUserMention({
                    user_id: item.value,
                    best_full_name: item.title
                }, el);
                self.holdSubmit();
            }
        });
    },

    showPrivateLookahead: function() {
        var self = this;

        var url;
        if (self.workspace_id) {
            // Only allow private "Signal This" to other workspace members
            url = self.base_uri + '/data/workspaces/' + self.workspace_id + '/users';
        }
        else {
            url = self.base_uri + '/data/users';
        }

        this.showUserLookahead({
            url: url,
            message: loc('signals.private-message-to:'),
            callback: function (item) {
                self.startPrivate({
                    user_id: item.value,
                    best_full_name: item.title
                });
            }
        });
    }
});

})(jQuery);
