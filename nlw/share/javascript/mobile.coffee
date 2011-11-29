$(document).bind "mobileinit", ->
  Socialtext?.mobile = true
  isGradeA = $.support.mediaquery and ($.browser.webkit or $.browser.mozilla)

  $.extend $.mobile,
    defaultTransition: "fade"
    ajaxEnabled: false
    ajaxFormsEnabled: false
    ajaxLinksEnabled: false
    hashListeningEnabled: false
    gradeA: -> isGradeA
  
  if isGradeA
    $(".ui-btn").live click: ->
      theme = $(@).attr("data-theme")
      $(@).removeClass("ui-btn-up-" + theme).addClass "ui-btn-down-" + theme
