'use strict';
const async = require('./waterfallHow');

async.waterfall([
  function(next){
    next(null,'one','two');
  },
  function(arg1,arg2,next){
    console.log(arg1);
    console.log(arg2);
    next(null,'three');
  },
  function(arg1,next){
    console.log(arg1);
    next(null,'done');
  }
],function(err,result){
  console.log(err,result);
});