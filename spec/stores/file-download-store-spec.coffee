fs = require 'fs'
path = require 'path'
{shell} = require 'electron'
NylasAPI = require '../../src/flux/nylas-api'
File = require('../../src/flux/models/file').default
Message = require('../../src/flux/models/message').default
FileDownloadStore = require('../../src/flux/stores/file-download-store').default
{Download} = require('../../src/flux/stores/file-download-store')
AccountStore = require '../../src/flux/stores/account-store'


describe 'FileDownloadStoreSpecs', ->

  describe "Download", ->
    beforeEach ->
      spyOn(fs, 'createWriteStream')
      spyOn(NylasAPI, 'makeRequest')

    describe "constructor", ->
      it "should require a non-empty filename", ->
        expect(-> new Download(fileId: '123', targetPath: 'test.png')).toThrow()
        expect(-> new Download(filename: null, fileId: '123', targetPath: 'test.png')).toThrow()
        expect(-> new Download(filename: '', fileId: '123', targetPath: 'test.png')).toThrow()

      it "should require a non-empty fileId", ->
        expect(-> new Download(filename: 'test.png', fileId: null, targetPath: 'test.png')).toThrow()
        expect(-> new Download(filename: 'test.png', fileId: '', targetPath: 'test.png')).toThrow()

      it "should require a download path", ->
        expect(-> new Download(filename: 'test.png', fileId: '123')).toThrow()
        expect(-> new Download(filename: 'test.png', fileId: '123', targetPath: '')).toThrow()

    describe "run", ->
      beforeEach ->
        account = AccountStore.accounts()[0]
        @download = new Download(fileId: '123', targetPath: 'test.png', filename: 'test.png', accountId: account.id)
        @download.run()
        expect(NylasAPI.makeRequest).toHaveBeenCalled()

      it "should create a request with a null encoding to prevent the request library from attempting to parse the (potentially very large) response", ->
        expect(NylasAPI.makeRequest.mostRecentCall.args[0].json).toBe(false)
        expect(NylasAPI.makeRequest.mostRecentCall.args[0].encoding).toBe(null)

      it "should create a request for /files/123/download", ->
        expect(NylasAPI.makeRequest.mostRecentCall.args[0].path).toBe("/files/123/download")

  describe "FileDownloadStore", ->
    beforeEach ->
      account = AccountStore.accounts()[0]

      spyOn(shell, 'showItemInFolder')
      spyOn(shell, 'openItem')
      @testfile = new File({
        accountId: account.id,
        filename: '123.png',
        contentType: 'image/png',
        id: "id",
        size: 100
      })
      @testdownload = new Download({
        accountId: account.id,
        state : 'unknown',
        fileId : 'id',
        percent : 0,
        filename : '123.png',
        filesize : 100,
        targetPath : '/Users/testuser/.nylas/downloads/id/123.png'
      })

      FileDownloadStore._downloads = {}
      FileDownloadStore._downloadDirectory = "/Users/testuser/.nylas/downloads"
      spyOn(FileDownloadStore, '_generatePreview').andReturn(Promise.resolve())

    describe "pathForFile", ->
      it "should return path within the download directory with the file id and displayName", ->
        f = new File(filename: '123.png', contentType: 'image/png', id: 'id')
        spyOn(f, 'displayName').andCallThrough()
        expect(FileDownloadStore.pathForFile(f)).toBe("/Users/testuser/.nylas/downloads/id/123.png")
        expect(f.displayName).toHaveBeenCalled()

      it "should return unique paths for identical filenames with different IDs", ->
        f1 = new File(filename: '123.png', contentType: 'image/png', id: 'id1')
        f2 = new File(filename: '123.png', contentType: 'image/png', id: 'id2')
        expect(FileDownloadStore.pathForFile(f1)).toBe("/Users/testuser/.nylas/downloads/id1/123.png")
        expect(FileDownloadStore.pathForFile(f2)).toBe("/Users/testuser/.nylas/downloads/id2/123.png")

    it "should escape the displayName if it contains path separator characters", ->
      f1 = new File(filename: "static#{path.sep}b#{path.sep}a.jpg", contentType: 'image/png', id: 'id1')
      expect(FileDownloadStore.pathForFile(f1)).toBe("/Users/testuser/.nylas/downloads/id1/static-b-a.jpg")

      f1 = new File(filename: "my:file ? Windows /hates/ me :->.jpg", contentType: 'image/png', id: 'id1')
      expect(FileDownloadStore.pathForFile(f1)).toBe("/Users/testuser/.nylas/downloads/id1/my-file - Windows -hates- me ---.jpg")

    describe "_checkForDownloadedFile", ->
      it "should return true if the file exists at the path and is the right size", ->
        f = new File(filename: '123.png', contentType: 'image/png', id: "id", size: 100)
        spyOn(fs, 'statAsync').andCallFake (path) ->
          Promise.resolve({size: 100})
        waitsForPromise ->
          FileDownloadStore._checkForDownloadedFile(f).then (downloaded) ->
            expect(downloaded).toBe(true)

      it "should return false if the file does not exist", ->
        f = new File(filename: '123.png', contentType: 'image/png', id: "id", size: 100)
        spyOn(fs, 'statAsync').andCallFake (path) ->
          Promise.reject(new Error("File does not exist"))
        waitsForPromise ->
          FileDownloadStore._checkForDownloadedFile(f).then (downloaded) ->
            expect(downloaded).toBe(false)

      it "should return false if the file is too small", ->
        f = new File(filename: '123.png', contentType: 'image/png', id: "id", size: 100)
        spyOn(fs, 'statAsync').andCallFake (path) ->
          Promise.resolve({size: 50})
        waitsForPromise ->
          FileDownloadStore._checkForDownloadedFile(f).then (downloaded) ->
            expect(downloaded).toBe(false)

    describe "_onNewMailReceived", ->
      it "should fetch attachments if the setting is on-receive", ->
        spyOn(FileDownloadStore, '_fetch')
        spyOn(NylasEnv.config, 'get').andCallFake (key) ->
          return 'on-receive' if key is 'core.attachments.downloadPolicy'
          return null
        FileDownloadStore._onNewMailReceived(message: [new Message(files: [new File()])])
        expect(FileDownloadStore._fetch).toHaveBeenCalled()

      it "should not fetch attachments otherwise", ->
        spyOn(FileDownloadStore, '_fetch')
        spyOn(NylasEnv.config, 'get').andCallFake (key) ->
          return 'on-read' if key is 'core.attachments.downloadPolicy'
          return null
        FileDownloadStore._onNewMailReceived(message: [new Message(files: [new File()])])
        expect(FileDownloadStore._fetch).not.toHaveBeenCalled()

    describe "_runDownload", ->
      beforeEach ->
        spyOn(Download.prototype, 'run').andCallFake -> Promise.resolve(@)
        spyOn(FileDownloadStore, '_prepareFolder').andCallFake -> Promise.resolve(true)

      it "should make sure that the download file path exists", ->
        FileDownloadStore._runDownload(@testfile)
        expect(FileDownloadStore._prepareFolder).toHaveBeenCalled()

      it "should return the promise returned by download.run if the download already exists", ->
        existing =
          fileId: @testfile.id
          run: jasmine.createSpy('existing.run').andCallFake ->
            Promise.resolve(existing)
        FileDownloadStore._downloads[@testfile.id] = existing

        promise = FileDownloadStore._runDownload(@testfile)
        expect(promise instanceof Promise).toBe(true)
        waitsForPromise ->
          promise.then ->
            expect(existing.run).toHaveBeenCalled()

      describe "when the downloaded file exists", ->
        beforeEach ->
          spyOn(FileDownloadStore, '_checkForDownloadedFile').andCallFake ->
            Promise.resolve(true)

        it "should resolve with a Download without calling download.run", ->
          waitsForPromise =>
            FileDownloadStore._runDownload(@testfile).then (download) ->
              expect(Download.prototype.run).not.toHaveBeenCalled()
              expect(download instanceof Download).toBe(true)
              expect(download.data()).toEqual({
                state : 'finished',
                fileId : 'id',
                percent : 0,
                filename : '123.png',
                filesize : 100,
                targetPath : '/Users/testuser/.nylas/downloads/id/123.png'
              })

      describe "when the downloaded file does not exist", ->
        beforeEach ->
          spyOn(FileDownloadStore, '_checkForDownloadedFile').andCallFake ->
            Promise.resolve(false)

        it "should register the download with the right attributes", ->
          FileDownloadStore._runDownload(@testfile)
          advanceClock(0)
          expect(FileDownloadStore.downloadDataForFile(@testfile.id)).toEqual({
            state : 'unstarted',fileId : 'id',
            percent : 0,
            filename : '123.png',
            filesize : 100,
            targetPath : '/Users/testuser/.nylas/downloads/id/123.png'
          })

        it "should call download.run", ->
          waitsForPromise =>
            FileDownloadStore._runDownload(@testfile)
          runs ->
            expect(Download.prototype.run).toHaveBeenCalled()

        it "should resolve with a Download", ->
          waitsForPromise =>
            FileDownloadStore._runDownload(@testfile).then (download) ->
              expect(download instanceof Download).toBe(true)
              expect(download.data()).toEqual({
                state : 'unstarted',
                fileId : 'id',
                percent : 0,
                filename : '123.png',
                filesize : 100,
                targetPath : '/Users/testuser/.nylas/downloads/id/123.png'
              })

    describe "_fetch", ->
      it "should call through to startDownload", ->
        spyOn(FileDownloadStore, '_runDownload').andCallFake ->
          Promise.resolve(@testdownload)
        FileDownloadStore._fetch(@testfile)
        expect(FileDownloadStore._runDownload).toHaveBeenCalled()

      it "should fail silently since it's called passively", ->
        spyOn(FileDownloadStore, '_presentError')
        spyOn(FileDownloadStore, '_runDownload').andCallFake =>
          Promise.reject(@testdownload)
        FileDownloadStore._fetch(@testfile)
        expect(FileDownloadStore._presentError).not.toHaveBeenCalled()

    describe "_fetchAndOpen", ->
      it "should open the file once it's been downloaded", ->
        @savePath = "/Users/imaginary/.nylas/Downloads/a.png"
        download = {targetPath: @savePath}
        downloadResolve = null

        spyOn(FileDownloadStore, '_runDownload').andCallFake =>
          new Promise (resolve, reject) ->
            downloadResolve = resolve

        FileDownloadStore._fetchAndOpen(@testfile)
        expect(shell.openItem).not.toHaveBeenCalled()
        downloadResolve(download)
        advanceClock(100)
        expect(shell.openItem).toHaveBeenCalledWith(@savePath)

      it "should open an error if the download fails", ->
        spyOn(FileDownloadStore, '_presentError')
        spyOn(FileDownloadStore, '_runDownload').andCallFake =>
          Promise.reject(@testdownload)
        FileDownloadStore._fetchAndOpen(@testfile)
        advanceClock(1)
        expect(FileDownloadStore._presentError).toHaveBeenCalled()

    describe "_fetchAndSave", ->
      beforeEach ->
        @userSelectedPath = "/Users/imaginary/.nylas/Downloads/b.png"
        spyOn(NylasEnv, 'showSaveDialog').andCallFake (options, callback) => callback(@userSelectedPath)

      it "should open a save dialog and prompt the user to choose a download path", ->
        spyOn(FileDownloadStore, '_runDownload').andCallFake =>
          new Promise (resolve, reject) -> # never resolve
        FileDownloadStore._fetchAndSave(@testfile)
        expect(NylasEnv.showSaveDialog).toHaveBeenCalled()
        expect(FileDownloadStore._runDownload).toHaveBeenCalledWith(@testfile)

      it "should open an error if the download fails", ->
        spyOn(FileDownloadStore, '_presentError')
        spyOn(FileDownloadStore, '_runDownload').andCallFake =>
          Promise.reject(@testdownload)
        FileDownloadStore._fetchAndSave(@testfile)
        advanceClock(1)
        expect(FileDownloadStore._presentError).toHaveBeenCalled()

      describe "when the user confirms a path", ->
        beforeEach ->
          @download = {targetPath: 'bla'}
          @onEndEventCallback = null
          streamStub =
            pipe: ->
            on: (eventName, eventCallback) =>
              @onEndEventCallback = eventCallback

          spyOn(FileDownloadStore, '_runDownload').andCallFake =>
            Promise.resolve(@download)
          spyOn(fs, 'createReadStream').andReturn(streamStub)
          spyOn(fs, 'createWriteStream')

        it "should copy the file to the download path after it's been downloaded and open it after the stream has ended", ->
          FileDownloadStore._fetchAndSave(@testfile)
          advanceClock(1)
          expect(fs.createReadStream).toHaveBeenCalledWith(@download.targetPath)
          expect(shell.showItemInFolder).not.toHaveBeenCalled()
          @onEndEventCallback()
          advanceClock(1)

        it "should show file in folder if download path differs from previous download path", ->
          spyOn(FileDownloadStore, '_saveDownload').andCallFake =>
            Promise.resolve(@testfile)
          NylasEnv.savedState.lastDownloadDirectory = null
          @userSelectedPath = "/Users/imaginary/.nylas/Another Random Folder/file.jpg"
          FileDownloadStore._fetchAndSave(@testfile)
          advanceClock(1)
          expect(shell.showItemInFolder).toHaveBeenCalledWith(@userSelectedPath)

        it "should not show the file in the folder if the download path is the previous download path", ->
          spyOn(FileDownloadStore, '_saveDownload').andCallFake =>
            Promise.resolve(@testfile)
          @userSelectedPath = "/Users/imaginary/.nylas/Another Random Folder/123.png"
          NylasEnv.savedState.lastDownloadDirectory = "/Users/imaginary/.nylas/Another Random Folder"
          FileDownloadStore._fetchAndSave(@testfile)
          advanceClock(1)
          expect(shell.showItemInFolder).not.toHaveBeenCalled()

        it "should update the NylasEnv.savedState.lastDownloadDirectory if is has changed", ->
          spyOn(FileDownloadStore, '_saveDownload').andCallFake =>
            Promise.resolve(@testfile)
          NylasEnv.savedState.lastDownloadDirectory = null
          @userSelectedPath = "/Users/imaginary/.nylas/Another Random Folder/file.jpg"
          FileDownloadStore._fetchAndSave(@testfile)
          advanceClock(1)
          expect(NylasEnv.savedState.lastDownloadDirectory).toEqual('/Users/imaginary/.nylas/Another Random Folder')

        describe "file extensions", ->
          it "should allow the user to save the file with a different extension", ->
            @userSelectedPath = "/Users/imaginary/.nylas/Downloads/b-changed.tiff"
            FileDownloadStore._fetchAndSave(@testfile)
            advanceClock(1)
            expect(fs.createWriteStream).toHaveBeenCalledWith(@userSelectedPath)

          it "should restore the extension if the user removed it entirely, because it's usually an accident", ->
            @userSelectedPath = "/Users/imaginary/.nylas/Downloads/b-changed"
            FileDownloadStore._fetchAndSave(@testfile)
            advanceClock(1)
            expect(fs.createWriteStream).toHaveBeenCalledWith("#{@userSelectedPath}.png")

    describe "_abortFetchFile", ->
      beforeEach ->
        @download =
          ensureClosed: jasmine.createSpy('abort')
          fileId: @testfile.id
        FileDownloadStore._downloads[@testfile.id] = @download

      it "should cancel the download for the provided file", ->
        spyOn(fs, 'exists').andCallFake (path, callback) -> callback(true)
        spyOn(fs, 'unlink')
        FileDownloadStore._abortFetchFile(@testfile)
        expect(fs.unlink).toHaveBeenCalled()
        expect(@download.ensureClosed).toHaveBeenCalled()

      it "should not try to delete the file if doesn't exist", ->
        spyOn(fs, 'exists').andCallFake (path, callback) -> callback(false)
        spyOn(fs, 'unlink')
        FileDownloadStore._abortFetchFile(@testfile)
        expect(fs.unlink).not.toHaveBeenCalled()
        expect(@download.ensureClosed).toHaveBeenCalled()
