生成器与迭代器是ES6和Python的重要概念，初次接触后感受到它们的强大，尤其是在异步调用方面的运用.RJIterator是该功能的OC实现,可以在OC/Swift项目中使用.

#### 1. 异步的运用

##### 异步任务
在RJIterator中,一个RJAsyncClosure类型的闭包就是一个异步任务,可以被异步调度

RJAsyncClosure 是RJIterator定义的闭包类型：

```Objective-C
typedef void (^RJAsyncCallback)(id _Nullable value, id _Nullable error);
typedef void (^RJAsyncClosure)(RJAsyncCallback _Nonnull callback);
```

同时，RJIterator兼容PromiseKit，RJIterator会在运行时判断，如果一个对象是AnyPromise类型,也是异步任务.


#### 异步块
使用rj_async声明一个异步块,表示代码块内部将以异步方式调度执行

Objective-C:
```Objective-C
rj_async(^{
    //异步代码
})
.error(^(id error) {
    //出错处理
})
.finally(^{
    //收尾 不论成功还是出错都会执行
});
```

Swift:
```Swift
rj_async {
   //...
}
.error {error in
    let error = error as! MyErrorType
    //...
}
.finally {
    //...
}
```

#### 以登录举例

比如有这样的登录场景: 登录成功 --> 查询个人信息 --> 下载头像 --> 给头像加特效 --> 进入详情.

为了举例，假设要求每一步必须在上一步完成之后进行. 该功能可以使用异步块如下实现

##### （1) 定义异步任务

```Objective-C
//登录
- (RJAsyncClosure)loginWithAccount:(NSString *)account pwd:(NSString *)pwd {
    return ^(RJAsyncCallback callback){
       //调用http接口
        post(@"/login", account, pwd, ^(id response, error) {
            callback(response.data, error);
        });
    };
}
//拉取信息
- (RJAsyncClosure)queryInfoWithUid:(NSString *)uid token:(NSString *)token{
    return ^(RJAsyncCallback callback){
        get(@"query", uid, token, ^(id response, error) {
            callback(response.data, error);
        });
    };
}
//下载头像
- (RJAsyncClosure)downloadHeadImage:(NSString *)url{
    return ^(RJAsyncCallback callback){
        get(@"file", url, ^(id response, error) {
            callback(response.data, error);
        });
    };
}
//处理头像
- (RJAsyncClosure)makeEffect:(UIImage *)image{
    return ^(RJAsyncCallback callback){
        make(image, ^(id data, error) {
            callback(data, error);
        });
    };
}
```

##### （2)以同步方式编写代码 
```Objective-C
- (void)onLogin:(id)sender {
    [ProgressHud show];
    rj_async(^{
        NSDictionary *login_josn = rj_yield( [self loginWithAccount:@"112233" pwd:@"12345"] );
        NSDictionary *query_json = rj_yield( [self queryInfoWithUid:login_josn[@"uid"] token:login_josn[@"token"]] );
        UIImage *image = rj_yield( [self downloadHeadImage:query_json[@"url"]] );
        NSString *beautiful_image = rj_yield( [self makeEffect:image] );
        NSLog(@"all done");
        //进入详情界面
     })
    .error(^(id error) {
        NSLog(@"error happened");
    })
    .finally(^{
        [ProgressHud dismiss];
    });
}
```

rj_async块内部完全以同步方式编写，通过把异步任务包装进rj_yield()，rj_async会自动以异步方式调度它们，不会阻塞主流程，在主观感受上，它们是同步代码,功能逻辑也比较清晰. 

##### rj_async块内部运行在主线程，可以直接在块内部进行UI操作. 
这里async的含义并不是启动子线程来执行块，而是块内部以异步方式调度。异步指的是不阻塞,异步不一定就是子线程。

RJIterator兼容PromiseKit.如果已有自己的一个Promise，可以在异步块内直接传给rj_yield()，它会被正确异步调度, 但是只支持AnyPromise,如果不是AnyPromise,如果可以转化的话，使用PromiseKit提供的相关方法转为AnyPromise再使用.


##### 对比普通回调方式编写代码 
如果以普通回调方式,则不论如何逃不出如下模式:

```Objective-C
- (void)loginWithAccount:(NSString *)account pwd:(NSString *)pwd callback:(void (^)(id value, id error))callback {
    post(@"/login", account, pwd, ^(id response, error) {
        callback(response.data, error);
    });
}
- (void)queryInfoWithUid:(NSString *)uid token:(NSString *)token  callback:(void (^)(id value, id error))callback{
    get(@"query", uid, token, ^(id response, error) {
        callback(response.data, error);
    });
}
- (void)downloadHeadImage:(NSString *)url callback:(void (^)(id value, id error))callback{
    get(@"file", url, ^(id response, error) {
        callback(response.data, error);
    });
}
- (void)makeEffect:(UIImage *)image callback:(void (^)(id value, id error))callback{
    make(image, ^(id data, error) {
        callback(data, error);
    });
}

- (void)onLogin:(id)sender {
    [ProgressHud show];
    [self loginWithAccount:@"112233" pwd:@"112345" callback:^(id value, id error) {
        if (error) {
            [ProgressHud dismiss];
            NSLog(@"Error happened:%@", error);
        }
        else {
            NSDictionary *json = (NSDictionary *)value;
            [self queryInfoWithUid:json[@"uid"] token:json[@"token"] callback:^(id value, id error) {
                if (error) {
                    [ProgressHud dismiss];
                    NSLog(@"Error happened:%@", error);
                }
                else {
                    NSDictionary *json = (NSDictionary *)value;
                    [self downloadHeadImage:json[@"url"] callback:^(id value, id error) {
                        if (error) {
                            [ProgressHud dismiss];
                            NSLog(@"Error happened:%@", error);
                        }
                        else {
                            UIImage *image = (UIImage *)value;
                            [self makeEffect:image callback:^(id value, id error) {
                                if (error) {
                                    [ProgressHud dismiss];
                                    NSLog(@"Error happened:%@", error);
                                }
                                else {
                                    [ProgressHud dismiss];
                                    UIImage *image = (UIImage *)value;
                                    /*
                                     All done
                                     */
                                }
                            }];
                        }
                    }];
                }
            }];
        }
    }];
}
```
这时 onLogin方法就掉进了传说中的回调地狱

##### 对比Promise链
```Objective-C
[ProgressHud show];

[self loginWithAccount:@"112233" pwd:@"12345"].promise
.then(^(NSDictionary *json) {
    return [self queryInfoWithUid:json[@"uid"] token:json[@"token"]].promise;
})
.then(^(NSDictionary *json) {
    return [self downloadHeadImage:json[@"url"]].promise;
})
.then(^(UIImage *image) {
    return [self makeEffect:image].promise;
})
.then(^(UIImage *image) {
    /*All done*/
})
.catch(^(id error) {
    NSLog(@"error happened");
})
.finally(^{
    [ProgressHud dismiss];
});
```

#### 2.生成器与迭代器

生成器与迭代器的概念及用法. 可以参考ES6教程

http://www.infoq.com/cn/articles/es6-in-depth-generators

http://es6.ruanyifeng.com/#docs/generator

##### 在RJIterator中,满足以下条件的C/Objective-C/Swift方法,闭包即可以作为生成器:

(1)返回值为id或void,接受最多8个id参数的OC类方法,实例方法,block;c函数;Swift类方法,实例方法.


(2)返回值为id,接受一个参数的Swift函数,闭包.

生成器不能直接调用，需要通过RJIterator类的初始化方法创建迭代器，再通过迭代器访问生成器:

```Objective-C
- (id _Nonnull)initWithFunc:(RJGenetarorFunc _Nonnull)func arg:(id _Nullable)arg;
- (id _Nonnull)initWithTarget:(id _Nonnull)target selector:(SEL _Nonnull)selector, ...;
- (id _Nonnull)initWithBlock:(id _Nonnull)block, ...;
- (id _Nonnull)initWithTarget:(id _Nonnull)target selector:(SEL _Nonnull)selector args:(NSArray *_Nullable)args;
- (id _Nonnull)initWithBlock:(id _Nullable (^ _Nonnull)(id _Nullable))block arg:(id _Nullable)arg;
- (id _Nonnull)initWithStandardBlock:(dispatch_block_t _Nonnull)block;
```


##### 低配版聊天机器人
假设talk是个会说话的机器人，按一下它回一句.则可以如下实现talk

```Swift
func talk(arg: Any?) -> Any? {
    rj_yield("Hello, How are you?");
    rj_yield("Today is Friday");
    rj_yield("So yestday is Thursday");
    rj_yield("And tomorrow is Saturday");
    rj_yield("Over");
    return "==talk done==";
}
```

这时候talk就是一个生成器,每次调用都会返回“下一句话”.他会记住上次说到哪了.
调用方式必须是通过迭代器,所以下面先创建talk的迭代器，然后通过next方法依次获得应答.

```Swift
var it: RJIterator;
var r: RJResult;

it = RJIterator.init(withFunc: talk, arg: nil)
r = it.next()
print("value: \(r.value), done:\(r.done)")
//==> value: Hello How are you?, done:NO

r = it.next()
print("value: \(r.value), done:\(r.done)")
//==> value: Today is Friday, done:NO

r = it.next()
print("value: \(r.value), done:\(r.done)")
//==> value: So yestday is Thursday, done:NO

r = it.next()
print("value: \(r.value), done:\(r.done)")
//==> value: And tomorrow is Saturday, done:NO

r = it.next()
print("value: \(r.value), done:\(r.done)")
//==> value: Over, done:NO

r = it.next()
print("value: \(r.value), done:\(r.done)")
//==> value: ==talk done==, done:YES

r = it.next()
print("value: \(r.value), done:\(r.done)")
//==> value: ==talk done==, done:YES
```
RJResult是迭代器RJIterator每次next返回的结果值类型, 其中value表示结果数据, done表示是否迭代结束，结束表示生成器内部已经执行了尾部或者某处的return.

每次next调用,talk都会从rj_yield处返回，可以看作是暂时中断talk，等到再次执行next,talk又从上次中断的地方恢复继续执行，这种“切换”方式类似协程，只是RJIterator并不是一个完整的协程库，协程库大部分目的在于提高服务端性能，因此高效的协程调度很重要，而RJIterator核心在于实现yield原语和async块。


##### 新的需求
感觉还不够好，比如想要告诉机器人我的名字，以增进彼此感情.
修改talk:
```Swift
func talk(name: Any?) -> Any? {
    rj_yield("Hello \(name), How are you?");
    rj_yield("Today is Friday");
    rj_yield("So yestday is Thursday");
    rj_yield("And tomorrow is Saturday");
    rj_yield("Over");
    return "==talk done==";
}
```

并在创建迭代器的时候给它传参:
```Swift
it = RJIterator.init(withFunc: talk, arg: "乌卡卡")
```

这时候第一次调用next,将如下返回:
```
value: Hello 乌卡卡, How are you?, done:NO
```

##### 更新的需求
在第5次调用next和talk对话的时候，它回答了"Over"，并且再次迭代(第6次)它就会结束, 但如果还想再聊几轮,可以在第6次迭代的时候,给他传命令，告诉机器人再来一发。

修改talk:
```Swift
fileprivate func talk(name: Any?) -> Any? {
    var cmd = ""
    repeat {
        rj_yield("Hello \(name ?? ""), How are you?");
        rj_yield("Today is Friday");
        rj_yield("So yestday is Thursday");
        rj_yield("And tomorrow is Saturday");
        cmd = rj_yield("Over") as? String ?? "";
    }while cmd != "Over"
    
    return "==talk done==";
}
```
第6次调用next时传值
```Swift
r = it.next("again")
print("value: \(r.value), done:\(r.done)")
//value: value: Hello 乌卡卡, How are you?, done:NO
```

如果不传这个值，talk将按正常流程结束，但是传入"again"后它又从头开始了。 也就是生成器talk除了具备“中断+返回”的能力，还具备中间多次“传值进去”的能力，其中原理是: 
###### 给next传的值将作为生成器内部上次rj_yield的新返回值,并在生成器“苏醒”的时候赋值给左边"cmd"，如果next不传参,则该返回值就是rj_yield()本来包装的那个值. 通过这个特性，可以基于生成器与迭代器变种出新功能,rj_async块就是基于这个原理.

##### 生成器嵌套
生成器内部可以再嵌套调用别的生成器,比如要从1数到9，感觉工作量太大，所以定义3个生成器,每个负责数3个数, 再定义一个总的生成器，内部调用这三个小生成器
```Swift
func count_1_3(_: Any?) -> Any? {
    rj_yield(1)
    rj_yield(2)
    return 3
}
func count_4_5(_: Any?) -> Any? {
    rj_yield(4)
    rj_yield(5)
    return 6
}
func count_7_9(_: Any?) -> Any? {
    rj_yield(7)
    rj_yield(8)
    return 9
}

func count(_: Any?) -> Any? {
    rj_yield(RJIterator.init(withFunc: count_1_3, arg: nil))
    rj_yield(RJIterator.init(withFunc: count_4_5, arg: nil))
    rj_yield(RJIterator.init(withFunc: count_7_9, arg: nil))
    return nil
}
```
为count创建迭代器，连续执行next将得到value: 1, 2, 3, 4, 5, 6, 7, 8, 9


#### 可能
苹果文档透露Swift以后的版本可能会新增异步，多任务方面的新特性，所以以后的Swift有可能也会像JS一样支持async,yield,await等功能.

### 安装
pod

```
pod "RJIterator", "~> 1.1.3"
```

手动: 

RJIterator基于MRC管理内存,混有一个Swift文件， 所以手动添加进去还要改配置，加Bridge Header, 比较麻烦,建议pod

