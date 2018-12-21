### **iOS**

对于同步方法的内部需要依赖其他异步过程的结果, iOS 的 第三方库 AFNetworking 采用了 GCD 信号量的方式实现.

即发起连接请求之前，创建一个初始值为 0 的信号量，在方法返回之前阻塞函数, 请求该信号量，直到在连接请求的结果回调中释放该信号量. 

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

<br>

### **JavaScript**


这个信号量的实现过程其实很吻合 JavaScript  async/await 的内部原理. 

async 将 generator 和其自动执行器包装在同一个函数里, 相当于 AFNetworking 的 tasksForKeyPath 函数. 

而 generator 的 yield 就是 dispatch_semaphore_wait , 执行器 next 就是 dispatch_semaphore_signal .

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

如图, 事件循环的同步代码执行完毕后才会依次执行微任务队列中的回调函数,并返回异步执行的结果. 

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

如果一帧内有多处DOM修改, 浏览器会积攒起来一次绘制, 不会像图中显示的每轮事件循环都去渲染更新.

 Vue3.0 将会推出 Time Slicing Supoort :  每隔一帧 yield 给浏览器响应新的用户事件, 这样即使有用户事件产生了大量计算也不会影响事件回调函数的执行和浏览器渲染.

 iOS 的渲染更新节点也是在 Application object 处理完事件队列中所有的用户交互之后, 控制流将要回到主 Runloop 之时.
被标记为 "update layout" "needs display" 的视图在 `update cycle` 中完成渲染更新, 然后 Runloop 重启进入下一个循环.

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
	const feweekly = await feweeklyPromise;  // 相较前者并发了,但依旧阻塞
	const tooling  = await toolingPromise;
	console.log("---------");
```
```javascript
	getZhihuColumn('feweekly').then(feweekly => { // 异步非阻塞: 并发并且非阻塞
		console.log(`NAME: ${feweekly.name}`);
	})
	getZhihuColumn('toolingtips').then(tooling => {
		return tooling.name;
	}).then(name => {
		console.log(name);
	})
	console.log("---------");
```

<br>

### **Swoole**

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

Swoole 的 Co::sleep() 模拟的是协程中的 IO 密集型任务, 它会像 await 一样阻塞在那里. 但不同于 node 的异步非阻塞机制, 协程是通过自动让出控制权, 调度给其他已经完成 IO 任务的协程, 实现并发.

```bash
> time php go.php
 main
 mysql search ...
 response wait ...
 php go.php  0.08s user 0.02s system 4% cpu 2.107 total
```

而 sleep() 可以看做是 CPU 密集型任务, 从结果上看, 它不会引起协程的调度. 

```bash
> time php go.php
 mysql search ...
 main
 response wait ...
 php go.php  0.10s user 0.05s system 4% cpu 3.181 total
```

这是因为协程的内部也是基于事件驱动. 协程又叫做用户态线程, 和同步阻塞程序的主要区别在于进程/线程是操作系统在充当事件循环的调度, 而协程是由 epoll 自行调度.

<img src="https://paprika-dev.b0.upaiyun.com/eHJffMVYi5Egby6rQpC0c08gGXNO1G2F0FKglSGP.png">

epoll 向内核注册了回调函数，回调函数会把准备好的 socket fd 加入一个就绪链表, 执行 epoll_wait 时拷贝就绪链表里的 socket 数据到用户态, 这个过程遵循多路复用的同步 IO 事件原理, 通过监听多个IO事件, 等待事件触发的通知来执行读写任务而无需轮询, 不同于异步 IO 由内核来完成读写任务再通知应用程序数据结果.

Reactor 模型是常见的处理 同步IO事件 的模型.

它工作流程是: I/O事件触发，激活事件分离器，分离器调度对应的事件处理器；事件处理器完成I/O操作，处理数据.

<img src="https://paprika-dev.b0.upaiyun.com/GOgcviIiHMGvwThrnfjHbGMY03Sov5ZfuXriE2rj.png">

在 Swoole 4.0 中主协程就是 Reactor 协程，负责整个事件循环的运行. 
在工作协程中执行一些IO操作时，底层会将IO事件注册到事件循环，并让出执行权. 
主协程的 Reactor 会继续处理 IO 事件、监听新事件(epoll_wait), 有 IO 事件完成后唤醒其工作协程.


Swoole 的多进程 + 多线程模型: 

<img src="https://paprika-dev.b0.upaiyun.com/3jmpVbIhs7Z7APifAOYLgR0hwBmbDBcvAUC8lvq1.png" width="500">

可以把 Reactor 也就是 Master Process 看做 Nginx ，Work Process 是 php-FPM . 

<img src="https://paprika-dev.b0.upaiyun.com/0hDH4Y7no7VHuFaUZoQj76vKZnx2bmzEEpZamEpw.jpeg" width="500">

Reactor 线程异步并行地处理网络请求，然后转发给 Work Process, Work Process 接收数据回调至 PHP 业务层, 再将来自 PHP 层的数据和连接控制信息发送给 Reactor. 

<br>

### **Openresty**

Cosocket , 是 Lua 协程与 Nginx 事件通知相结合的成果. 

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

而在书写上也真正实现了 **完全的同步方式** 替代 **异步的回调机制**(在 Swoole 部分支持协程的回调函数里, 其实也是可以实现的).

<br>

### **Golang**

每个系统级线程都会有一个固定大小的栈, 用来保存函数递归调用时参数和局部变量.

但 Goroutine 会以一个很小的栈启动,当遇到深度递归导致栈空间不够时, 可以动态扩展栈的空间. 

因为启动的代价很小, Goroutine 可以轻易开启无数个 Goroutine.

<br>

回到文章最开始的问题, 同步方法内部依赖异步执行的结果, Golang 会如何实现?

```go
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
```go
func main() {
	done := make(chan int,1)
	go func() {
		println("response wait ... ")
		done <- 1
	}()
	<- done
}
```

Swoole 实现 channel :

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

Swoole 实现 waitgroup : 

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