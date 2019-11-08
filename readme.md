> linux一般使用 non-blocking IO 提高 IO 并发度。当IO并发度很低时，non-blocking IO 不一定比 blocking IO 更高效，因为后者完全由内核负责，而read/write这类系统调用已高度优化，效率显然高于多个线程协作的 non-blocking IO。但当 IO 并发度愈发提高时，blocking IO 阻塞一个线程的弊端便显露出来：内核得不停地在线程间切换才能完成有效的工作，一个 cpu core 上可能只做了一点点事情，就马上又换成了另一个线程，cpu cache 没得到充分利用，另外大量的线程会使得依赖 thread-local 加速的代码性能明显下降，如 tcmalloc ，一旦 malloc 变慢，程序整体性能往往也会随之下降。

[]()
> 而 non-blocking IO 一般由少量 event dispatcher 线程和一些运行用户逻辑的 worker 线程组成，这些线程往往会被复用（换句话说调度工作转移到了用户态），event dispatcher 和 worker 可以同时在不同的核运行（流水线化），内核不用频繁的切换就能完成有效的工作。线程总量也不用很多，所以对 thread-local 的使用也比较充分。这时候 non-blocking IO 就往往比 blocking IO 快了。不过 non-blocking IO 也有自己的问题，它需要调用更多系统调用，比如epoll_ctl，由于 epoll 实现为一棵红黑树，epoll_ctl 并不是一个很快的操作，特别在多核环境下，依赖 epoll_ctl 的实现往往会面临棘手的扩展性问题。non-blocking 需要更大的缓冲，否则就会触发更多的事件而影响效率。non-blocking 还得解决不少多线程问题，代码比 blocking 复杂很多。

[]()
> asynchronous IO: 无需负责读写，把 buffer 提交给内核后,内核会把数据从内核拷贝到用户态，然后告诉你已可读.

   ---   [[三种操作IO的方式]](https://github.com/eesly/brpc/blob/master/docs/cn/io.md#the-full-picture)

<br>

# OpenResty

<br>

**OpenResty** 的 **cosocket** 就是基于 nginx_epoll 的 event dispatcher 和 lua 语言的协程特性 实现的:

<img src="https://raw.githubusercontent.com/paprikaLang/paprikaLang.github.io/imgs/epoll1.png" width="700">

<img src="https://i.loli.net/2019/10/22/s2wuiFUXQl56eOV.jpg" width="700">

Lua 脚本运行在协程上，通过暂停自己（yield)，把网络事件添加到 Nginx 监听列表中，并把运行权限交给 Nginx ; 

当网络事件达到触发条件时，会唤醒 (resume）这个协程继续处理. 这样就以同步的模式实现了异步的逻辑.


```lua
local sock, err = ngx.socket.tcp()

if err then
	-- log
else
	sock:settimeout(5000)
	local ok, err = sock:connect('127.0.0.1',13370)  -- nc -l 13370 开启一个 TCP server
	local bytes, err = sock:send('paprikaLang')      -- 同步编程模式简单易用
	ngx.say(bytes)
end
```

以 ngx.sleep 为例:

1. 添加 ngx_http_lua_sleep_handler 回调函数;

2. 然后调用 Nginx 提供的接口 ngx_add_timer ，向 Nginx 的事件循环中增加一个定时器; 

3. lua_yield 将 Lua 协程挂起，并把控制权交给 Nginx 的事件循环;

4. sleep 结束后,  ngx_http_lua_sleep_handler 被触发, 它里面会调用 ngx_http_lua_sleep_resume, lua_resume 最后唤醒了 Lua 协程.

```lua
static int ngx_http_lua_ngx_sleep(lua_State *L)
{
	coctx->sleep.handler = ngx_http_lua_sleep_handler;
	ngx_add_timer(&coctx->sleep, (ngx_msec_t) delay);
	return lua_yield(L, 0);
}
```

如果代码中没有 I/O 操作或者 nginx.sleep(0)，而是加解密运算，那么 Lua 协程就会一直占用 LuaJIT VM，直到处理完整个请求也不会交出控制权.

一个简单的 swoole 协程的示例也可以验证 `IO密集型任务`和 `CPU密集型任务` 在这方面的差别:

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
Co::sleep():模拟的是 IO密集型任务, 会引发协程的调度, 协程让出控制, 进入协程调度队列, IO 就绪时恢复运行
> time php go.php
 main
 mysql search ...
 redis search ...
 php go.php  0.08s user 0.02s system 4% cpu 2.107 total
sleep(): 可以看做是 CPU密集型任务, 不会引起协程的调度
> time php go.php
 mysql search ...
 main
 redis search ...
 php go.php  0.10s user 0.05s system 4% cpu 3.181 total
```

<br>

# Golang

<br>

**Golang** 在 linux 系统下的网络IO系统则是通过 epoll 触发事件唤醒协程 实现了和 openresty 类似的同步模式.

```go
// +build linux
func netpollinit() {                                             // 对应 epollcreate1
	epfd = epollcreate1(_EPOLL_CLOEXEC)  
	... ...
}
// to arm edge-triggered notifications and associate fd with pd
func netpollopen(fd uintptr, pd *pollDesc) int32 {               //对应 epollctl
	var ev epollevent
	// _EPOLLRDHUP 解决了对端socket关闭，epoll本身并不能直接感知到这个关闭动作的问题
	ev.events = _EPOLLIN | _EPOLLOUT | _EPOLLRDHUP | _EPOLLET 
	*(**pollDesc)(unsafe.Pointer(&ev.data)) = pd // epollwait获取事件之后还会从&ev.data取出pd更改它的状态.
	return -epollctl(epfd, _EPOLL_CTL_ADD, int32(fd), &ev)
}
// returns list of goroutines that become runnable
func netpoll(block bool) *g {                                    // 对应 epollwait
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
			// 再调用 netpoll.go 中的 netpollready 函数, 返回一个已经就绪的协程链表
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

一系列方法来生成 EPOLL 单例(serverInit.Do(runtime_pollServerInit)), 然后通过 runtime_pollOpen 将监听事件的 fd 添加到 
epoll 事件队列中来等待连接事件; 一旦有连接事件 accept 进来, 再用连接事件的 fd 监听数据的读写事件.

```go
func main() {
	listener, err := net.Listen("tcp", ":8888") 
	if err != nil { 
		fmt.Println("listen error: ", err) 
		return
	} 
	for{
		conn, err := listener.Accept() // accept 和 read 内部原理相似, 通过阻塞协程实现同步编程模式
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
对于non-blocking IO的文件描述符，如果错误是 `EAGAIN` ,说明 Socket 的缓冲区为空，会阻塞当前协程. 

直到这个 连接fd 上再次发生读写事件(或连接事件)，epoll 会通知此协程重新开始运行. 

```go
func (fd *netFD) Read(p []byte) (n int, err error) {
	for {
		n, err := syscall.Read(fd.Sysfd, p)  // syscall.SOCK_NONBLOCK
		if err != nil {
			n = 0
			if err == syscall.EAGAIN && fd.pd.pollable() {
				// waitRead 最终调用的接口是: runtime_pollWait
				if err = fd.pd.waitRead(fd.isFile); err == nil { 
					// 协程激活后执行continue, 并重新read数据,这时应该没有err可以成功return了.
					continue
				}
			}
		}
		err = fd.eofError(n, err)
		return n, err
	}
}
```

```go
func poll_runtime_pollWait(pd *pollDesc, mode int) int {
	err := netpollcheckerr(pd, int32(mode))
	if err != 0 {
		return err
	}
	//如果返回true，表示是有读写事件发生(old == pdReady)
	for !netpollblock(pd, int32(mode), false) { 
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
        // CAS原子操作, 一种乐观锁: 当 gpp=0 时 将gpp设置为pdWait. 针对连接事件的惊群效应?
        if atomic.Casuintptr(gpp, 0, pdWait) {
            break
        }
    }
    // gopark会阻塞当前协程, 在此之前
    // 传入的函数指针 netpollblockcommit: casuintptr((*uintptr)(gpp), pdWait,  uintptr(unsafe.Pointer(gp)))
    // 会将pd.rg从pdWait换成当前协程的地址, 这是为了在netpollunblock时知道该唤醒哪条协程(return (*g)(unsafe.Pointer(old))).
    if waitio || netpollcheckerr(pd, mode) == 0 {
        //gopark调用了mcall，mcall用汇编实现，作用就是把协程挂起.
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

go-net 的 `goroutine-per-connenction` 的模式借助 go scheduler 的高效调度, 以同步的方式编写异步逻辑, 简洁易用.

但是遇到海量连接并且活跃连接占比又很低的情况, 这种模式就会耗费大量资源, 性能上也会随之下降. 

看官们可以通过模拟餐厅高峰期时的场景, 将 `顾客-服务员-厨师` 与 `connection-goroutine-threads_pool` 对应上联系, 来想想如何提高效率节省资源.

<br>

## GNET

<br>

`gnet` 重新设计开发了一套 `主从多 Reactors + 线程/Go程池` 的异步网络模型:

<img src="https://user-images.githubusercontent.com/7496278/64918783-90de3b80-d7d5-11e9-9190-ff8277c95db1.png" width="700" />

mainReactor(大堂经理):  利用内置的 Round-Robin 轮询负载均衡算法, 将 newConnection 分配给一个 subReator . 

subReator(服务员):      一个 subReator 可以在自己的 epoll 上监听多个 connection 的读写事件, 事件触发时调用 EventHandler.React 处理.

worker pool(后厨):      不能及时处理的交给 ants 协程池.

```go
func (svr *server) activateMainReactor() {
	defer svr.signalShutdown()
	_ = svr.mainLoop.poller.Polling(func(fd int, ev uint32, job internal.Job) error {
		// mainReactor 只负责将监听fd传给acceptNewConnection方法.
		return svr.acceptNewConnection(fd) // acceptNewConnection会将连接fd传递给一个subReactor.
	})
}

func (p *Poller) Polling(callback func(fd int, ev uint32, job internal.Job) error) (err error) {
	... ...
	for {
		n, err0 := unix.EpollWait(p.fd, el.events, -1) // epoll还是event-loop事件驱动的核心
		... ...
		for i := 0; i < n; i++ {
			if fd := int(el.events[i].Fd); fd != p.wfd {
				if err = callback(fd, el.events[i].Events, nil); err != nil { //异步回调触发的事件
					return
				}
			} ... ...
		}
		... ...
	}
}

func (svr *server) acceptNewConnection(fd int) error {
	nfd, sa, err := unix.Accept(fd)
	if err != nil {
		if err == unix.EAGAIN {
			return nil
		}
		return err
	}
	if err := unix.SetNonblock(nfd, true); err != nil {
		return err
	}
	lp := svr.subLoopGroup.next() //分配一个subReactor
	c := newConn(nfd, lp, sa)
	_ = lp.poller.Trigger(func() (err error) {
		if err = lp.poller.AddRead(nfd); err != nil { //AddRead 内部调用了subReactor 内置 epoll 的 unix.EpollCtl
			return
		}
		lp.connections[nfd] = c
		err = lp.loopOpen(c)
		return
	})
	return nil
}

func (svr *server) startReactors() {
	svr.subLoopGroup.iterate(func(i int, lp *loop) bool {
		svr.wg.Add(1)
		go func() {
			svr.activateSubReactor(lp)
			svr.wg.Done()
		}()
		return true
	})
}

func (svr *server) activateSubReactor(lp *loop) {
	... ... // 事件循环在每个subReactor内部独立运行, 充分利用多核. 
	_ = lp.poller.Polling(func(fd int, ev uint32, job internal.Job) error { 
		if c, ack := lp.connections[fd]; ack {
			switch c.outboundBuffer.IsEmpty() {
			case false:
				if ev&netpoll.OutEvents != 0 {
					return lp.loopOut(c)
				}
				return nil
			case true:
				if ev&netpoll.InEvents != 0 {
					return lp.loopIn(c) //读事件的处理
				}
				return nil
			}
		}
		return nil
	})
}

func (lp *loop) loopIn(c *conn) error {
	... ...
loopReact:
	out, action := lp.svr.eventHandler.React(c) //业务逻辑如果在React里阻塞, 整个loop也会阻塞. 需要放置在worker pool里处理.
	if len(out) != 0 {
		if frame, err := lp.svr.codec.Encode(out); err == nil {
			c.write(frame)
		}
		goto loopReact
	}
	... ...
}
```


<br>

# Swoole

<br>

Swoole 的 `Multi-Reactors` 模型:

<img src="https://raw.githubusercontent.com/paprikaLang/paprikaLang.github.io/imgs/epoll2.png" width="700">


**Main Thread** 负责监听服务端口接收网络连接, 将连接成功的I/O事件分发给 WorkThread .

<img src="https://raw.githubusercontent.com/paprikaLang/paprikaLang.github.io/imgs/epoll3.jpg" width="550">

<br>

**Work Thread**  在客户端注册的读事件上监听, 触发后再交给一个 Work Process 来处理读事件的业务逻辑;  WorkThread 会先接收到这个 Work Process 注册的写事件, 然后业务逻辑开始处理, 处理完成后触发此事件. 

<br>

**Work Process** 将数据收发和数据处理分离开来，因为客户端不会关心后台的如何处理数据,它们只需要及时的信息反馈. 

Worker Process 可以发起异步的 Task 任务(类似于 gnet 的 worker pool)处理耗时的操作, Task 底层使用 Unix Socket 管道通信，是全内存的，没有 IO 消耗. 不同的进程使用不同的管道通信，可以最大化利用多核.

<br>

WorkThread <=> Work Process 循环的过程类似 同步 I/O 模拟的 Proactor 模式: 

<img src="https://raw.githubusercontent.com/paprikaLang/paprikaLang.github.io/imgs/epoll4.jpg" width="700">

最后附一张 swoole 整体流程图(也可以和gnet的做下对比):

<img src="https://raw.githubusercontent.com/paprikaLang/paprikaLang.github.io/imgs/epoll6.png" width="700">

<br>

*其他链接*

[百万 Go TCP 连接的思考2: 百万连接的吞吐率和延迟](https://colobu.com/2019/02/27/1m-go-tcp-connection-2/)


