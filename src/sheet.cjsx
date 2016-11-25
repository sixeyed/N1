React = require 'react'
_ = require 'underscore'
{Actions,ComponentRegistry, WorkspaceStore} = require "nylas-exports"
RetinaImg = require('./components/retina-img').default
Flexbox = require('./components/flexbox').default
InjectedComponentSet = require './components/injected-component-set'
ResizableRegion = require './components/resizable-region'

FLEX = 10000

class Sheet extends React.Component
  @displayName = 'Sheet'

  @propTypes =
    data: React.PropTypes.object.isRequired
    depth: React.PropTypes.number.isRequired
    onColumnSizeChanged: React.PropTypes.func

  @defaultProps:
    onColumnSizeChanged: ->

  @childContextTypes:
    sheetDepth: React.PropTypes.number

  getChildContext: =>
    sheetDepth: @props.depth

  constructor: (@props) ->
    @state = @_getStateFromStores()

  componentDidMount: =>
    @unlisteners ?= []
    @unlisteners.push ComponentRegistry.listen (event) =>
      @setState(@_getStateFromStores())
    @unlisteners.push WorkspaceStore.listen (event) =>
      @setState(@_getStateFromStores())

  componentDidUpdate: =>
    @props.onColumnSizeChanged(@)
    minWidth = 0
    minWidth += col.minWidth for col in @state.columns
    NylasEnv.setMinimumWidth(minWidth)

  shouldComponentUpdate: (nextProps, nextState) =>
    not _.isEqual(nextProps, @props) or not _.isEqual(nextState, @state)

  componentWillUnmount: =>
    unlisten() for unlisten in @unlisteners

  render: =>
    style =
      position:'absolute'
      width:'100%'
      height:'100%'
      zIndex: 1

    # Note - setting the z-index of the sheet is important, even though it's
    # always 1. Assigning a z-index creates a "stacking context" in the browser,
    # so z-indexes inside the sheet are relative to each other, but something in
    # one sheet cannot be on top of something in another sheet.
    # http://philipwalton.com/articles/what-no-one-told-you-about-z-index/

    <div name={"Sheet"}
         style={style}
         className={"sheet mode-#{@state.mode}"}
         data-id={@props.data.id}>
      <Flexbox direction="row" style={overflow: 'hidden'}>
        {@_columnFlexboxElements()}
      </Flexbox>
    </div>

  _columnFlexboxElements: =>
    @state.columns.map (column, idx) =>
      {maxWidth, minWidth, handle, location, width} = column
      if minWidth != maxWidth and maxWidth < FLEX
        <ResizableRegion
          key={"#{@props.data.id}:#{idx}"}
          name={"#{@props.data.id}:#{idx}"}
          className={"column-#{location.id}"}
          style={height:'100%'}
          data-column={idx}
          onResize={@_onColumnResize.bind(@, column)}
          initialWidth={width}
          minWidth={minWidth}
          maxWidth={maxWidth}
          handle={handle}>
          <InjectedComponentSet direction="column" matching={location: location, mode: @state.mode}/>
        </ResizableRegion>
      else
        style =
          height: '100%'
          minWidth: minWidth
          overflow: 'hidden'
        if maxWidth < FLEX
          style.width = maxWidth
        else
          style.flex = 1
        <InjectedComponentSet direction="column"
                              key={"#{@props.data.id}:#{idx}"}
                              name={"#{@props.data.id}:#{idx}"}
                              className={"column-#{location.id}"}
                              data-column={idx}
                              style={style}
                              matching={location: location, mode: @state.mode}/>

  _onColumnResize: (column, width) =>
    NylasEnv.storeColumnWidth(id: column.location.id, width: width)
    @props.onColumnSizeChanged(@)

  _getStateFromStores: =>
    state =
      mode: WorkspaceStore.layoutMode()
      columns: []

    widest = -1
    widestWidth = -1

    if @props.data?.columns[state.mode]?
      for location, idx in @props.data.columns[state.mode]
        continue if WorkspaceStore.isLocationHidden(location)
        entries = ComponentRegistry.findComponentsMatching({location: location, mode: state.mode})
        maxWidth = _.reduce entries, ((m,component) -> Math.min(component.containerStyles?.maxWidth ? 10000, m)), 10000
        minWidth = _.reduce entries, ((m,component) -> Math.max(component.containerStyles?.minWidth ? 0, m)), 0
        width = NylasEnv.getColumnWidth(location.id)
        col = {maxWidth, minWidth, location, width}
        state.columns.push(col)

        if maxWidth > widestWidth
          widestWidth = maxWidth
          widest = idx

    if state.columns.length > 0
      # Once we've accumulated all the React components for the columns,
      # ensure that at least one column has a huge max-width so that the columns
      # expand to fill the window. This may make items in the column unhappy, but
      # we pick the column with the highest max-width so the effect is minimal.
      state.columns[widest].maxWidth = FLEX

      # Assign flexible edges based on whether items are to the left or right
      # of the flexible column (which has no edges)
      state.columns[i].handle = ResizableRegion.Handle.Right for i in [0..widest-1] by 1
      state.columns[i].handle = ResizableRegion.Handle.Left  for i in [widest..state.columns.length-1] by 1
    state

  _pop: =>
    Actions.popSheet()

module.exports = Sheet
