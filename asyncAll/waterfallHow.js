'use strict';
exports.waterfall = function(task=[],callback=noop){
  if(!Array.isArray(task)){
    return callback(new Error('task should be an array'));
  }
  (function next(...args){
    if(args[0]){
      return callback(args[0]);
    }
    if(task.length){
      let fn = task.shift();
      fn.apply(null,[...args.slice(1),onlyOnce(next)]);
    }else{
      callback.apply(null,args);
    }
  })();
};
function noop(){}
function onlyOnce(cb){
  let flag = false;
  return (...args) => {
    if(flag){
      return cb(new Error('cb already called'));
    }
    cb.apply(null,args);
    flag = true;
  };
}