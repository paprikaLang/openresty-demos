'use strict';
const fs = require('fs');
const async = require('./eachLimitHow');
const request = require('request');

let sites = ['www.baidu.com',
             'github.com',
             'www.zhihu.com',
             'www.npmjs.com'
];

function downloadFavicon(site,next){
    let address = `https://${site}/favicon.ico`;
    let file = `./${site}.ico`;
    request.get(address)
           .pipe(fs.createWriteStream(file))
           .on('finish',next);
}

async.eachLimit(sites,3,downloadFavicon,function(err){
  if(err){
    console.log('error',err)

  }
  console.log('over');
});