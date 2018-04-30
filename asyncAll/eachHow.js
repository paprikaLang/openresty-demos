'use strict';
exports.each = function(items=[],iterator,callback=noop){
  if(!Array.isArray(items)){
    return callback(new Error('items should be an array'));
  }
  if(typeof iterator != 'function'){
    return callback(new Error('iterator should be a function'));
  }
  let complete = 0;
  function next(err){
    if(err){
      return callback(err);
    }
    if(++complete >= items.length){
      callback();
    }
  }
  items.map((item) => iterator(item,next));
};

function noop(){}