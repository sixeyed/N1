Contact = require("../../src/flux/models/contact").default
AccountStore = require "../../src/flux/stores/account-store"
Account = require("../../src/flux/models/account").default

contact_1 =
  name: "Evan Morikawa"
  email: "evan@nylas.com"

describe "Contact", ->

  beforeEach ->
    @account = AccountStore.accounts()[0]

  it "can be built via the constructor", ->
    c1 = new Contact contact_1
    expect(c1.name).toBe "Evan Morikawa"
    expect(c1.email).toBe "evan@nylas.com"

  it "accepts a JSON response", ->
    c1 = (new Contact).fromJSON(contact_1)
    expect(c1.name).toBe "Evan Morikawa"
    expect(c1.email).toBe "evan@nylas.com"

  it "correctly parses first and last names", ->
    c1 = new Contact {name: "Evan Morikawa"}
    expect(c1.firstName()).toBe "Evan"
    expect(c1.lastName()).toBe "Morikawa"

    c2 = new Contact {name: "Evan Takashi Morikawa"}
    expect(c2.firstName()).toBe "Evan"
    expect(c2.lastName()).toBe "Takashi Morikawa"

    c3 = new Contact {name: "evan foo last-name"}
    expect(c3.firstName()).toBe "evan"
    expect(c3.lastName()).toBe "foo last-name"

    c4 = new Contact {name: "Prince"}
    expect(c4.firstName()).toBe "Prince"
    expect(c4.lastName()).toBe ""

    c5 = new Contact {name: "Mr. Evan Morikawa"}
    expect(c5.firstName()).toBe "Evan"
    expect(c5.lastName()).toBe "Morikawa"

    c6 = new Contact {name: "Mr Evan morikawa"}
    expect(c6.firstName()).toBe "Evan"
    expect(c6.lastName()).toBe "morikawa"

    c7 = new Contact {name: "Dr. No"}
    expect(c7.firstName()).toBe "No"
    expect(c7.lastName()).toBe ""

    c8 = new Contact {name: "Mr"}
    expect(c8.firstName()).toBe "Mr"
    expect(c8.lastName()).toBe ""

  it "properly parses Mike Kaylor via LinkedIn", ->
    c8 = new Contact {name: "Mike Kaylor via LinkedIn"}
    expect(c8.firstName()).toBe "Mike"
    expect(c8.lastName()).toBe "Kaylor"
    c8 = new Contact {name: "Mike Kaylor VIA LinkedIn"}
    expect(c8.firstName()).toBe "Mike"
    expect(c8.lastName()).toBe "Kaylor"
    c8 = new Contact {name: "Mike Viator"}
    expect(c8.firstName()).toBe "Mike"
    expect(c8.lastName()).toBe "Viator"
    c8 = new Contact {name: "Olivia Pope"}
    expect(c8.firstName()).toBe "Olivia"
    expect(c8.lastName()).toBe "Pope"

  it "should not by fancy about the contents of parenthesis (Evan Morikawa)", ->
    c8 = new Contact {name: "Evan (Evan Morikawa)"}
    expect(c8.firstName()).toBe "Evan"
    expect(c8.lastName()).toBe "(Evan Morikawa)"

  it "falls back to the first component of the email if name isn't present", ->
    c1 = new Contact {name: " Evan Morikawa ", email: "evan@nylas.com"}
    expect(c1.displayName()).toBe "Evan Morikawa"
    expect(c1.displayName(compact: true)).toBe "Evan"

    c2 = new Contact {name: "", email: "evan@nylas.com"}
    expect(c2.displayName()).toBe "evan"
    expect(c2.displayName(compact: true)).toBe "evan"

    c3 = new Contact {name: "", email: ""}
    expect(c3.displayName()).toBe ""
    expect(c3.displayName(compact: true)).toBe ""


  it "properly parses names with @", ->
    c1 = new Contact {name: "nyl@s"}
    expect(c1.firstName()).toBe "nyl@s"
    expect(c1.lastName()).toBe ""

    c1 = new Contact {name: "nyl@s@n1"}
    expect(c1.firstName()).toBe "nyl@s@n1"
    expect(c1.lastName()).toBe ""

    c2 = new Contact {name: "nyl@s nyl@s"}
    expect(c2.firstName()).toBe "nyl@s"
    expect(c2.lastName()).toBe "nyl@s"

    c3 = new Contact {name: "nyl@s 2000"}
    expect(c3.firstName()).toBe "nyl@s"
    expect(c3.lastName()).toBe "2000"

    c6 = new Contact {name: "ev@nylas.com", email: "ev@nylas.com"}
    expect(c6.firstName()).toBe "ev@nylas.com"
    expect(c6.lastName()).toBe ""

    c7 = new Contact {name: "evan@nylas.com"}
    expect(c7.firstName()).toBe "evan@nylas.com"
    expect(c7.lastName()).toBe ""

    c8 = new Contact {name: "Mike K@ylor via L@nkedIn"}
    expect(c8.firstName()).toBe "Mike"
    expect(c8.lastName()).toBe "K@ylor"

  it "properly parses names with last, first (description)", ->
    c1 = new Contact {name: "Smith, Bob"}
    expect(c1.firstName()).toBe "Bob"
    expect(c1.lastName()).toBe "Smith"
    expect(c1.fullName()).toBe "Bob Smith"

    c2 = new Contact {name: "von Smith, Ricky Bobby"}
    expect(c2.firstName()).toBe "Ricky Bobby"
    expect(c2.lastName()).toBe "von Smith"
    expect(c2.fullName()).toBe "Ricky Bobby von Smith"

    c3 = new Contact {name: "von Smith, Ricky Bobby (Awesome Employee)"}
    expect(c3.firstName()).toBe "Ricky Bobby"
    expect(c3.lastName()).toBe "von Smith (Awesome Employee)"
    expect(c3.fullName()).toBe "Ricky Bobby von Smith (Awesome Employee)"

  it "should properly return `You` as the display name for the current user", ->
    c1 = new Contact {name: " Test Monkey", email: @account.emailAddress}
    expect(c1.displayName()).toBe "You"
    expect(c1.displayName(compact: true)).toBe "You"

  describe "isMe", ->
    it "returns true if the contact name matches the account email address", ->
      c1 = new Contact {email: @account.emailAddress}
      expect(c1.isMe()).toBe(true)
      c1 = new Contact {email: 'ben@nylas.com'}
      expect(c1.isMe()).toBe(false)

    it "is case insensitive", ->
      c1 = new Contact {email: @account.emailAddress.toUpperCase()}
      expect(c1.isMe()).toBe(true)

    it "it calls through to accountForEmail", ->
      c1 = new Contact {email: @account.emailAddress}
      acct = new Account()
      spyOn(AccountStore, 'accountForEmail').andReturn(acct)
      expect(c1.isMe()).toBe(true)
      expect(AccountStore.accountForEmail).toHaveBeenCalled()

  describe 'isValid', ->
    it "should return true for a variety of valid contacts", ->
      expect((new Contact(name: 'Ben', email: 'ben@nylas.com')).isValid()).toBe(true)
      expect((new Contact(email: 'ben@nylas.com')).isValid()).toBe(true)
      expect((new Contact(email: 'ben+123@nylas.com')).isValid()).toBe(true)

    it "should support contacts with unicode characters in domains", ->
      expect((new Contact(name: 'Ben', email: 'ben@arıman.com')).isValid()).toBe(true)

    it "should return false if the contact has no email", ->
      expect((new Contact(name: 'Ben')).isValid()).toBe(false)

    it "should return false if the contact has an email that is not valid", ->
      expect((new Contact(name: 'Ben', email:'Ben <ben@nylas.com>')).isValid()).toBe(false)
      expect((new Contact(name: 'Ben', email:'<ben@nylas.com>')).isValid()).toBe(false)
      expect((new Contact(name: 'Ben', email:'"ben@nylas.com"')).isValid()).toBe(false)

    it "returns false if the email doesn't satisfy the regex", ->
      expect((new Contact(name: "test", email: "foo")).isValid()).toBe false

    it "returns false if the email doesn't match", ->
      expect((new Contact(name: "test", email: "foo@")).isValid()).toBe false
