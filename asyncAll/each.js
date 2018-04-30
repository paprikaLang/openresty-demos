'use strict';
const fs = require('fs');
const async = require('./eachHow');
const request = require('request');

let sites=  ['www.baidu.com','github.com','www.zhihu.com','www.npmjs.com'];

function downloadFavicon(site,next){
  let address = `https://${site}/favicon.ico`;
  let file = `./${site}.ico`;
  request.get(address)
    .pipe(fs.createWriteStream(file))
    .on('finish',next);
}

async.each(sites,downloadFavicon,function(error){
   if(error){
     console.log('error',error);
   }
   console.log('over');
});
