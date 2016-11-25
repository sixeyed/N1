NylasStore = require 'nylas-store'
Rx = require 'rx-lite'
_ = require 'underscore'
{Message,
 OutboxStore,
 AccountStore,
 MutableQueryResultSet,
 MutableQuerySubscription,
 ObservableListDataSource,
 FocusedPerspectiveStore,
 DatabaseStore} = require 'nylas-exports'
{ListTabular} = require 'nylas-component-kit'

class DraftListStore extends NylasStore
  constructor: ->
    @listenTo FocusedPerspectiveStore, @_onPerspectiveChanged
    @_createListDataSource()

  dataSource: =>
    @_dataSource

  selectionObservable: =>
    return Rx.Observable.fromListSelection(@)

  # Inbound Events

  _onPerspectiveChanged: =>
    @_createListDataSource()

  # Internal

  _createListDataSource: =>
    mailboxPerspective = FocusedPerspectiveStore.current()

    if mailboxPerspective.drafts
      query = DatabaseStore.findAll(Message)
        .include(Message.attributes.body)
        .order(Message.attributes.date.descending())
        .where(draft: true)
        .page(0, 1)

      # Adding a "account_id IN (a,b,c)" clause to our query can result in a full
      # table scan. Don't add the where clause if we know we want results from all.
      if mailboxPerspective.accountIds.length < AccountStore.accounts().length
        query.where(accountId: mailboxPerspective.accountIds)

      subscription = new MutableQuerySubscription(query, {emitResultSet: true})
      $resultSet = Rx.Observable.fromNamedQuerySubscription('draft-list', subscription)
      $resultSet = Rx.Observable.combineLatest [
        $resultSet,
        Rx.Observable.fromStore(OutboxStore)
      ], (resultSet, outbox) =>

        # Generate a new result set that includes additional information on
        # the draft objects. This is similar to what we do in the thread-list,
        # where we set thread.__messages to the message array.
        resultSetWithTasks = new MutableQueryResultSet(resultSet)

        mailboxPerspective.accountIds.forEach (aid) =>
          OutboxStore.itemsForAccount(aid).forEach (task) =>
            draft = resultSet.modelWithId(task.draftClientId)
            if draft
              draft = draft.clone()
              draft.uploadTaskId = task.id
              draft.uploadProgress = task.progress
              resultSetWithTasks.updateModel(draft)

        return resultSetWithTasks.immutableClone()

      @_dataSource = new ObservableListDataSource($resultSet, subscription.replaceRange)
    else
      @_dataSource = new ListTabular.DataSource.Empty()

    @trigger(@)

module.exports = new DraftListStore()
