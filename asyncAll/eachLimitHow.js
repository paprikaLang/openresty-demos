'use strict';
exports.eachLimit = function(items = [],limit = 1,iterator,callback = noop){
  if(!Array.isArray(items)){
    return callback(new Error('items should be an array'));
  }
  if(typeof iterator != 'function'){
    return callback(new Error('iterator should be a function'));
  }
  let done = false;
  let running = 0;
  let errored = false;

  (function next(){
    if(done && running <= 0 ){
       return callback();
    }
    while(running < limit && !errored){
      let item = items.shift();
      running++;
      if(item === undefined){
        done = true;
        if(running <= 0){
           callback();
        }
        return ;
      }
      iterator(item,(err)=>{
        running--;
        if(err){
          errored = true;
          return callback(err);
        }
        next();
      });
    }
  })();
};

function noop(){};