/* eslint global-require: 0 */
/* eslint import/no-dynamic-require: 0 */
const s3 = require('s3');
const request = require('request');
const Promise = require('bluebird');
const path = require('path');
const fs = require('fs-plus');


let s3Client = null;
let packageVersion = null;
let fullVersion = null;

module.exports = (grunt) => {
  const {spawn} = require('./task-helpers')(grunt);

  function populateVersion() {
    return new Promise((resolve, reject) => {
      const json = grunt.config.get('appJSON')
      const cmd = 'git';
      const args = ['rev-parse', '--short', 'HEAD'];
      spawn({cmd, args}, (error, {stdout} = {}) => {
        if (error) {
          return reject();
        }
        const commitHash = stdout ? stdout.trim() : null;
        packageVersion = json.version;
        if (packageVersion.indexOf('-') > 0) {
          fullVersion = packageVersion;
        } else {
          fullVersion = `${packageVersion}-${commitHash}`;
        }
        return resolve();
      });
    });
  }

  function postToSlack(msg) {
    if (!process.env.NYLAS_INTERNAL_HOOK_URL) {
      return Promise.resolve();
    }
    return new Promise((resolve, reject) =>
      request.post({
        url: process.env.NYLAS_INTERNAL_HOOK_URL,
        json: {
          username: "Edgehill Builds",
          text: msg,
        },
      }
      , (error) => {
        return error ? reject(error) : resolve();
      })
    );
  }

  function put(localSource, destName, options = {}) {
    grunt.log.writeln(`>> Uploading ${localSource} to S3…`);

    const write = grunt.log.writeln;
    let lastPc = 0;

    const params = {
      Key: destName,
      ACL: "public-read",
      Bucket: "edgehill",
    };
    Object.assign(params, options);

    return new Promise((resolve, reject) => {
      const uploader = s3Client.uploadFile({
        localFile: localSource,
        s3Params: params,
      });
      uploader.on("error", err => reject(err));
      uploader.on("progress", () => {
        const pc = Math.round((uploader.progressAmount / uploader.progressTotal) * 100.0);
        if (pc !== lastPc) {
          lastPc = pc;
          write(`>> Uploading ${destName} ${pc}%`);
          return;
        }
      });
      uploader.on("end", data => resolve(data));
    });
  }

  function uploadToS3(filepath, key) {
    grunt.log.writeln(`>> Uploading ${filepath} to ${key}…`);
    return put(filepath, key).then((data) => {
      const msg = `N1 release asset uploaded: <${data.Location}|${key}>`;
      return postToSlack(msg).then(() => Promise.resolve(data));
    });
  }

  grunt.registerTask("publish", "Publish Nylas build", function publish() {
    const done = this.async();

    populateVersion()
    .then(() => {
      // find files to publish
      const {shouldPublishBuild} = require('./task-helpers')(grunt);
      const outputDir = grunt.config.get('outputDir');
      const uploads = [];

      if (process.platform === 'darwin') {
        uploads.push({
          source: `${outputDir}/N1.zip`,
          key: `${fullVersion}/${process.platform}/${process.arch}/N1.zip`,
        });
      } else if (process.platform === 'win32') {
        uploads.push({
          source: `${outputDir}/RELEASES`,
          key: `${fullVersion}/${process.platform}/${process.arch}/RELEASES`,
        });
        uploads.push({
          source: `${outputDir}/N1Setup.exe`,
          key: `${fullVersion}/${process.platform}/${process.arch}/N1Setup.exe`,
        });
        uploads.push({
          source: `${outputDir}/Nylas-${packageVersion}-full.nupkg`,
          key: `${fullVersion}/${process.platform}/${process.arch}/nylas-${packageVersion}-full.nupkg`,
        });
      } else if (process.platform === 'linux') {
        const files = fs.readdirSync(outputDir);
        for (const file of files) {
          if (path.extname(file) === '.deb') {
            uploads.push({
              source: `${outputDir}/${file}`,
              key: `${fullVersion}/${process.platform}-deb/${process.arch}/N1.deb`,
              options: {ContentType: "application/x-deb"},
            });
          }
          if (path.extname(file) === '.rpm') {
            uploads.push({
              source: `${outputDir}/${file}`,
              key: `${fullVersion}/${process.platform}-rpm/${process.arch}/N1.rpm`,
              options: {ContentType: "application/x-rpm"},
            });
          }
        }
      } else {
        grunt.fail.fatal(`Unsupported platform: '${process.platform}'`);
      }

      // configure environment
      if (!shouldPublishBuild()) {
        grunt.log.writeln(`>> Not publishing builds…`);
        grunt.log.writeln(`>> Would have uploaded the following assets: ${JSON.stringify(uploads, null, 2)}`);
        return Promise.resolve();
      }
      const awsKey = process.env.AWS_ACCESS_KEY_ID != null ? process.env.AWS_ACCESS_KEY_ID : "";
      const awsSecret = process.env.AWS_SECRET_ACCESS_KEY != null ? process.env.AWS_SECRET_ACCESS_KEY : "";

      if (awsKey.length === 0) {
        grunt.fail.fatal("Please set the AWS_ACCESS_KEY_ID environment variable");
      }
      if (awsSecret.length === 0) {
        grunt.fail.fatal("Please set the AWS_SECRET_ACCESS_KEY environment variable");
      }

      s3Client = s3.createClient({
        s3Options: {
          accessKeyId: process.env.AWS_ACCESS_KEY_ID,
          scretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
        },
      });

      return Promise.all(uploads.map(({source, key, options}) =>
        uploadToS3(source, key, options))
      )
      .then(done)
    })
    .catch((err) => {
      grunt.fail.fatal(err)
    });
  });
}
