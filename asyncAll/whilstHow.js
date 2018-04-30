exports.whilst = function(test,iterator,callback=noop){
  if(typeof test != 'function'){
    return callback(new Error('test should be a function'));
  }
  if(typeof iterator != 'function'){
    return callback(new Error('iterator should be a function'));
  }
  (function next(){
    if(test()){
      iterator((err)=>{
        if(err){
          return callback(err);
        }
        next();
      });
   }
  })();
};
function noop(){};