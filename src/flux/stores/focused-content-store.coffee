_ = require 'underscore'
Reflux = require 'reflux'
AccountStore = require './account-store'
WorkspaceStore = require './workspace-store'
DatabaseStore = require('./database-store').default
FocusedPerspectiveStore = require('./focused-perspective-store').default
MailboxPerspective = require '../../mailbox-perspective'
Actions = require('../actions').default
Thread = require('../models/thread').default
Model = require '../models/model'

{Listener, Publisher} = require '../modules/reflux-coffee'
CoffeeHelpers = require '../coffee-helpers'

###
Public: The FocusedContentStore provides access to the objects currently selected
or otherwise focused in the window. Normally, focus would be maintained internally
by components that show models. The FocusedContentStore makes the concept of
selection public so that you can observe focus changes and trigger your own changes
to focus.

Since {FocusedContentStore} is a Flux-compatible Store, you do not call setters
on it directly. Instead, use {Actions::setFocus} or
{Actions::setCursorPosition} to set focus. The FocusedContentStore observes
these models, changes it's state, and broadcasts to it's observers.

Note: The {FocusedContentStore} triggers when a focused model is changed, even if
it's ID has not. For example, if the user has a {Thread} selected and removes a tag,
{FocusedContentStore} will trigger so you can fetch the new version of the
{Thread}. If you observe the {FocusedContentStore} properly, you should always
have the latest version of the the selected object.

**Standard Collections**:

   - thread
   - file

**Example: Observing the Selected Thread**

```coffeescript
@unsubscribe = FocusedContentStore.listen(@_onFocusChanged, @)

...

# Called when focus has changed, or when the focused model has been modified.
_onFocusChanged: ->
  thread = FocusedContentStore.focused('thread')
  if thread
    console.log("#{thread.subject} is selected!")
  else
    console.log("No thread is selected!")
```

Section: Stores
###
class FocusedContentStore
  @include: CoffeeHelpers.includeModule

  @include Publisher
  @include Listener

  constructor: ->
    @_resetInstanceVars()
    @listenTo AccountStore, @_onAccountsChange
    @listenTo WorkspaceStore, @_onWorkspaceChange
    @listenTo DatabaseStore, @_onDataChange
    @listenTo Actions.setFocus, @_onFocus
    @listenTo Actions.setCursorPosition, @_onFocusKeyboard

  triggerAfterAnimationFrame: (payload) =>
    window.requestAnimationFrame =>
      @trigger(payload)

  _resetInstanceVars: =>
    @_focused = {}
    @_focusedUsingClick = {}
    @_keyboardCursor = {}
    @_keyboardCursorEnabled = WorkspaceStore.layoutMode() is 'list'

  # Inbound Events

  _onAccountsChange: =>
    # Ensure internal consistency by removing any focused items that belong
    # to accounts which no longer exist.
    changed = []

    for dict in [@_focused, @_keyboardCursor]
      for collection, item of dict
        if item and item.accountId and !AccountStore.accountForId(item.accountId)
          delete dict[collection]
          changed.push(collection)

    if changed.length > 0
      @trigger({ impactsCollection: (c) -> changed.includes(c) })

  _onFocusKeyboard: ({collection, item}) =>
    throw new Error("focusKeyboard() requires a Model or null") if item and not (item instanceof Model)
    throw new Error("focusKeyboard() requires a collection") unless collection
    return if @_keyboardCursor[collection]?.id is item?.id

    @_keyboardCursor[collection] = item
    @triggerAfterAnimationFrame({ impactsCollection: (c) -> c is collection })

  _onFocus: ({collection, item, usingClick}) =>
    throw new Error("focus() requires a Model or null") if item and not (item instanceof Model)
    throw new Error("focus() requires a collection") unless collection
    return if @_focused[collection]?.id is item?.id

    @_focused[collection] = item
    @_focusedUsingClick[collection] = usingClick
    @_keyboardCursor[collection] = item if item
    @triggerAfterAnimationFrame({ impactsCollection: (c) -> c is collection })

  _onWorkspaceChange: =>
    keyboardCursorEnabled = WorkspaceStore.layoutMode() is 'list'

    if keyboardCursorEnabled isnt @_keyboardCursorEnabled
      @_keyboardCursorEnabled = keyboardCursorEnabled

      if keyboardCursorEnabled
        for collection, item of @_focused
          @_keyboardCursor[collection] = item
        @_focused = {}
      else
        for collection, item of @_keyboardCursor
          @_onFocus({collection, item})

    @trigger({ impactsCollection: -> true })

  _onDataChange: (change) =>
    # If one of the objects we're storing in our focused or keyboard cursor
    # dictionaries has changed, we need to let our observers know, since they
    # may now be holding on to outdated data.
    return unless change and change.objectClass

    touched = []

    for data in [@_focused, @_keyboardCursor]
      for key, val of data
        continue unless val and val.constructor.name is change.objectClass
        for obj in change.objects
          if val.id is obj.id
            if change.type is 'unpersist'
              data[key] = null
            else
              data[key] = obj
            touched.push(key)

    if touched.length > 0
      @trigger({ impactsCollection: (c) -> c in touched })

  # Public Methods

  ###
  Public: Returns the focused {Model} in the collection specified,
  or undefined if no item is focused.

  - `collection` The {String} name of a collection. Standard collections are
    listed above.
  ###
  focused: (collection) =>
    @_focused[collection]

  ###
  Public: Returns the ID of the focused {Model} in the collection specified,
  or undefined if no item is focused.

  - `collection` The {String} name of a collection. Standard collections are
    listed above.
  ###
  focusedId: (collection) =>
    @_focused[collection]?.id

  ###
  Public: Returns true if the item for the collection was focused via a click or
  false otherwise.

  - `collection` The {String} name of a collection. Standard collections are
    listed above.
  ###
  didFocusUsingClick: (collection) =>
    @_focusedUsingClick[collection] ? false

  ###
  Public: Returns the {Model} the keyboard is currently focused on
  in the collection specified. Keyboard focus is not always separate from
  primary focus (selection). You can use {::keyboardCursorEnabled} to determine
  whether keyboard focus is enabled.

  - `collection` The {String} name of a collection. Standard collections are
    listed above.
  ###
  keyboardCursor: (collection) =>
    @_keyboardCursor[collection]

  ###
  Public: Returns the ID of the {Model} the keyboard is currently focused on
  in the collection specified. Keyboard focus is not always separate from
  primary focus (selection). You can use {::keyboardCursorEnabled} to determine
  whether keyboard focus is enabled.

  - `collection` The {String} name of a collection. Standard collections are
    listed above.
  ###
  keyboardCursorId: (collection) =>
    @_keyboardCursor[collection]?.id

  ###
  Public: Returns a {Boolean} - `true` if the keyboard cursor concept applies in
  the current {WorkspaceStore} layout mode. The keyboard cursor is currently only
  enabled in `list` mode.
  ###
  keyboardCursorEnabled: =>
    @_keyboardCursorEnabled


module.exports = new FocusedContentStore()
