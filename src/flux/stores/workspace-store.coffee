_ = require 'underscore'
Actions = require('../actions').default
AccountStore = require './account-store'
CategoryStore = require './category-store'
MailboxPerspective = require '../../mailbox-perspective'
NylasStore = require 'nylas-store'

Sheet = {}
Location = {}

###
Public: The WorkspaceStore manages Sheets and layout modes in the application.
Observing the WorkspaceStore makes it easy to monitor the sheet stack. To learn
more about sheets and layout in N1, see the {InterfaceConcepts.md}
documentation.

Section: Stores
###
class WorkspaceStore extends NylasStore
  constructor: ->
    @_resetInstanceVars()
    @_preferredLayoutMode = NylasEnv.config.get('core.workspace.mode')

    @listenTo Actions.selectRootSheet, @_onSelectRootSheet
    @listenTo Actions.setFocus, @_onSetFocus
    @listenTo Actions.toggleWorkspaceLocationHidden, @_onToggleLocationHidden
    @listenTo Actions.popSheet, @popSheet
    @listenTo Actions.popToRootSheet, @popToRootSheet
    @listenTo Actions.pushSheet, @pushSheet

    {windowType} = NylasEnv.getLoadSettings()
    unless windowType is 'onboarding'
      require('electron').webFrame.setZoomLevelLimits(1, 1)
      NylasEnv.config.observe 'core.workspace.interfaceZoom', (z) =>
        require('electron').webFrame.setZoomFactor(z) if z and _.isNumber(z)

    if NylasEnv.isMainWindow()
      @_rebuildMenu()
      NylasEnv.commands.add(document.body, {
        'core:pop-sheet': => @popSheet()
        'application:select-list-mode' : => @_onSelectLayoutMode("list")
        'application:select-split-mode' : => @_onSelectLayoutMode("split")
      })


  _rebuildMenu: =>
    @_menuDisposable?.dispose()
    @_menuDisposable = NylasEnv.menu.add([
      {
        "label": "View",
        "submenu": [
          {
            "label": "Single Panel Mode",
            "type": "radio",
            "command": "application:select-list-mode",
            "checked": @_preferredLayoutMode is 'list',
            "position": "before=mailbox-navigation"
          },
          {
            "label": "Two Panel Mode",
            "type": "radio",
            "command": "application:select-split-mode",
            "checked": @_preferredLayoutMode is 'split'
            "position": "before=mailbox-navigation"
          }
        ]
      }
    ])

  _resetInstanceVars: =>
    @Location = Location = {}
    @Sheet = Sheet = {}

    @_hiddenLocations = NylasEnv.config.get('core.workspace.hiddenLocations') || {}
    @_sheetStack = []

    if NylasEnv.isMainWindow()
      @defineSheet 'Global'
      @defineSheet 'Threads', {root: true},
        list: ['RootSidebar', 'ThreadList']
        split: ['RootSidebar', 'ThreadList', 'MessageList', 'MessageListSidebar']
      @defineSheet 'Thread', {},
        list: ['MessageList', 'MessageListSidebar']
    else
      @defineSheet 'Global'

  ###
  Inbound Events
  ###

  _onSelectRootSheet: (sheet) =>
    if not sheet
      throw new Error("Actions.selectRootSheet - #{sheet} is not a valid sheet.")
    if not sheet.root
      throw new Error("Actions.selectRootSheet - #{sheet} is not registered as a root sheet.")

    @_sheetStack = []
    @_sheetStack.push(sheet)
    @trigger(@)

  _onToggleLocationHidden: (location) =>
    if not location.id
      throw new Error("Actions.toggleWorkspaceLocationHidden - pass a WorkspaceStore.Location")

    if @_hiddenLocations[location.id]
      if location is @Location.MessageListSidebar
        Actions.recordUserEvent("Sidebar Opened")
      delete @_hiddenLocations[location.id]
    else
      if location is @Location.MessageListSidebar
        Actions.recordUserEvent("Sidebar Closed")
      @_hiddenLocations[location.id] = location

    NylasEnv.config.set('core.workspace.hiddenLocations', @_hiddenLocations)

    @trigger(@)

  _onSetFocus: ({collection, item}) =>
    if collection is 'thread'
      if @layoutMode() is 'list'
        if item and @topSheet() isnt Sheet.Thread
          @pushSheet(Sheet.Thread)
        if not item and @topSheet() is Sheet.Thread
          @popSheet()

    if collection is 'file'
      if @layoutMode() is 'list'
        if item and @topSheet() isnt Sheet.File
          @pushSheet(Sheet.File)
        if not item and @topSheet() is Sheet.File
          @popSheet()

  _onSelectLayoutMode: (mode) =>
    return if mode is @_preferredLayoutMode
    @_preferredLayoutMode = mode
    NylasEnv.config.set('core.workspace.mode', @_preferredLayoutMode)
    @_rebuildMenu()
    @popToRootSheet()
    @trigger()

  ###
  Accessing Data
  ###

  # Returns a {String}: The current layout mode. Either `split` or `list`
  #
  layoutMode: =>
    root = @rootSheet()
    if not root
      'list'
    else if @_preferredLayoutMode in root.supportedModes
      @_preferredLayoutMode
    else
      root.supportedModes[0]

  preferredLayoutMode: =>
    @_preferredLayoutMode

  # Public: Returns The top {Sheet} in the current stack. Use this method to determine
  # the sheet the user is looking at.
  #
  topSheet: =>
    @_sheetStack[@_sheetStack.length - 1]

  # Public: Returns The {Sheet} at the root of the current stack.
  #
  rootSheet: =>
    @_sheetStack[0]

  # Public: Returns an {Array<Sheet>} The stack of sheets
  #
  sheetStack: =>
    @_sheetStack

  # Public: Returns an {Array} of locations that have been hidden.
  #
  hiddenLocations: =>
    _.values(@_hiddenLocations)

  # Public: Returns a {Boolean} indicating whether the location provided is hidden.
  # You should provide one of the WorkspaceStore.Location constant values.
  isLocationHidden: (loc) =>
    return false unless loc
    @_hiddenLocations[loc.id]?


  ###
  Managing Sheets
  ###

  # * `id` {String} The ID of the Sheet being defined.
  # * `options` {Object} If the sheet should be listed in the left sidebar,
  #      pass `{root: true, name: 'Label'}`.
  # *`columns` An {Object} with keys for each layout mode the Sheet
  #      supports. For each key, provide an array of column names.
  #
  defineSheet: (id, options = {}, columns = {}) =>
    # Make sure all the locations have definitions so that packages
    # can register things into these locations and their toolbars.
    for layout, cols of columns
      for col, idx in cols
        Location[col] ?= {id: "#{col}", Toolbar: {id: "#{col}:Toolbar"}}
        cols[idx] = Location[col]

    Sheet[id] =
      id: id
      columns: columns
      supportedModes: Object.keys(columns)

      icon: options.icon
      name: options.name
      root: options.root
      sidebarComponent: options.sidebarComponent

      Toolbar:
        Left: {id: "Sheet:#{id}:Toolbar:Left"}
        Right: {id: "Sheet:#{id}:Toolbar:Right"}
      Header: {id: "Sheet:#{id}:Header"}
      Footer: {id: "Sheet:#{id}:Footer"}

    if (options.root and not @rootSheet()) and not options.silent
      @_onSelectRootSheet(Sheet[id])

    @triggerDebounced()

  undefineSheet: (id) =>
    delete Sheet[id]
    @triggerDebounced()

  # Push the sheet on top of the current sheet, with a quick animation.
  # A back button will appear in the top left of the pushed sheet.
  # This method triggers, allowing observers to update.
  #
  # * `sheet` The {Sheet} type to push onto the stack.
  #
  pushSheet: (sheet) =>
    @_sheetStack.push(sheet)
    @trigger()

  # Remove the top sheet, with a quick animation. This method triggers,
  # allowing observers to update.
  popSheet: =>
    sheet = @topSheet()

    if @_sheetStack.length > 1
      @_sheetStack.pop()
      @trigger()

    if Sheet.Thread and sheet is Sheet.Thread
      Actions.setFocus(collection: 'thread', item: null)

  # Return to the root sheet. This method triggers, allowing observers
  # to update.
  popToRootSheet: =>
    if @_sheetStack.length > 1
      @_sheetStack.length = 1
      @trigger()

  triggerDebounced: _.debounce(( -> @trigger(@)), 1)

module.exports = new WorkspaceStore()
