import fs from 'fs'
import request from 'request'
import crypto from 'crypto'
import {remote} from 'electron'
import Utils from './models/utils'
import Actions from './actions'
import {APIError, RequestEnsureOnceError} from './errors'
import PriorityUICoordinator from '../priority-ui-coordinator'
import IdentityStore from './stores/identity-store'
import NylasAPI from './nylas-api'

export default class NylasAPIRequest {
  constructor(api, options) {
    const defaults = {
      url: `${options.APIRoot || api.APIRoot}${options.path}`,
      method: 'GET',
      json: true,
      timeout: 15000,
      ensureOnce: false,
      started: () => {},
      error: () => {},
      success: () => {},
    }

    this.api = api;
    this.options = Object.assign(defaults, options);

    const bodyIsRequired = (this.options.method !== 'GET' && !this.options.formData);
    if (bodyIsRequired) {
      const fallback = this.options.json ? {} : '';
      this.options.body = this.options.body || fallback;
    }
  }

  constructAuthHeader() {
    if (!this.options.accountId) {
      throw new Error("Cannot make Nylas request without specifying `auth` or an `accountId`.");
    }

    const identity = IdentityStore.identity();
    if (identity && !identity.token) {
      const clickedIndex = remote.dialog.showMessageBox({
        type: 'error',
        message: 'Identity is present but identity token is missing.',
        detail: `Actions like sending and receiving mail require this token. Please log back into your Nylas ID to restore it—your email accounts will not be removed in this process.`,
        buttons: ['Log out'],
      })
      if (clickedIndex === 0) {
        Actions.logoutNylasIdentity()
      }
    }

    const accountToken = this.api.accessTokenForAccountId(this.options.accountId);
    if (!accountToken) {
      throw new Error(`Cannot make Nylas request for account ${this.options.accountId} auth token.`);
    }

    return {
      user: accountToken,
      pass: identity ? identity.token : '',
      sendImmediately: true,
    };
  }

  getRequestHash() {
    const {url, method, requestId, body, qs} = this.options
    const query = qs ? qs.toJSON() : ''
    const md5sum = crypto.createHash('md5')
    const data = `${requestId || ''}${method}${url}${query}${body || ''}`
    md5sum.update(data)
    return md5sum.digest('hex')
  }

  requestHasSucceededBefore() {
    const hash = this.getRequestHash()
    return fs.existsSync(`${NylasEnv.getConfigDirPath()}/${hash}`)
  }

  writeRequestSuccessRecord() {
    try {
      const hash = this.getRequestHash()
      fs.writeFileSync(`${NylasEnv.getConfigDirPath()}/${hash}`)
    } catch (e) {
      console.warn('NylasAPIRequest: Error writing request success record to filesystem')
    }
  }

  run() {
    if (this.options.ensureOnce === true) {
      try {
        if (this.requestHasSucceededBefore()) {
          const error = new RequestEnsureOnceError('NylasAPIRequest: request with `ensureOnce = true` has already succeeded before')
          return Promise.reject(error)
        }
      } catch (error) {
        return Promise.reject(error)
      }
    }
    if (!this.options.auth) {
      try {
        this.options.auth = this.constructAuthHeader();
      } catch (err) {
        return Promise.reject(new APIError({body: err.message, statusCode: 400}));
      }
    }

    const requestId = Utils.generateTempId();

    return new Promise((resolve, reject) => {
      this.options.startTime = Date.now();
      Actions.willMakeAPIRequest({
        request: this.options,
        requestId: requestId,
      });

      const req = request(this.options, (error, response = {}, body) => {
        Actions.didMakeAPIRequest({
          request: this.options,
          statusCode: response.statusCode,
          error: error,
          requestId: requestId,
        });

        PriorityUICoordinator.settle.then(() => {
          if (error || (response.statusCode > 299)) {
            // Some errors (like socket errors and some types of offline
            // errors) return with a valid `error` object but no `response`
            // object (and therefore no `statusCode`. To normalize all of
            // this, we inject our own offline status code so people down
            // the line can have a more consistent interface.
            if (!response.statusCode) {
              response.statusCode = NylasAPI.TimeoutErrorCodes[0];
            }
            const apiError = new APIError({error, response, body, requestOptions: this.options});
            NylasEnv.errorLogger.apiDebug(apiError);
            this.options.error(apiError);
            reject(apiError);
          } else {
            if (this.options.ensureOnce === true) {
              this.writeRequestSuccessRecord()
            }
            this.options.success(body, response);
            resolve(body);
          }
        });
      });

      req.on('abort', () => {
        const cancelled = new APIError({
          statusCode: NylasAPI.CancelledErrorCode,
          body: 'Request Aborted',
        });
        reject(cancelled);
      });

      this.options.started(req);
    });
  }
}
