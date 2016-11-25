Reflux = require 'reflux'
Actions = require('../src/flux/actions').default
Message = require('../src/flux/models/message').default
DatabaseStore = require('../src/flux/stores/database-store').default
AccountStore = require '../src/flux/stores/account-store'
ActionBridge = require('../src/flux/action-bridge').default
_ = require 'underscore'

ipc =
    on: ->
    send: ->

describe "ActionBridge", ->

  describe "in the work window", ->
    beforeEach ->
      spyOn(NylasEnv, "getWindowType").andReturn "default"
      spyOn(NylasEnv, "isWorkWindow").andReturn true
      @bridge = new ActionBridge(ipc)

    it "should have the role Role.WORK", ->
      expect(@bridge.role).toBe(ActionBridge.Role.WORK)

    it "should rebroadcast global actions", ->
      spyOn(@bridge, 'onRebroadcast')
      testAction = Actions[Actions.globalActions[0]]
      testAction('bla')
      expect(@bridge.onRebroadcast).toHaveBeenCalled()

    it "should rebroadcast when the DatabaseStore triggers", ->
      spyOn(@bridge, 'onRebroadcast')
      DatabaseStore.trigger({})
      expect(@bridge.onRebroadcast).toHaveBeenCalled()

    it "should not rebroadcast mainWindow actions since it is the main window", ->
      spyOn(@bridge, 'onRebroadcast')
      testAction = Actions.didMakeAPIRequest
      testAction('bla')
      expect(@bridge.onRebroadcast).not.toHaveBeenCalled()

    it "should not rebroadcast window actions", ->
      spyOn(@bridge, 'onRebroadcast')
      testAction = Actions[Actions.windowActions[0]]
      testAction('bla')
      expect(@bridge.onRebroadcast).not.toHaveBeenCalled()

  describe "in another window", ->
    beforeEach ->
      spyOn(NylasEnv, "getWindowType").andReturn "popout"
      spyOn(NylasEnv, "isWorkWindow").andReturn false
      @bridge = new ActionBridge(ipc)
      @message = new Message
        id: 'test-id'
        accountId: TEST_ACCOUNT_ID

    it "should have the role Role.SECONDARY", ->
      expect(@bridge.role).toBe(ActionBridge.Role.SECONDARY)

    it "should rebroadcast global actions", ->
      spyOn(@bridge, 'onRebroadcast')
      testAction = Actions[Actions.globalActions[0]]
      testAction('bla')
      expect(@bridge.onRebroadcast).toHaveBeenCalled()

    it "should rebroadcast mainWindow actions", ->
      spyOn(@bridge, 'onRebroadcast')
      testAction = Actions.didMakeAPIRequest
      testAction('bla')
      expect(@bridge.onRebroadcast).toHaveBeenCalled()

    it "should not rebroadcast window actions", ->
      spyOn(@bridge, 'onRebroadcast')
      testAction = Actions[Actions.windowActions[0]]
      testAction('bla')
      expect(@bridge.onRebroadcast).not.toHaveBeenCalled()

  describe "onRebroadcast", ->
    beforeEach ->
      spyOn(NylasEnv, "getWindowType").andReturn "popout"
      spyOn(NylasEnv, "isMainWindow").andReturn false
      @bridge = new ActionBridge(ipc)

    describe "when called with TargetWindows.ALL", ->
      it "should broadcast the action over IPC to all windows", ->
        spyOn(ipc, 'send')
        Actions.didPassivelyReceiveNewModels.firing = false
        @bridge.onRebroadcast(ActionBridge.TargetWindows.ALL, 'didPassivelyReceiveNewModels', [{oldModel: '1', newModel: 2}])
        expect(ipc.send).toHaveBeenCalledWith('action-bridge-rebroadcast-to-all', 'popout', 'didPassivelyReceiveNewModels', '[{"oldModel":"1","newModel":2}]')

    describe "when called with TargetWindows.WORK", ->
      it "should broadcast the action over IPC to the main window only", ->
        spyOn(ipc, 'send')
        Actions.didPassivelyReceiveNewModels.firing = false
        @bridge.onRebroadcast(ActionBridge.TargetWindows.WORK, 'didPassivelyReceiveNewModels', [{oldModel: '1', newModel: 2}])
        expect(ipc.send).toHaveBeenCalledWith('action-bridge-rebroadcast-to-work', 'popout', 'didPassivelyReceiveNewModels', '[{"oldModel":"1","newModel":2}]')

    it "should not do anything if the current invocation of the Action was triggered by itself", ->
      spyOn(ipc, 'send')
      Actions.didPassivelyReceiveNewModels.firing = true
      @bridge.onRebroadcast(ActionBridge.TargetWindows.ALL, 'didPassivelyReceiveNewModels', [{oldModel: '1', newModel: 2}])
      expect(ipc.send).not.toHaveBeenCalled()
