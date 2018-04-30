'use strict';
const PENGING = Symbol();
const FULFILLED = Symbol();
const REJECTED = Symbol();


function Promisee(fn){
  if (typeof fn != 'function'){
    throw new Error('resolve should be a function');
  }

  let state = PENGING;
  let value = null;
  let handler = {};
  function fulfill(result){
    state = FULFILLED;
    value = result;
    next(handler);
  }

  function reject(err){
    state = REJECTED;
    value = err;
    next(handler);
  }
  function resolve(result){
    try{
      fulfill(result);
    }catch(err){
      reject(err);
    }
  }
  function next({onFulfill,onReject}){
     switch(state){
       case FULFILLED:
       onFulfill && onFulfill(value);
       break;
       case REJECTED:
       onReject && onReject(value);
       break;
       case PENGING:
       handler = {onFulfill,onReject};
     }
  }
  this.then = function(onFulfill,onReject){
    next({onFulfill,onReject});
  }
  fn(resolve,reject);

}

let p = new Promisee((resolve,reject)=>{
     resolve('hello');
     // reject('hello');
     setTimeout(()=>resolve('hello'),0);
});

p.then(console.log.bind(null,'over'),console.error.bind(null,'error'));





