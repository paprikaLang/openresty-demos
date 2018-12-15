### iOS

对于同步方法的内部实现需要依赖其他异步过程的实现, iOS 的 第三方库 AFNetworking 采用了 GCD 信号量的方式.

即发起连接请求之前，创建一个初始值为 0 的信号量，在方法返回之前请求该信号量，同时，在连接请求的结果回调中释放该信号量. 

```objectivec
- (NSArray *)tasksForKeyPath:(NSString *)keyPath {
    __block NSArray *tasks = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [self.session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(dataTasks))]) {
            tasks = dataTasks;
        } else if (){
			...
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(tasks))]) {
            tasks = [@[dataTasks, uploadTasks, downloadTasks] valueForKeyPath:@"@unionOfArrays.self"];
        }

        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    return tasks;
}
```

### JavaScript


上面的这个实现过程其实很吻合 JavaScript  async/await 同步写法的内部原理. 

async 将 generator 和其自动执行器包装在了同一个函数里, 相当于 AFNetworking 的 tasksForKeyPath 函数. 而 generator 的 yield 就是 dispatch_semaphore_wait , 执行器 next 就是 dispatch_semaphore_signal .

```javascript
//执行器
function ajax(url) {
    axios.get(url).then(result => userGen.next(result.data))
}

function* steps() {
    const a = yield ajax('https://api.github.com/users');
    const b = yield ajax(`https://api.github.com/users/${a[0].login}`);
    const c = yield ajax(b.followers_url);
    console.log(c);
}
const userGen = steps();
userGen.next();
```
```javascript
//自动执行器
const thunkify = require('thunkify');
function run(fn) {
  var gen = fn();
  function next(err, data) {
    var result = gen.next(data);
    if (result.done) return;
    result.value(next);
  }
  next();
}

var get = thunkify(axios.get);
function* steps() {
    const a = yield get('https://api.github.com/users');
    const b = yield get(`https://api.github.com/users/${a[0].login}`);
    const c = yield get(b.followers_url);
    console.log(c);
}
run(steps)
```
```javascript
async function fn(args){
  // 等同于下面的形式
}
// spawn内部实现了自动执行器
function fn(args){ 
  return spawn(function*() {
  	  ...
  }); 
}
```
不过 async await 应用时还需要注意两点:

**1. JavaScript 的事件循环和任务队列**

<img src="https://paprika-dev.b0.upaiyun.com/g3dtpqSgppOEBpvao7ogbPLWQUxSNEDYAFc9KZUZ.png" width="300"/>

- Promise 对象属于微任务. 

本轮事件循环的同步代码执行完毕后才会依次执行微任务队列中的回调函数,并返回异步执行的结果. 

```javascript
const files = await getFiles();
let totalSize = 0;

await Promise.all(
	files.map(async file => {
		totalSize += await getSize(file);  // totalSize = 0 + await getSize(file);
	})
);
```
```javascript
await Promise.all(
	files.map(async file => {
	  	const size = await getSize(file);  
	  	totalSize += size;
	})
);
```

- 关于浏览器渲染

如果一帧内有多处DOM修改, 浏览器会积攒起来一次绘制, 并不像图中显示的每轮事件循环都去渲染更新.

Vue3.0 将会推出 Time Slicing Supoort ---- 每隔一帧 yield 给浏览器响应新的用户事件, 这样即使用户事件产生了大量计算或延迟也不会影响事件回调函数的执行而导致浏览器卡顿了.

在 iOS 里, 渲染更新的节点也是在 Application object 处理完事件队列中所有的用户交互之后, 控制流将要回到主 Runloop 之时.
被标记为 "update layout" "needs display" 的视图在 `update cycle` 中完成渲染更新, Runloop 随后重新启动进入下一个循环.

**2. 并发与阻塞的问题**

```javascript
async function getZhihuColumn(id) {
	await sleep(2000);
	const url = `https://zhuanlan.zhihu.com/api/columns/${id}`;
    const response = await fetch(url);
    if (response.status !== 200) {
    	throw new Error(response.statusText);
    }
    return await response.json();
}

const showColumnInfo = async () => {
	try {
        console.time('showColumnInfo');
        const feweekly = await getZhihuColumn('feweekly');
		const tooling  = await getZhihuColumn('toolingtips');
		console.timeEnd('showColumnInfo');
	} catch(err) {
        console.error(err);  
	}
}
```
```javascript
	const feweeklyPromise =  getZhihuColumn('feweekly');
	const toolingPromise  =  getZhihuColumn('toolingtips');
	const feweekly = await feweeklyPromise;  //相较前者并发了,但依旧阻塞
	const tooling  = await toolingPromise;
	console.log("---------");
```
```javascript
	getZhihuColumn('feweekly').then(feweekly => { //异步非阻塞: 并发并且非阻塞
		console.log(`NAME: ${feweekly.name}`);
	})
	getZhihuColumn('toolingtips').then(tooling => {
		return tooling.name;
	}).then(name => {
		console.log(name);
	})
	console.log("---------");
```

### Swoole

```php
use Swoole\Coroutine as Co;
go(function() {
	// Co::sleep(1);
	sleep(1);
	echo "mysql search ...".PHP_EOL;
});
echo "main".PHP_EOL;
go(function() {
	// Co::sleep(2);
	sleep(2);
	echo "response wait ...".PHP_EOL;
});
```

Swoole 的 Co::sleep() 模拟的是协程中的 IO 密集型任务, 它会像 await 一样阻塞在那里, 自动让出控制权, 其他IO操作完成的协程才可执行并实现并发.

```bash
> time php go.php
 main
 mysql search ...
 response wait ...
 php go.php  0.08s user 0.02s system 4% cpu 2.107 total
```

而 sleep() 可以看做是 CPU 密集型任务, 不会引起协程的调度. 

```bash
> time php go.php
 mysql search ...
 main
 response wait ...
 php go.php  0.10s user 0.05s system 4% cpu 3.181 total
```

因为协程的内核也是事件驱动的, 协程又叫做用户态线程, 和同步阻塞程序的主要区别在于进程/线程是操作系统在充当事件循环的调度, 而协程是自己用 epoll 进行调度.

<img src="https://paprika-dev.b0.upaiyun.com/eHJffMVYi5Egby6rQpC0c08gGXNO1G2F0FKglSGP.png">

epoll 向内核注册了回调函数，回调函数会把准备好的 socket fd 加入一个就绪链表, 执行 epoll_wait 时拷贝就绪链表里的 socket 数据到用户态, 内核与用户态 mmap 同一块内存还可以减少不必要的拷贝. 

epoll 支持 ET 模式还需要配合非阻塞 socket , 避免 connect recv 这样的 API 卡在某个函数里, 重复同个触发事件.

Reactor模型是同步IO事件处理的一种常见模型, 同步IO和异步IO的区别是:同步 IO 需要在 socket fd 就绪后应用程序自己进行读写操作;  异步 IO 则是内核操作完成再拷贝给应用程序数据结果. epoll 是 IO复用 的一种实现, 而 IO 复用属于同步 IO 的范畴.

<img src="https://paprika-dev.b0.upaiyun.com/GOgcviIiHMGvwThrnfjHbGMY03Sov5ZfuXriE2rj.png">

Reactor 的工作流程是: I/O事件触发，激活事件分离器，分离器调度对应的事件处理器；事件处理器完成I/O操作，处理数据.

在 Swoole4.0 中主协程就是 Reactor 协程，负责整个事件循环的运行. 
在工作协程中执行一些IO操作时，底层会将IO事件注册到事件循环，并让出执行权. 
主协程的 Reactor 会继续处理 IO 事件、监听新事件(epoll_wait), 有 IO 事件完成后唤醒其工作协程.


Swoole 的多进程+ 多线程模型: 

<img src="https://paprika-dev.b0.upaiyun.com/3jmpVbIhs7Z7APifAOYLgR0hwBmbDBcvAUC8lvq1.png" width="500">

可以把 Reactor 也就是 Master Process 看做 Nginx ，Work Process 就是 php-FPM . Reactor 线程异步并行地处理网络请求，然后再转发给 Work Process, Work Process 接收数据回调至 PHP 业务层, 再将来自 PHP 层的数据和连接控制信息发送给 Reactor. 

<img src="https://paprika-dev.b0.upaiyun.com/0hDH4Y7no7VHuFaUZoQj76vKZnx2bmzEEpZamEpw.jpeg" width="300">




### Openresty

OpenResty 世界中技术、实用价值最高部分 ---- cosocket , 是 Lua 协程 + Nginx 事件通知相结合的成果. cosocket 对象是全双工的: 一个专门读取的 "light thread"，一个专门写入的 "light thread".

它们可以同时对同一个 cosocket 对象进行操作. 但不能让两个 "light threads" 对同一个 cosocket 对象都进行读（或者写、或者连接）操作，否则当调用 cosocket 对象时，将得到一个类似 "socket busy reading" 的错误.

<img src="https://paprika-dev.b0.upaiyun.com/HLcw2ecSy1BfRzNTm16uoIpfD9X5HC5lr30BlWqm.png">

```lua
local sock, err = ngx.socket.tcp()

if err then
	-- log
else
	sock:settimeout(5000)
	local ok, err = sock:connect('127.0.0.1',13370)  -- nc -l 13370 开启一个 TCP server
	local bytes, err = sock:send('paprikaLang')
	ngx.say(bytes)
end
```

终于可以在书写上实现完全的同步方式替代异步回调了, 在 Swoole 部分支持协程的回调函数里, 其实也是可以实现的.


### Golang

每个系统级线程都会有一个固定大小的栈, 用来保存函数递归调用时参数和局部变量. 而 Goroutine 会以一个很小的栈启动,当遇到深度递归导致栈空间不够时, 可以动态扩展栈的空间. 因为启动的代价很小, Goroutine 可以轻易开启无数个 Goroutine.

回到最开始的问题, Golang 会如何实现?

```golang
func main() {
	var mu sync.Mutex
	mu.Lock()
	go func() {
		println("response wait ... ")
		mu.Unlock()
	}()
	mu.Lock()
}
```
```
func main() {
	done := make(chan int,1)
	go func() {
		println("response wait ... ")
		done <- 1
	}()
	<- done
}
```
Swoole 实现 channel 管道同步:

```php
$serv = new \swoole_http_server("127.0.0.1", 9503, SWOOLE_BASE);

$serv->on('request', function ($req, $resp) {
    $chan = new chan(2);
    go(function () use ($chan) {
        $cli = new Swoole\Coroutine\Http\Client('www.qq.com', 80);
            $cli->set(['timeout' => 10]);
            $cli->setHeaders([
            'Host' => "www.qq.com",
            "User-Agent" => 'Chrome/49.0.2587.3',
            'Accept' => 'text/html,application/xhtml+xml,application/xml',
            'Accept-Encoding' => 'gzip',
        ]);
        $ret = $cli->get('/');
        $chan->push(['www.qq.com' => $cli->body]);
    });

    go(function () use ($chan) {
        $cli = new Swoole\Coroutine\Http\Client('www.163.com', 80);
        $cli->set(['timeout' => 10]);
        $cli->setHeaders([
            'Host' => "www.163.com",
            "User-Agent" => 'Chrome/49.0.2587.3',
            'Accept' => 'text/html,application/xhtml+xml,application/xml',
            'Accept-Encoding' => 'gzip',
        ]);
        $ret = $cli->get('/');
        $chan->push(['www.163.com' => $cli->body]);
    });

    $result = [];
    for ($i = 0; $i < 2; $i++)
    {
        $result += $chan->pop();
    }
    $resp->end(json_encode($result));
});
$serv->start();
```

Swoole 实现 Golang 的 waitgroup : 

```php
class WaitGroup
{
	private $count = 0;
	private $chan;
	
	function __construct()
	{
		$this->chan = new chan;
	}
	function add() {
		$this->count++;
	}
	function done() {
		$this->chan->push(true);
	}
	function wait() {
		for ($i=0; $i < $this->count; $i++) { 
			$this->chan->pop();
		}
	}
}

go(function() {
	$wg = new WaitGroup;
	for ($i=0; $i < 10; $i++) { 
		$wg->add();
		go(function() use ($wg, $i){
			co::sleep(.3);
			echo "hello $i\n";
			$wg->done();
		});
	}
	$wg->wait();
	echo "all done\n";
});
```

