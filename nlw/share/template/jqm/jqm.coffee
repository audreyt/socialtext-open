### Reusable parts begin here ###

doInitPrefs = (ev, ui) ->
  return if $('#setup').data('oldPrefs')
  $('#setup').data('oldPrefs', $.extend({}, myPrefs)).show()
  $('#setup label:not(.ui-btn)').addClass 'ui-input-text'
  for own key, val of myPrefs
    onInitPref? key, val
    $input = $("input[name=#{key}], select[name=#{key}]")
    continue unless $input.length
    $input.data 'key', key
    switch $input.attr 'type'
      when 'checkbox'
        checked = if Number(myPrefs[key]) then true else false
        $input.prop 'checked', checked
        $label = $input.next('label')
        if checked
          $label.addClass('ui-btn-active')
              .find('span.ui-icon-checkbox-off')
              .removeClass('ui-icon-checkbox-off')
              .addClass('ui-icon-checkbox-on')
        else
          $label.removeClass('ui-btn-active')
              .find('span.ui-icon-checkbox-on')
              .removeClass('ui-icon-checkbox-on')
              .addClass('ui-icon-checkbox-off')
      else $input.val val
    if $input.find('option').length
      $input.prev().find('.ui-btn-text').text(
        $input.find('option:selected').text()
      )
    $input.setupColorPicker() if $input.hasClass('color')
  setTimeout doInitSetup, 100
  return

doInitSetup = ->
  unless /\S/.test($('input[name=Workspace]').val())
    $('input[name=Workspace]').focus()
  if $.fn.lookahead
    $.fn.createSelectOverlap ||= (->)
    $('input[name=Workspace]').lookahead
      filterName: 'name_filter'
      url: '/data/workspaces'
      requireMatch: true
      linkText: (i) -> [ i.title + ' (' + i.name + ')', i.name ]
      onAccept: (id, item) ->
        item.orig ||= { name: item.name }
        $('input[name=Workspace]').val item.orig.name
    $('input[name=Template]').lookahead
      filterName: 'name_filter'
      url: -> "/data/workspaces/#{$('input[name=Workspace]').val()}/tags/template/pages?type=wiki,xhtml"
      requireMatch: true
      linkText: (i) -> i.name
      onAccept: (id, item) ->
        item.orig ||= { name: item.name }
        $('input[name=Template]').val item.orig.name
    $('input.tag').setupTagLookahead?()
  onBeforeSetup?()
  gadgets.window.adjustHeight $('#setup').height() + 30
  return

withInstance = (callback, fallback) ->
  return if $.browser.msie and Number($.browser.version) <= 6
  instanceId = Number('__ENV_pref_instance_id__') || '__MODULE_ID__'
  if instanceId != '__' + 'MODULE_ID' + '__' and window.parent and window.parent.$
    $$ = window.parent.$("#gadget-#{instanceId}")
    if $$.length
      $save = window.parent.$("#st-savebutton-#{instanceId}")
      $settings = window.parent.$("#gadget-#{instanceId}-settings")
      callback $$, $save, $settings
      return true
  fallback?()
  return

draggable = $.fn.draggable
$.fn.draggable = (opts) ->
  draggable.call @, opts
  @.addTouch?()

$.fn.makeMinusIcon = ->
  $(@).data('icon', 'minus').parent()
    .removeClass('ui-btn-up-b')
    .addClass('ui-btn-up-c')
    .data('theme', 'c')
    .attr('title', loc('do.remove'))
    .find('.ui-icon-plus').removeClass('ui-icon-plus').addClass('ui-icon-minus')
  return

$.fn.setupTagLookahead = ->
  $(@).each ->
    $input = $(@)
    $input.lookahead
      filterName: 'name_filter'
      url: ->
        wksp = $('input[name=Workspace]').val()
        return '/static/error' unless wksp
        return "/data/workspaces/#{wksp}/tags"
      requireMatch: false
      linkText: (tag) -> tag.name
      onAccept: (tag) -> $input.val(tag)
      onError:
        404: ->
          $input.get(0).lookahead.getLookaheadList().find('li:not(:last)').remove()
          return loc("kanban.please-fill-in-wiki-field-first")

$.fn.setupColorPicker = ->
  $$ = $(@)
  $$.parent('nobr').replaceWith $$
  $$.attr 'name', $$.attr('id')
  $picker = $('<div />', css:
    cursor: 'pointer'
    float: 'left'
    height: '28px'
    width: '28px'
    border: '2px solid #999'
    borderRadius: '9px'
    '-moz-border-radius': '9px'
    '-webkit-border-radius': '9px'
    marginRight: '2px'
    marginTop: '3px'
    backgroundColor: $$.val() || 'transparent'
  ).ColorPicker(
    onChange: (hsb, hex, rgb) ->
      $$.val '#'+hex.toUpperCase()
      $picker.css 'background-color', '#'+hex
      $('div.colorpicker_submit').css 'border-color', '#'+hex
    onBeforeShow: ->
      color = $$.val().replace(/^#(.)(.)(.)$/, '#$1$1$2$2$3$3')
      $picker.ColorPickerSetColor color
      $('#'+$picker.data('colorpickerId')).addTouch()
      $('div.colorpicker_submit').css 'border-color', color
    onSubmit: ->
      $picker.ColorPickerHide()
  ).insertBefore($$.wrap('<nobr />'))
  $$.bind 'keyup', ->
    color = $$.val().replace(/^#(.)(.)(.)$/, '#$1$1$2$2$3$3')
    $$.ColorPickerSetColor color
    $picker.css 'background-color', color
    $('div.colorpicker_submit').css 'border-color', color
  return

gadgets.util.registerOnLoadHandler ->
  prefs = new gadgets.Prefs
  getPref = (key) -> gadgets.util.unescapeString(prefs.getString(key))
  myPrefs[key] = getPref(key) for own key of myPrefs

  gadgets.window.setTitle getPref("Title") || defaultTitle

  if $.browser.msie and Number($.browser.version) <= 8
    jQuery.ajaxSetup
      xhr: -> (
        new window.ActiveXObject "Msxml2.XMLHTTP"
      ) or (
        new window.ActiveXObject "Microsoft.XMLHTTP"
      )

  return doDisplayView() if $.browser.msie and Number($.browser.version) <= 6

  return if onLoadHandler?() == false

  $('#setup').bind 'pageshow', doInitPrefs

  $('a.save').click ->
    $('input[name], select[name]').each ->
      key = $(@).data('key')
      return unless key
      if $(@).attr('type') == 'checkbox'
        myPrefs[key] = if $(@).is(':checked') then 1 else 0
      else
        myPrefs[key] = $(@).val()
    onBeforeSave?()
    oldPrefs = $('#setup').data 'oldPrefs'
    finalize = ->
      $('#setup').data 'oldPrefs', null
      gadgets.window.adjustHeight 60
      doDisplayView()
    withInstance( ($$, $save) ->
      $form = $$.find 'form'
      for own key, val of myPrefs
        $form.find("input[name=#{key}], select[name=#{key}]").val val
      if window.parent.gadgets and window.parent.gadgets.container
        if $save.length
          $('#loading').show()
          gadgets.window.adjustHeight 60
          $save.click()
          return # skip finalization
        else
          window.parent.gadgets.container.save instanceId, $form.get(0)
      finalize()
    , ->
      for own key, val of myPrefs
        prefs.set key, val unless oldPrefs[key] == myPrefs[key]
      finalize()
    )
    return true

  $('a.cancel').click ->
    myPrefs = $('#setup').data('oldPrefs')
    $('#setup').data 'oldPrefs', null
    withInstance ($$, $save) -> if $save.length
      $('#loading').show()
      gadgets.window.adjustHeight 60
      $save.click()
      return
    return true

  $('a[href]').click ->
    $self = $(@)
    setTimeout ->
      $('#setup').show()
      $.mobile.changePage $self.attr('href')
        , $self.data('transition') || 'flip'
        , $self.data('direction') == 'reverse'
    , 100
    return false

  isPageWidgetSetupMode = false
  withInstance ($$, $save, $settings) ->
    # Hijack container's "Setup" icon
    $('a.save').text $save.val() if $save.length
    $settings.attr('onclick', '').unbind('click').click ->
      $('#link-setup').triggerHandler 'click'
    if $save.length and window.parent.parent and window.parent.parent.$
      $buttons = window.parent.parent.$('#st-widget-opensocial-setup-buttons')
      if $buttons.length and !$save.hasClass('hijacked')
        $save.addClass 'hijacked'
        $('a.save').click -> $buttons.show()
        $buttons.hide()
        $ -> $('#link-setup').triggerHandler('click')
        $('#link-setup').hide()
        isPageWidgetSetupMode = true
        return
    $('#link-setup').hide()
  return if isPageWidgetSetupMode

  if /\S/.test getPref('Workspace')
    $ -> doDisplayView()
  else
    $('#link-setup').triggerHandler 'click'
  return

