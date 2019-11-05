> linux一般使用 non-blocking IO 提高 IO 并发度。当IO并发度很低时，non-blocking IO 不一定比 blocking IO 更高效，因为后者完全由内核负责，而read/write这类系统调用已高度优化，效率显然高于多个线程协作的 non-blocking IO。但当 IO 并发度愈发提高时，blocking IO 阻塞一个线程的弊端便显露出来：内核得不停地在线程间切换才能完成有效的工作，一个 cpu core 上可能只做了一点点事情，就马上又换成了另一个线程，cpu cache 没得到充分利用，另外大量的线程会使得依赖 thread-local 加速的代码性能明显下降，如 tcmalloc ，一旦 malloc 变慢，程序整体性能往往也会随之下降。

[]()
> 而 non-blocking IO 一般由少量 event dispatcher 线程和一些运行用户逻辑的 worker 线程组成，这些线程往往会被复用（换句话说调度工作转移到了用户态），event dispatcher 和 worker 可以同时在不同的核运行（流水线化），内核不用频繁的切换就能完成有效的工作。线程总量也不用很多，所以对 thread-local 的使用也比较充分。这时候 non-blocking IO 就往往比 blocking IO 快了。不过 non-blocking IO 也有自己的问题，它需要调用更多系统调用，比如epoll_ctl，由于 epoll 实现为一棵红黑树，epoll_ctl 并不是一个很快的操作，特别在多核环境下，依赖 epoll_ctl 的实现往往会面临棘手的扩展性问题。non-blocking 需要更大的缓冲，否则就会触发更多的事件而影响效率。non-blocking 还得解决不少多线程问题，代码比 blocking 复杂很多。

[]()
> asynchronous IO: 无需负责读写，把 buffer 提交给内核后,内核会把数据从内核拷贝到用户态，然后告诉你已可读.

   ---   [[三种操作IO的方式]](https://github.com/eesly/brpc/blob/master/docs/cn/io.md#the-full-picture)


<br>

<br>

# OpenResty

**OpenResty** 中最核心的概念 **cosocket** 就是依靠 Nginx epoll 的 event dispatcher 和 lua 语言的协程特性 实现的:

<img src="https://raw.githubusercontent.com/paprikaLang/paprikaLang.github.io/imgs/epoll1.png">

<img src="https://i.loli.net/2019/10/22/s2wuiFUXQl56eOV.jpg" width="700">

Lua 脚本运行在协程上，通过暂停自己（yield)，把网络事件添加到 Nginx 监听列表中，并把运行权限交给 Nginx ; 
当网络事件达到触发条件时，会唤醒 (resume）这个协程继续处理.

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

以 ngx.sleep 为例:

1. 添加 ngx_http_lua_sleep_handler 回调函数;

2. 然后调用 NGINX 提供的接口 ngx_add_timer ，向 NGINX 的事件循环中增加一个定时器; 

3. lua_yield 将 Lua 协程挂起，并把控制权交给 NGINX 的事件循环;

4. sleep 结束后,  ngx_http_lua_sleep_handler 被触发, 它里面会调用 ngx_http_lua_sleep_resume, lua_resume 最后唤醒了 Lua 协程.

```lua
static int ngx_http_lua_ngx_sleep(lua_State *L)
{
	coctx->sleep.handler = ngx_http_lua_sleep_handler;
	ngx_add_timer(&coctx->sleep, (ngx_msec_t) delay);
	return lua_yield(L, 0);
}
```

如果代码中没有 I/O 或者 ngx.sleep(0) 操作，而全是加解密运算这样的CPU密集型任务，那么 Lua 协程就会一直占用 LuaJIT VM，直到处理完整个请求.

<br>

<br>

# Golang

**Golang** 在 linux 上通过 runtime 包中的 netpoll_epoll.go 也实现了底层的 event dispatcher .

```go
// +build linux
func netpollinit() {                             // 对应 epollcreate1
	epfd = epollcreate1(_EPOLL_CLOEXEC)  
	... ...
}
// to arm edge-triggered notifications and associate fd with pd
func netpollopen(fd uintptr, pd *pollDesc) int32 {  //对应 epollctl
	var ev epollevent
	// _EPOLLRDHUP 解决了对端socket关闭，epoll本身并不能直接感知到这个关闭动作的问题
	ev.events = _EPOLLIN | _EPOLLOUT | _EPOLLRDHUP | _EPOLLET 
	*(**pollDesc)(unsafe.Pointer(&ev.data)) = pd // epollwait获取事件之后还会从&ev.data取出pd更改它的状态.
	return -epollctl(epfd, _EPOLL_CTL_ADD, int32(fd), &ev)
}
// returns list of goroutines that become runnable
func netpoll(block bool) *g {                      // 对应 epollwait
	var events [128]epollevent
	... ...
	n := epollwait(epfd, &events[0], int32(len(events)), waitms)
	... ...
	var gp guintptr
	for i := int32(0); i < n; i++ {
		ev := &events[i]
		... ...
		if mode != 0 {
			pd := *(**pollDesc)(unsafe.Pointer(&ev.data))
			// 再调用 netpoll.go 中的 netpollready 函数, 返回一个已经就绪的协程(g)链表
			netpollready(&gp, pd, mode)
		}
	} 
	... ...
	return gp.ptr()
}
```

```go
func netpollready(gpp *guintptr, pd *pollDesc, mode int32) {
	var rg, wg guintptr
	if mode == 'r' || mode == 'r'+'w' {
		// 将pollDesc的状态改成 pdReady 并返回就绪协程的地址
		// IO事件唤醒协程, 如果true改成false表示超时唤醒
		rg.set(netpollunblock(pd, 'r', true))
	}
	... ...
	if rg != 0 {
		// 将就绪协程添加至链表中
		rg.ptr().schedlink = *gpp
		*gpp = rg
	}
}
```

net.Listen 返回之前要经过:

fd_unix.go 中 netFD 的 Init --> 

fd_poll_runtime.go 中 `pollDesc` 的 init --> 

netpoll.go 中的 runtime_pollServerInit -->

一系列方法来生成 epoll 单例(serverInit.Do(runtime_pollServerInit)), 然后通过 runtime_pollOpen 将 fd 添加到 epoll 事件队列中. 

```go
func main() {
	listener, err := net.Listen("tcp", ":8888") 
	if err != nil { 
		fmt.Println("listen error: ", err) 
		return
	} 
	for{
		conn, err := listener.Accept() 
		if err != nil {
			fmt.Println("accept error: ", err) 
			continue
		} 
		// 分配一个新的协程来处理一个新的连接: goroutine-per-connenction
		go HandleConn(conn)
	}
}
func HandleConn(conn net.Conn) {
  	defer conn.Close()
  	buf := make([]byte, 1024)
	for {
		n, err := conn.Read(buf)
		if err != nil {
			log.Println(err)
			return
		}

		conn.Write(buf[:n])
	}
}
```

```go

func (fd *netFD) accept() (netfd *netFD, err error) {
	netfd, err = newFD(s, fd.family, fd.sotype, fd.net)
	... ...
	// 这个前面已经分析，将该fd添加到epoll队列中
	err = netfd.init()
}
```

```go
func (fd *netFD) Read(p []byte) (n int, err error) {
	for {
		n, err := syscall.Read(fd.Sysfd, p)  // socketFunc(family, sotype|syscall.SOCK_NONBLOCK...)
		if err != nil {
			n = 0
			// 处理EAGAIN类型的错误，其他错误一律返回给调用者
			if err == syscall.EAGAIN && fd.pd.pollable() {
				// 对于non-blocking IO的文件描述符，如果错误是EAGAIN,说明Socket的缓冲区为空，会阻塞当前协程
				// waitRead 最终调用的接口是: runtime_pollWait
				if err = fd.pd.waitRead(fd.isFile); err == nil {
					continue
				}
			}
		}
		err = fd.eofError(n, err)
		return n, err
	}
}
```

对于non-blocking IO的文件描述符，如果错误是 `EAGAIN` ,说明 Socket 的缓冲区为空，会阻塞当前 goroutine . 

直到这个 netFD 上再次发生读写事件，才会将此 goroutine 激活并重新运行. 

而在底层通知 goroutine 再次发生读写事件的, 正是 epoll 的事件驱动机制.

```go
func poll_runtime_pollWait(pd *pollDesc, mode int) int {
	err := netpollcheckerr(pd, int32(mode))
	if err != 0 {
		return err
	}
	//如果返回true，表示是有读写事件发生, g被唤醒
	for !netpollblock(pd, int32(mode), false) { 
		//如果返回false,而且是超时错误就返回给应用程序, 如果是其他错误则继续进入 netpollblock 阻塞当前协程
		err = netpollcheckerr(pd, int32(mode))
		if err != 0 {
			return err
		}
	}
	return 0
}
```
```go
func netpollblock(pd *pollDesc, mode int32, waitio bool) bool {
    gpp := &pd.rg
    if mode == 'w' {
        gpp = &pd.wg
    }
    for {
        old := *gpp
        if old == pdReady {
            *gpp = 0
            return true
        }
        if old != 0 {
            throw("netpollblock: double wait")
        }
	// 参考 atomic.Store 的实现: if !CompareAndSwapPointer(&vp.typ, nil, unsafe.Pointer(^uintptr(0)))
        // 个人猜想casuintptr也应该是一个 CAS, 当 gpp=0 代表此时没有协程在对这个netFD消费
	// 当前协程可以将gpp设置为pdWait了. 此过程类似于一个加锁的效果.
        if atomic.Casuintptr(gpp, 0, pdWait) {
            break
        }
    }
    // gopark会阻塞当前协程g, 在此之前
    // 传入的函数指针 netpollblockcommit: casuintptr((*uintptr)(gpp), pdWait,  uintptr(unsafe.Pointer(gp)))
    // 会将pd.rg从pdWait换成g的地址, 这是为了在netpollunblock时知道该唤醒哪条协程(return (*g)(unsafe.Pointer(old))):
    if waitio || netpollcheckerr(pd, mode) == 0 {
        //gopark调用了mcall，mcall用汇编实现，作用就是把g挂起.
        gopark(netpollblockcommit, unsafe.Pointer(gpp), "IO wait", traceEvGoBlockNet, 5)
    }
    // atomic_xchg先获取gpp当前状态记录在old中,再 *gpp = 0
    old := atomic.Xchguintptr(gpp, 0)
    if old > pdWait {
        throw("netpollblock: corrupted state")
    }
    return old == pdReady
}
```

sysmon 是 golang 中的监控协程，可以周期性调用 netpoll(false) 获取就绪的协程 g链表; 

findrunnable 在调用 schedule() 时触发; 

golang 做完 gc 后也会调用 runtime·startTheWorldWithSema(void) 来检查是否有网络事件阻塞. 

这三种场景最终都会调用 injectglist() 来把阻塞的协程列表插入到全局的可运行g队列, 在下次调度时等待执行.


以上原理使得golang能以简洁易用的同步模式, 借助 go scheduler 的高效调度, 编写异步逻辑. 但是在海量连接场景下并且活跃连接占比又很低时, 这种 `goroutine-per-connenction` 的模式就会产生耗费资源, 低效



<br>

# Swoole


```php
<?php 
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
	echo "redis search ...".PHP_EOL;
});
输出结果-------------------------
Co::sleep():
// time php go.php
// main
// mysql search ...
// redis search ...
// php go.php  0.08s user 0.02s system 4% cpu 2.107 total
sleep():
// time php go.php
// mysql search ...
// main
// redis search ...
// php go.php  0.10s user 0.05s system 4% cpu 3.181 total
```

sleep() 可以看做是 CPU密集型任务, 不会引起协程的调度;

Co::sleep() 模拟的是 IO密集型任务, 会引发协程的调度, 协程让出控制, 进入协程调度队列, IO就绪时恢复运行.

**Swoole**

<img src="https://raw.githubusercontent.com/paprikaLang/paprikaLang.github.io/imgs/epoll2.png" width="650px;">

事件处理模型 Reactor 将I/O事件注册到多路复用器(能维护自己的事件循环, 监听不同的I/O事件)上，一旦有事件触发, 事件分离器就会将其分发到事件处理器中执行事件的处理逻辑.

Swoole 的 Main Thread , WorkThread , Work Process 均是由 Reactor 驱动, 并按照 注册事件等待触发 -> 分发 -> 处理 这样的模式运行.

Main Thread 负责监听服务端口接收网络连接, 将连接成功的I/O事件分发给 WorkThread .

<img src="https://raw.githubusercontent.com/paprikaLang/paprikaLang.github.io/imgs/epoll3.jpg" width="550px;">

WorkThread 在客户端request注册的读就绪事件上等待I/O操作完成, 再交给一个 Work Process 来处理请求对象的业务逻辑.

WorkThread 会先接收到这个 Work Process 注册的写就绪事件, 然后业务逻辑开始处理, 处理完成后触发此事件. 

Work Process 将数据收发和数据处理分离开来，只有 Worker Process 可以发起异步的Task任务,Task 底层使用 Unix Socket 管道通信，是全内存的，没有IO消耗。不同的进程使用不同的管道通信，可以最大化利用多核.

WorkThread <=> Work Process 这整个过程类似 同步 I/O 模拟的 Proactor 模式: 

<img src="https://raw.githubusercontent.com/paprikaLang/paprikaLang.github.io/imgs/epoll4.jpg" width="650px;">

从整体上看 Master Process + Work Process 的架构类似于 Nginx + php-FPM . 

<img src="https://raw.githubusercontent.com/paprikaLang/paprikaLang.github.io/imgs/epoll5.jpg" width="550px;">

总结一下 Swoole 的进程间通信

<img src="https://raw.githubusercontent.com/paprikaLang/paprikaLang.github.io/imgs/epoll6.png" width="650px;">


<br>

*注*

[百万 Go TCP 连接的思考2: 百万连接的吞吐率和延迟](https://colobu.com/2019/02/27/1m-go-tcp-connection-2/)
[Benchmark for implementation of servers that support 1m connections](https://github.com/smallnest/1m-go-tcp-server)

文章和源码包含以下内容:

8_server_workerpool: use **Reactor** pattern to implement multiple event loops

9_few_clients_high_throughputs: a simple goroutines per connection server for test throughtputs and latency

10_io_intensive_epoll_server: an io-bound multiple epoll server

11_io_intensive_goroutine: an io-bound goroutines per connection server

12_cpu_intensive_epoll_server: a cpu-bound multiple epoll server

13_cpu_intensive_goroutine: an cpu-bound goroutines per connection server


<br>


*参考*


