import _ from 'underscore'
import {AccountStore, TaskFactory, MailboxPerspective} from 'nylas-exports'
import SearchQuerySubscription from './search-query-subscription'


class SearchMailboxPerspective extends MailboxPerspective {

  constructor(accountIds, searchQuery) {
    super(accountIds)
    this.searchQuery = searchQuery
    this.name = 'Search'

    if (!_.isString(this.searchQuery)) {
      throw new Error("SearchMailboxPerspective: Expected a `string` search query")
    }
  }

  emptyMessage() {
    return "No search results available"
  }

  isEqual(other) {
    return super.isEqual(other) && other.searchQuery === this.searchQuery
  }

  threads() {
    return new SearchQuerySubscription(this.searchQuery, this.accountIds)
  }

  canReceiveThreadsFromAccountIds() {
    return false
  }

  tasksForRemovingItems(threads) {
    return TaskFactory.tasksForApplyingCategories({
      threads: threads,
      categoriesToAdd: (accountId) => {
        const account = AccountStore.accountForId(accountId)
        return [account.defaultFinishedCategory()]
      },
    })
  }
}

export default SearchMailboxPerspective;
