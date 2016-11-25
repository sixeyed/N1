import _ from 'underscore';
import React from 'react';
import ReactDOM from 'react-dom';
import Actions from '../flux/actions';
import RetinaImg from './retina-img';


class Modal extends React.Component {

  static propTypes = {
    className: React.PropTypes.string,
    children: React.PropTypes.element,
    height: React.PropTypes.number,
    width: React.PropTypes.number,
  };

  constructor(props) {
    super(props);
    this.state = {
      offset: 0,
      dimensions: {},
    };
  }

  componentDidMount() {
    this._focusImportantElement();
  }

  _focusImportantElement = () => {
    const modalNode = ReactDOM.findDOMNode(this);

    const focusable = modalNode.querySelectorAll("[tabIndex], input");
    const matches = _.sortBy(focusable, (node) => {
      if (node.tabIndex > 0) {
        return node.tabIndex;
      } else if (node.nodeName === "INPUT") {
        return 1000000
      }
      return 1000001
    })
    if (matches[0]) {
      matches[0].focus();
    }
  };

  _computeModalStyles = (height, width) => {
    const modalStyle = {
      top: "50%",
      left: "50%",
      margin: `-${height / 2}px 0 0 -${width / 2}px`,
      height: height,
      width: width,
      position: "absolute",
      backgroundColor: "white",
      boxShadow: "0 10px 20px rgba(0,0,0,0.19), inset 0 0 1px rgba(0,0,0,0.5)",
      borderRadius: "5px",
    };
    const containerStyle = {
      height: "100%",
      width: "100%",
      zIndex: 1000,
      position: "absolute",
      backgroundColor: "transparent",
    };
    return {containerStyle, modalStyle};
  };

  _onKeyDown = (event) => {
    if (event.key === "Escape") {
      Actions.closeModal();
    }
  };

  render() {
    const {children, height, width} = this.props;
    const {containerStyle, modalStyle} = this._computeModalStyles(height, width);

    return (
      <div
        style={containerStyle}
        className="modal-container"
        onKeyDown={this._onKeyDown}
        onClick={() => Actions.closeModal()}
      >
        <div
          className="modal nylas-modal-container"
          style={modalStyle}
          onClick={(event) => event.stopPropagation()}
        >
          <RetinaImg
            className="modal-close"
            style={{width: "14", WebkitFilter: "none", zIndex: "1", position: "relative"}}
            name="modal-close.png"
            mode={RetinaImg.Mode.ContentDark}
            onClick={(event) => {
              event.stopPropagation();
              Actions.closeModal();
            }}
          />
          {children}
        </div>
      </div>
    );
  }

}

export default Modal;
