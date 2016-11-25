_ = require 'underscore'
{Actions,
 SyncbackCategoryTask,
 DestroyCategoryTask,
 CategoryStore,
 Category,
 ExtensionRegistry,
 RegExpUtils} = require 'nylas-exports'
SidebarItem = require './sidebar-item'
SidebarActions = require './sidebar-actions'

isSectionCollapsed = (title) ->
  if NylasEnv.savedState.sidebarKeysCollapsed[title] isnt undefined
    NylasEnv.savedState.sidebarKeysCollapsed[title]
  else
    false

toggleSectionCollapsed = (section) ->
  return unless section
  SidebarActions.setKeyCollapsed(section.title, not isSectionCollapsed(section.title))

class SidebarSection

  @empty: (title) ->
    return {
      title,
      items: []
    }

  @standardSectionForAccount: (account) ->
    if not account
      throw new Error("standardSectionForAccount: You must pass an account.")

    cats = CategoryStore.standardCategories(account)
    return @empty(account.label) if cats.length is 0

    items = _
      .reject(cats, (cat) -> cat.name is 'drafts')
      .map (cat) => SidebarItem.forCategories([cat], editable: false, deletable: false)

    unreadItem = SidebarItem.forUnread([account.id])
    starredItem = SidebarItem.forStarred([account.id])
    draftsItem = SidebarItem.forDrafts([account.id])
    snoozedItem = SidebarItem.forSnoozed([account.id])

    extensionItems = ExtensionRegistry.AccountSidebar.extensions()
    .filter((ext) => ext.sidebarItem?)
    .map((ext) => ext.sidebarItem([account.id]))
    .map(({id, name, iconName, perspective}) =>
      SidebarItem.forPerspective(id, perspective, {name, iconName})
    )

    # Order correctly: Inbox, Unread, Starred, rest... , Drafts
    items.splice(1, 0, unreadItem, starredItem, snoozedItem, extensionItems...)
    items.push(draftsItem)

    return {
      title: account.label
      items: items
    }

  @standardSectionForAccounts: (accounts) ->
    return @empty('All Accounts') if not accounts or accounts.length is 0
    return @empty('All Accounts') if CategoryStore.categories().length is 0
    return @standardSectionForAccount(accounts[0]) if accounts.length is 1

    standardNames = [
      'inbox',
      'important'
      'sent',
      ['archive', 'all'],
      'spam'
      'trash'
    ]
    items = []

    for names in standardNames
      names = if Array.isArray(names) then names else [names]
      categories = CategoryStore.getStandardCategories(accounts, names...)
      continue if categories.length is 0

      children = []
      accounts.forEach (acc) ->
        cat = _.first(_.compact(
          names.map((name) -> CategoryStore.getStandardCategory(acc, name))
        ))
        return unless cat
        children.push(SidebarItem.forCategories([cat], name: acc.label, editable: false, deletable: false))

      items.push SidebarItem.forCategories(categories, {children, editable: false, deletable: false})

    accountIds = _.pluck(accounts, 'id')

    starredItem = SidebarItem.forStarred(accountIds,
      children: accounts.map (acc) -> SidebarItem.forStarred([acc.id], name: acc.label)
    )
    unreadItem = SidebarItem.forUnread(accountIds,
      children: accounts.map (acc) -> SidebarItem.forUnread([acc.id], name: acc.label)
    )
    draftsItem = SidebarItem.forDrafts(accountIds,
      children: accounts.map (acc) -> SidebarItem.forDrafts([acc.id], name: acc.label)
    )
    snoozedItem = SidebarItem.forSnoozed(accountIds,
      children: accounts.map (acc) -> SidebarItem.forSnoozed([acc.id], name: acc.label)
    )

    extensionItems =  ExtensionRegistry.AccountSidebar.extensions()
    .filter((ext) => ext.sidebarItem?)
    .map((ext) =>
      {id, name, iconName, perspective} = ext.sidebarItem(accountIds)
      return SidebarItem.forPerspective(id, perspective, {
        name,
        iconName,
        children: accounts.map((acc) =>
          subItem = ext.sidebarItem([acc.id])
          return SidebarItem.forPerspective(
            subItem.id + "-#{acc.id}",
            subItem.perspective,
            {name: acc.label, iconName: subItem.iconName}
          )
        )
      })
    )

    # Order correctly: Inbox, Unread, Starred, rest... , Drafts
    items.splice(1, 0, unreadItem, starredItem, snoozedItem, extensionItems...)
    items.push(draftsItem)

    return {
      title: 'All Accounts'
      items: items
    }


  @forUserCategories: (account, {title, collapsible} = {}) ->
    return unless account
    # Compute hierarchy for user categories using known "path" separators
    # NOTE: This code uses the fact that userCategoryItems is a sorted set, eg:
    #
    # Inbox
    # Inbox.FolderA
    # Inbox.FolderA.FolderB
    # Inbox.FolderB
    #
    items = []
    seenItems = {}
    for category in CategoryStore.userCategories(account)
      # https://regex101.com/r/jK8cC2/1
      re = RegExpUtils.subcategorySplitRegex()
      itemKey = category.displayName.replace(re, '/')

      parent = null
      parentComponents = itemKey.split('/')
      for i in [parentComponents.length..1] by -1
        parentKey = parentComponents[0...i].join('/')
        parent = seenItems[parentKey]
        break if parent

      if parent
        itemDisplayName = category.displayName.substr(parentKey.length+1)
        item = SidebarItem.forCategories([category], name: itemDisplayName)
        parent.children.push(item)
      else
        item = SidebarItem.forCategories([category])
        items.push(item)
      seenItems[itemKey] = item


    title ?= account.categoryLabel()
    collapsed = isSectionCollapsed(title)
    if collapsible
      onCollapseToggled = toggleSectionCollapsed

    return {
      title: title
      iconName: account.categoryIcon()
      items: items
      collapsed: collapsed
      onCollapseToggled: onCollapseToggled
      onItemCreated: (displayName) ->
        return unless displayName
        category = new Category
          displayName: displayName
          accountId: account.id
        Actions.queueTask(new SyncbackCategoryTask({category}))
    }


module.exports = SidebarSection
