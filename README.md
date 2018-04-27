生成器与迭代器是ES6和Python的重要概念，初次接触后感受到它们的强大，尤其是在异步调用方面的运用.

RJIterator是该功能的OC实现,可以在OC/Swift项目中使用.

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
使用rj_async声明一个异步块,块内是同步风格编写的代码,但将以异步方式调度执行.

Objective-C:
```Objective-C
rj_async(^{
    //同步风格的代码
})
.finally(^{
    //收尾,总会走这里
});
```

Swift:
```Swift
rj_async {
   //...
}
.finally {
    //...
}
```

#### 以登录举例

比如有这样的登录场景: 登录成功 --> 查询个人信息 --> 下载头像 --> 给头像加特效 --> 进入详情.

##### 为了举例，假设要求每一步必须在上一步完成之后进行.
该功能可以使用异步块如下实现:

##### （1) 定义异步任务

```Objective-C
//登录
- (RJAsyncClosure)loginWithAccount:(NSString *)account pwd:(NSString *)pwd { 
   //返回RJAsyncClosurele类型block
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

##### （2)以同步风格编写代码 
```Objective-C
- (void)onLogin:(id)sender {
    rj_async(^{
        //每次await 的 result
        RJResult *result = nil;
        
        [ProgressHud show];
        
        //开始登录...
        result = rj_await( [self loginWithAccount:@"112233" pwd:@"12345"] );
        if (result.error) {
            //登录失败
            return ;
        }
        //登录完成
        NSDictionary *login_josn = result.value;
        
        //开始拉取个人信息...
        result = rj_await( [self queryInfoWithUid:login_josn[@"uid"] token:login_josn[@"token"]] );
        if (result.error) {
            //拉取个人信息失败
            return ;
        }
        //拉取个人信息完成
        NSDictionary *info_josn = result.value;
        
        //开始下载头像...
        result = rj_await( [self downloadHeadImage:info_josn[@"url"]] );
        if (result.error) {
            //下载头像失败
            return ;
        }
        //下载头像完成
        UIImage *head_image = result.value;
        
        //开始处理头像
        result = rj_await( [self makeEffect:head_image] );
        if (result.error) {
            //处理头像失败
            return ;
        }
        //处理头像完成
        head_image = result.value;

        //全部完成,进入详情界面
        UserInfoViewController *vc = [[UserInfoViewController alloc] init];
        vc.uid = login_josn[@"uid"];
        vc.token = login_josn[@"token"];
        vc.name = info_josn[@"name"];
        vc.headimg = head_image;
        [self presentViewController:vc animated:YES completion:NULL];
    })
    .finally(^{
        //收尾
       [ProgressHud dismiss];
    });
}
```

rj_async块内部完全以同步方式编写，通过把异步任务包装进rj_await()，rj_async会自动以异步方式调度它们，不会阻塞主流程，在主观感受上，它们是同步代码,功能逻辑也比较清晰.实际上，任何"等待异步回调 -> 下一步"类型的逻辑都可以转化成如上的写法.

##### rj_async块内部运行在主线程，可以直接在块内部进行UI操作. 
##### rj_await可以理解为:"等待异步任务完成并返回结果"，但是这种等待是不阻塞主线程的. 


RJIterator兼容PromiseKit.如果已有自己的一个Promise，可以在异步块内直接传给rj_await()，它会被正确异步调度, 但是只支持AnyPromise,如果不是AnyPromise,如果可以转化的话，使用PromiseKit提供的相关方法转为AnyPromise再使用.
比如:
```Swift
rj_async {
  let fetchImage = URLSession.shared.dataTask(.promise, with: URL.init(string: "http://oem96wx6v.bkt.clouddn.com/bizhi-1030-1097-2xx.jpg")!).compactMap{ UIImage(data: $0.data) }
  let result = rj_await( AnyPromise.init(fetchImage) )
  if let error = result.error {
      print("下载头像失败:\(error)")
      return
  }
  let image = result.value as! UIImage
  print("下载头像成功, image:\(image)")
}
```

下面是该登录功能举例对应的Swift写法:
```Swift
 //登录
    func login(account: String, pwd: String) -> RJAsyncClosure {
        //返回RJAsyncClosure类型闭包
        return { (callback: @escaping RJAsyncCallback) in
            //以asyncAfter 模拟Http请求 + 回调
            DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 2, execute: {
                //登录成功
                callback(["uid": "80022", "token":"67625235555"], nil);
            })
        };
    }
    //查询个人信息
    func query(uid:String, token: String) -> RJAsyncClosure {
        return { (callback: @escaping RJAsyncCallback) in
            //以asyncAfter 模拟Http请求 + 回调
            DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 2, execute: {
                //查询成功
                callback(["name": "JimGreen", "url":"http://oem96wx6v.bkt.clouddn.com/bizhi-1030-1097-2.jpg"], NSError.init(domain: "s2", code: -1, userInfo: nil));
            })
        };
    }
    //下载头像
    func download(url: String) -> RJAsyncClosure {
        return {(callback: @escaping RJAsyncCallback) in
            DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 2, execute: {
                do {
                    let data: Data? = try Data.init(contentsOf: URL.init(string: url)!)
                    let iamge = UIImage.init(data: data!)
                    //下载成功
                    callback(iamge, nil)
                } catch let error {
                    //下载失败
                    callback(nil, error)
                }
            })
        };
    }
    //处理头像
    func makeEffect(image: UIImage) -> RJAsyncClosure {
        return { (callback: @escaping RJAsyncCallback) in
            DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 2, execute: {
                //处理成功
                callback(image, nil);
            })
        };
    }

    @objc func onLogin(_ sender: Any? = nil) {
        rj_async {
            //每次await 的 result
            var result: RJResult
            
            ProgressHud.show()
            
            //开始登录
            result = rj_await( self.login(account: "112233", pwd: "445566") )
            if let error = result.error {
                //登录失败
                return
            }
            //登录成功
            let login_json = result.value as! [String: String]
            
            //开始查询信息
            result = rj_await( self.query(uid: login_json["uid"]!, token: login_json["token"]!) )
            if let error = result.error {
                //查询信息失败
                return
            }
            //查询信息成功
            let info_json = result.value as! [String: String]
            
            //开始下载头像
            result = rj_await( self.download(url: info_json["url"]!) )
            if let error = result.error {
                //下载头像失败
                return
            }
            //下载头像成功
            let image = result.value as! UIImage
            
            //开始处理头像
            result = rj_await( self.makeEffect(image: image) )
            if let error = result.error {
                //处理头像失败
                return
            }
            //处理头像成功
            let beautiful_image = result.value as! UIImage
            
            //进入详情界面
        }
        .finally {
             //登录收尾
             ProgressHud.dismiss()
        }
    }
```

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

##### 对比Promise链实现
```Objective-C
//登录
- (AnyPromise *)loginWithAccount:(NSString *)account pwd:(NSString *)pwd {
    //返回AnyPromise
    return [AnyPromise promiseWithAdapterBlock:^(PMKAdapter  _Nonnull adapter) {
        //以dispatch_after模拟Http请求
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            //登录成功
            adapter(@{@"uid": @"0001", @"token": @"ffccdd566"}, nil);
        });
    }];
}

//查询信息
- (AnyPromise *)queryInfoWithUid:(NSString *)uid token:(NSString *)token{
    return [AnyPromise promiseWithAdapterBlock:^(PMKAdapter  _Nonnull adapter) {
        //以dispatch_after模拟Http请求
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            //查询成功
            adapter(@{@"url": @"http://oem96wx6v.bkt.clouddn.com/bizhi-1030-1097-2.jpg", @"name": @"LiLei"},
                     /*[NSError errorWithDomain:NSURLErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Query error, please check network"}]*/nil
                     );
        });
    }];
}

//下载头像
- (AnyPromise *)downloadHeadImage:(NSString *)url{
    return [AnyPromise promiseWithAdapterBlock:^(PMKAdapter  _Nonnull adapter) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            //下载头像
            NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
            adapter(data ? [UIImage imageWithData:data] : nil,
                     data ? nil : [NSError errorWithDomain:NSURLErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Download error, please check network"}]);
        });
    }];
}

//处理头像
- (AnyPromise *)makeEffect:(UIImage *)image{
    return [AnyPromise promiseWithAdapterBlock:^(PMKAdapter  _Nonnull adapter) {
        //以dispatch_after模拟处理过程
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            //处理成功
            adapter(image, nil);
        });
    }];
}

- (void)onLogin:(id)sender {
    //开始登录
    NSString *__block uid = @"";
    NSString *__block token = @"";
    NSString *__block name = @"";
    
    [self loginWithAccount:@"112233" pwd:@"445566"]
    .then(^(NSDictionary *json){
        //登录成功
        uid = json[@"uid"];
        token = json[@"token"];
        //开始查询信息
        return [self queryInfoWithUid:json[@"uid"] token:json[@"token"]];
    })
    .then(^(NSDictionary *json){
        //查询信息成功
        name = json[@"name"];
        //开始下载头像
        return [self downloadHeadImage:json[@"url"]];
    })
    .then(^(UIImage *image){
        //下载头像成功
        //开始处理头像
        return [self makeEffect:image];
    })
    .then(^(UIImage *image){
        //处理头像成功
        //进入详情
        UserInfoViewController *vc = [[UserInfoViewController alloc] init];
        vc.uid = uid;
        vc.token = token;
        vc.name = name;
        vc.headimg = image;
        [self presentViewController:vc animated:YES completion:NULL];
    })
    .catch(^(id error) {
        //出错
    })
    .ensure(^{
        //收尾
    });
}
```

1.catch到error后其实根本不知道具体是哪一步出错了,除非对每个error做明显标识，如果对每个error处理方式不同的话，catch块内难免if else:
```Objective-C
if (error.code == LOGIN_ERROR) {
    //登录出错处理
}
else if (error.code == QUERY_ERROR) {
    //查询信息出错处理
}
else if (error.code == DOWNLOAD_ERROR) {
    //下载出错处理
}
else if (error.code == MAKE_EFFECT_ERROR) {
    //处理头像出错处理
}
```

2.每个then块内的变量作用域是局部的，假设要在后面某个then块B内访问A块内得到的数据，除非把A块内的局部变量提成全局的,就像`uid,token,name`，因为在最后一个then块需要用来赋值给详情界面控制器,或者将它们作为参数层层传递到B块,都不够方便.

3.程序逻辑分散在过多的代码块.

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

## 安装
pod

```
use_frameworks!

pod 'RJIterator', '~> 1.1.5'

#import <RJIterator/RJIterator.h>

import PromiseKit
```

手动: 

RJIterator基于MRC管理内存,混有一个Swift文件， 所以手动添加进去还要改配置，加Bridge Header, 比较麻烦,建议pod



  
    
    
    
    
    
    
=========补充线 20180427=======

#### 为何rj_async,rj_await不支持catch
假如支持catch，出错后统一跳转到catch块:
```Objective-C
rj_async {^
   //await直接等到value,而不是RJResult对象，包含error和value
   id value = rj_await(异步操作);
   id value = rj_await(异步操作);
   id value = rj_await(异步操作);
}
.catch(^(id error) {
  //出错处理
})
.finally(^{
   //收尾
});
```
支持统一catch错误，确实比起目前的版本用起来更加直观方便，几乎100%贴近JS下async/await的用法了.

其实，最初版就是这样实现的,但是经过推敲后发现一个无法解决的问题: `catch`引发内存泄露.

假如在上面的代码中，在异步块开始处分配了一个对象,那么一旦接下来的某个await过程触发异常了，将造成对象无法释放的问题:

![](http://oem96wx6v.bkt.clouddn.com/%E5%B1%8F%E5%B9%95%E5%BF%AB%E7%85%A7%202018-04-25%20%E4%B8%8B%E5%8D%884.49.40.png)

如上图所示,异步块首先分配了一个对象object,然后进行三个await操作，假设在第二个await的过程中，发生错误，那么程序执行流直接略过后面的所有代码，进入catch块处理错误。

实际上这时不管在MRC，还是ARC下，object都无法得到释放。在ARC下，大部分情况下编译器为object生成的释放代码都处于代码块末端：

![](http://oem96wx6v.bkt.clouddn.com/%E5%B1%8F%E5%B9%95%E5%BF%AB%E7%85%A7%202018-04-25%20%E4%B8%8B%E5%8D%885.15.50.png)

如果执行流从中间断开了，那么这些释放代码永远执行不到，将造成“每逢出错必泄露”。而这种第三方实现的异常方式有别OC原生方式，无法获得编译器对”异常后内存泄露“问题的修复支持。

因此，在使用rj_async/rj_await进行异步编程的过程中，每一步await后要怎么处理错误，由每一步自己决定，不再统一跳转到catch块.且事实上实际开发场景中，每一步的出错处理方式是不同的，至少提示方式都不同，因此统一跳转到catch块处理错误的方式在大部分情况下反而造成不便。

