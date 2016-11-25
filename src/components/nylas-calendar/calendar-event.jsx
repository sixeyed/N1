import React from 'react'
import ReactDOM from 'react-dom'
import {Event} from 'nylas-exports'
import {InjectedComponentSet} from 'nylas-component-kit'
import {calcColor} from './calendar-helpers'

export default class CalendarEvent extends React.Component {
  static displayName = "CalendarEvent";

  static propTypes = {
    event: React.PropTypes.instanceOf(Event).isRequired,
    order: React.PropTypes.number,
    selected: React.PropTypes.bool,
    scopeEnd: React.PropTypes.number.isRequired,
    scopeStart: React.PropTypes.number.isRequired,
    direction: React.PropTypes.oneOf(['horizontal', 'vertical']),
    fixedSize: React.PropTypes.number,
    focused: React.PropTypes.bool,
    concurrentEvents: React.PropTypes.number,
    onClick: React.PropTypes.func,
    onDoubleClick: React.PropTypes.func,
    onFocused: React.PropTypes.func,
  }

  static defaultProps = {
    order: 1,
    direction: "vertical",
    fixedSize: -1,
    concurrentEvents: 1,
    onClick: () => {},
    onDoubleClick: () => {},
    onFocused: () => {},
  }

  componentDidMount() {
    this._scrollFocusedEventIntoView()
  }

  componentDidUpdate() {
    this._scrollFocusedEventIntoView()
  }

  _scrollFocusedEventIntoView() {
    const {focused} = this.props
    if (!focused) { return; }
    const eventNode = ReactDOM.findDOMNode(this)
    if (!eventNode) { return; }
    const {event, onFocused} = this.props
    eventNode.scrollIntoViewIfNeeded(true)
    onFocused(event)
  }

  _getDimensions() {
    const scopeLen = this.props.scopeEnd - this.props.scopeStart
    const duration = this.props.event.end - this.props.event.start;

    let top = Math.max((this.props.event.start - this.props.scopeStart) / scopeLen, 0);
    let height = Math.min((duration - this._overflowBefore()) / scopeLen, 1);

    let width = 1;
    let left;
    if (this.props.fixedSize === -1) {
      width = 1 / this.props.concurrentEvents;
      left = width * (this.props.order - 1);
      width = `${width * 100}%`;
      left = `${left * 100}%`;
    } else {
      width = this.props.fixedSize
      left = this.props.fixedSize * (this.props.order - 1);
    }

    top = `${top * 100}%`
    height = `${height * 100}%`

    return {left, width, height, top}
  }

  _getStyles() {
    let styles = {}
    if (this.props.direction === "vertical") {
      styles = this._getDimensions()
    } else if (this.props.direction === "horizontal") {
      const d = this._getDimensions()
      styles = {
        left: d.top,
        width: d.height,
        height: d.width,
        top: d.left,
      }
    }

    if (this.props.event.dragged) {
      styles.zIndex = 1;
    }

    const bgOpacity = this.props.event.hovered ? 1 : null;
    styles.backgroundColor = calcColor(this.props.event.calendarId, bgOpacity);

    return styles
  }

  _overflowBefore() {
    return Math.max(this.props.scopeStart - this.props.event.start, 0)
  }

  render() {
    const {direction, event, onClick, onDoubleClick, selected} = this.props;

    return (
      <div
        id={event.id}
        tabIndex={0}
        style={this._getStyles()}
        className={`calendar-event ${direction} ${selected ? 'selected' : null}`}
        onClick={(e) => onClick(e, event)}
        onDoubleClick={() => onDoubleClick(event)}
        data-id={event.id}
      >
        <div className="resize-handle top" />
        <span className="default-header" style={{order: 0}}>
          {event.displayTitle()}
        </span>
        <InjectedComponentSet
          className="event-injected-components"
          style={{position: "absolute"}}
          matching={{role: "Calendar:Event"}}
          exposedProps={{event: event}}
          direction="row"
        />
        <div className="resize-handle bottom" />
      </div>
    )
  }
}
