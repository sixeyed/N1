import _ from 'underscore'
import {
  Utils,
  Thread,
  AccountStore,
  DatabaseStore,
  NylasSyncStatusStore,
  QuotedHTMLTransformer,
} from 'nylas-exports'

const INDEX_SIZE = 10000
const MAX_INDEX_SIZE = 30000
const CHUNKS_PER_ACCOUNT = 10
const INDEXING_WAIT = 1000
const MESSAGE_BODY_LENGTH = 50000
const INDEX_VERSION = 1

class ThreadSearchIndexStore {

  constructor() {
    this.unsubscribers = []
  }

  activate() {
    NylasSyncStatusStore.whenSyncComplete().then(() => {
      const date = Date.now()
      console.log('Thread Search: Initializing thread search index...')

      this.accountIds = _.pluck(AccountStore.accounts(), 'id')
      this.initializeIndex()
      .then(() => {
        NylasEnv.config.set('threadSearchIndexVersion', INDEX_VERSION)
        return Promise.resolve()
      })
      .then(() => {
        console.log(`Thread Search: Index built successfully in ${((Date.now() - date) / 1000)}s`)
        this.unsubscribers = [
          AccountStore.listen(this.onAccountsChanged),
          DatabaseStore.listen(this.onDataChanged),
        ]
      })
    })
  }

  /**
   * We only want to build the entire index if:
   * - It doesn't exist yet
   * - It is too big
   * - We bumped the index version
   *
   * Otherwise, we just want to index accounts that haven't been indexed yet.
   * An account may not have been indexed if it is added and the app is closed
   * before sync completes
   */
  initializeIndex() {
    if (NylasEnv.config.get('threadSearchIndexVersion') !== INDEX_VERSION) {
      return this.clearIndex()
      .then(() => this.buildIndex(this.accountIds))
    }

    return DatabaseStore.searchIndexSize(Thread)
    .then((size) => {
      console.log(`Thread Search: Current index size is ${(size || 0)} threads`)
      if (!size || size >= MAX_INDEX_SIZE || size === 0) {
        return this.clearIndex().thenReturn(this.accountIds)
      }
      return this.getUnindexedAccounts()
    })
    .then((accountIds) => this.buildIndex(accountIds))
  }

  /**
   * When accounts change, we are only interested in knowing if an account has
   * been added or removed
   *
   * - If an account has been added, we want to index its threads, but wait
   *   until that account has been successfully synced
   *
   * - If an account has been removed, we want to remove its threads from the
   *   index
   *
   * If the application is closed before sync is completed, the new account will
   * be indexed via `initializeIndex`
   */
  onAccountsChanged = () => {
    _.defer(() => {
      NylasSyncStatusStore.whenSyncComplete().then(() => {
        const latestIds = _.pluck(AccountStore.accounts(), 'id')
        if (_.isEqual(this.accountIds, latestIds)) {
          return;
        }
        const date = Date.now()
        console.log(`Thread Search: Updating thread search index for accounts ${latestIds}`)

        const newIds = _.difference(latestIds, this.accountIds)
        const removedIds = _.difference(this.accountIds, latestIds)
        const promises = []
        if (newIds.length > 0) {
          promises.push(this.buildIndex(newIds))
        }

        if (removedIds.length > 0) {
          promises.push(
            Promise.all(removedIds.map(id => DatabaseStore.unindexModelsForAccount(id, Thread)))
          )
        }
        this.accountIds = latestIds
        Promise.all(promises)
        .then(() => {
          console.log(`Thread Search: Index updated successfully in ${((Date.now() - date) / 1000)}s`)
        })
      })
    })
  }

  /**
   * When a thread gets updated we will update the search index with the data
   * from that thread if the account it belongs to is not being currently
   * synced.
   *
   * When the account is successfully synced, its threads will be added to the
   * index either via `onAccountsChanged` or via `initializeIndex` when the app
   * starts
   */
  onDataChanged = (change) => {
    if (change.objectClass !== Thread.name) {
      return;
    }
    _.defer(() => {
      const {objects, type} = change
      const {isSyncCompleteForAccount} = NylasSyncStatusStore
      const threads = objects.filter(({accountId}) => isSyncCompleteForAccount(accountId))

      let promises = []
      if (type === 'persist') {
        promises = threads.map(this.updateThreadIndex)
      } else if (type === 'unpersist') {
        promises = threads.map(this.unindexThread)
      }
      Promise.all(promises)
    })
  }

  buildIndex = (accountIds) => {
    if (!accountIds || accountIds.length === 0) { return Promise.resolve() }
    const sizePerAccount = Math.floor(INDEX_SIZE / accountIds.length)
    return Promise.resolve(accountIds)
    .each((accountId) => (
      this.indexThreadsForAccount(accountId, sizePerAccount)
    ))
  }

  clearIndex() {
    return (
      DatabaseStore.dropSearchIndex(Thread)
      .then(() => DatabaseStore.createSearchIndex(Thread))
    )
  }

  getUnindexedAccounts() {
    return Promise.resolve(this.accountIds)
    .filter((accId) => DatabaseStore.isIndexEmptyForAccount(accId, Thread))
  }

  indexThreadsForAccount(accountId, indexSize) {
    const chunkSize = Math.floor(indexSize / CHUNKS_PER_ACCOUNT)
    const chunks = Promise.resolve(_.times(CHUNKS_PER_ACCOUNT, () => chunkSize))

    return chunks.each((size, idx) => {
      return DatabaseStore.findAll(Thread)
      .where({accountId})
      .limit(size)
      .offset(size * idx)
      .order(Thread.attributes.lastMessageReceivedTimestamp.descending())
      .background()
      .then((threads) => {
        return Promise.all(
          threads.map(this.indexThread)
        ).then(() => {
          return new Promise((resolve) => setTimeout(resolve, INDEXING_WAIT))
        })
      })
    })
  }

  indexThread = (thread) => {
    return (
      this.getIndexData(thread)
      .then((indexData) => (
        DatabaseStore.indexModel(thread, indexData)
      ))
    )
  }

  updateThreadIndex = (thread) => {
    return (
      this.getIndexData(thread)
      .then((indexData) => (
        DatabaseStore.updateModelIndex(thread, indexData)
      ))
    )
  }

  unindexThread = (thread) => {
    return DatabaseStore.unindexModel(thread)
  }

  getIndexData(thread) {
    const messageBodies = (
      thread.messages()
      .then((messages) => (
        messages
        .map(({body, snippet}) => (
          !_.isString(body) ?
            {snippet} :
            {body: QuotedHTMLTransformer.removeQuotedHTML(body)}
        ))
        .map(({body, snippet}) => (
          snippet || Utils.extractTextFromHtml(body, {maxLength: MESSAGE_BODY_LENGTH}).replace(/(\s)+/g, ' ')
        ))
        .join(' ')
      ))
    )
    const participants = (
      thread.participants
      .map(({name, email}) => `${name} ${email}`)
      .join(" ")
    )

    return Promise.props({
      participants,
      body: messageBodies,
      subject: thread.subject,
    });
  }

  deactivate() {
    this.unsubscribers.forEach(unsub => unsub())
  }
}

export default new ThreadSearchIndexStore()
