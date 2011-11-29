if (!window.Event) {
  var Event = new Object();
}

Object.extend(Event, {
  KEY_BACKSPACE: 8,
  KEY_TAB:       9,
  KEY_RETURN:   13,
  KEY_ESC:      27,
  KEY_LEFT:     37,
  KEY_UP:       38,
  KEY_RIGHT:    39,
  KEY_DOWN:     40,
  KEY_DELETE:   46,

  element: function(event) {
    return event.target || event.srcElement;
  },

  isLeftClick: function(event) {
    return (((event.which) && (event.which == 1)) ||
            ((event.button) && (event.button == 1)));
  },

  pointerX: function(event) {
    return event.pageX || (event.clientX + 
      (document.documentElement.scrollLeft || document.body.scrollLeft));
  },

  pointerY: function(event) {
    return event.pageY || (event.clientY + 
      (document.documentElement.scrollTop || document.body.scrollTop));
  },

  stop: function(event) {
    if (event.preventDefault) { 
      event.preventDefault(); 
      event.stopPropagation(); 
    } else {
      event.returnValue = false;
      event.cancelBubble = true;
    }
  },

  // find the first node with the given tagName, starting from the
  // node the event was triggered on; traverses the DOM upwards
  findElement: function(event, tagName) {
    var element = Event.element(event);
    while (element.parentNode && (!element.tagName ||
        (element.tagName.toUpperCase() != tagName.toUpperCase())))
      element = element.parentNode;
    return element;
  },

  observers: false,

  // This contains a list of two element arrays, where the first
  // element of each array is the original observer function and
  // the second element is a closure containing the original
  // observer function.
  observers_to_wrapped_observers_map: [],

  _lookupWrappedObserver: function(observer) {
    var l = this.observers_to_wrapped_observers_map.length;
    for (var i = 0; i < l; ++i) {
      if (observer == this.observers_to_wrapped_observers_map[i][0]) {
        return this.observers_to_wrapped_observers_map[i][1];
      }
    }
    return observer;
  },

  _indexOfWrappedObserver: function(observer) {
    var l = this.observers_to_wrapped_observers_map.length;
    for (var i = 0; i < l; ++i) {
      if (this.observers_to_wrapped_observers_map[i][0] == observer) {
        return i;
      }
    }
    return null;
  },

  _removeWrappedObserver: function(i) {
    this.observers_to_wrapped_observers_map[i][0] = null;
    this.observers_to_wrapped_observers_map[i][1] = null;
    this.observers_to_wrapped_observers_map.splice(i, 1);
  },

  _buildWrappedObserver: function(element, name, observer) {
    if (window != element && 'unload' != name) {
      return observer;
    }

    var i = this._indexOfWrappedObserver(observer);
    if (null != i) {
      return this.observers_to_wrapped_observers_map[i][1];
    }

    var wrapped_observer = function() {
      observer();
      var i = Event._indexOfWrappedObserver(observer);
      Event._removeWrappedObserver(i);
      if (0 == Event.observers_to_wrapped_observers_map.length) {
        Event.unloadCache();
      }
    };
    this.observers_to_wrapped_observers_map.push([observer, wrapped_observer]);
    wrapped_observer = null;
    var l = this.observers_to_wrapped_observers_map.length;
    return this.observers_to_wrapped_observers_map[l-1][1];
  },

  _observeAndCache: function(element, name, observer, useCapture) {
    if (!this.observers) this.observers = [];

    observer = this._buildWrappedObserver(element, name, observer);

    if (element.addEventListener) {
      this.observers.push([element, name, observer, useCapture]);
      element.addEventListener(name, observer, useCapture);
    } else if (element.attachEvent) {
      this.observers.push([element, name, observer, useCapture]);
      element.attachEvent('on' + name, observer);
    }
  },
  
  unloadCache: function() {
    if (!Event.observers) return;
    for (var i = 0; i < Event.observers.length; i++) {
      Event.stopObserving.apply(this, Event.observers[i]);
      Event.observers[i][0] = null;
    }
    Event.observers = false;

    while (Event.observers_to_wrapped_observers_map.length > 0) {
      Event._removeWrappedObserver(0);
    }
  },

  observe: function(element, name, observer, useCapture) {
    var element = $(element);
    useCapture = useCapture || false;
    
    if (name == 'keypress' &&
        (navigator.appVersion.match(/Konqueror|Safari|KHTML/)
        || element.attachEvent))
      name = 'keydown';
    
    this._observeAndCache(element, name, observer, useCapture);
  },

  stopObserving: function(element, name, observer, useCapture) {
    var element = $(element);
    useCapture = useCapture || false;

    if (window == element && 'unload' == name) {
      var i = Event._indexOfWrappedObserver(observer);
      if (null != i) {
        observer = this.observers_to_wrapped_observers_map[i][1];
        Event._removeWrappedObserver(i);
      }
    }
    
    if (name == 'keypress' &&
        (navigator.appVersion.match(/Konqueror|Safari|KHTML/)
        || element.detachEvent))
      name = 'keydown';
    
    if (element.removeEventListener) {
      element.removeEventListener(name, observer, useCapture);
    } else if (element.detachEvent) {
      element.detachEvent('on' + name, observer);
    }
  }
});

/* prevent memory leaks in IE */
if (navigator.appVersion.match(/\bMSIE\b/))
    Event.observe(window, 'unload', Prototype.emptyFunction, false);
