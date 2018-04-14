生成器与迭代器是ES6和Python的重要概念，初次接触后感受到它们的强大，尤其是在异步调用方面的运用.RJIterator是该功能的OC实现,可以在OC/Swift项目中使用.

#### 1. 异步的优化

##### 异步调用
在RJIterator中, 任何返回RJAsyncClosure类型的OC/Swift方法都属于异步调用，比如:
```Objective-C
- (RJAsyncClosure)foo:(id)arg1 arg2:(id)arg2 /*...其他参数*/{
    return ^(RJAsyncCallback callback){
        do_something(^{
            callback(data, error);
        });
    };
}
```
RJAsyncClosure 是RJIterator定义的闭包类型： 
```Objective-C
typedef void (^RJAsyncCallback)(id _Nullable value, id _Nullable error);
typedef void (^RJAsyncClosure)(RJAsyncCallback _Nonnull callback);
```
返回该类型可以理解为返回了一个包含任务内容的代码块，以供稍后调度.

#### 异步块
使用rj_async声明一个异步块,表示代码块内部将以异步方式调度执行

```Objective-C
rj_async {
    //异步代码
}
.error(^(id error) {
    //出错处理
})
.finally(^{
    //收尾 不论成功还是出错都会执行
});
```

#### 以登录举例

比如有这样的登录场景: 登录成功 --> 查询个人信息 --> 下载头像 --> 给头像加特效 --> 进入详情.

要求每一步必须在上一步完成之后进行. 该功能可以使用异步块如下实现

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


##### 对比普通回调发送编写代码 
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
    return [self queryInfoWithUid:json[@"uid"] token:json[@"token"]].promise
})
.then(^(NSDictionary *json) {
    return [self downloadHeadImage:json[@"url"]].promise
})
.then(^(UIImage *image) {
    return [self makeEffect:image].promise
})
.then(^(UIImage *image) {
    /*All done*/
})
.error(^(id error) {
    NSLog(@"error happened");
})
.finally(^{
    [ProgressHud dismiss];
});
```

#### 2.生成器与迭代器

生成器与迭代器的概念及用法, 以及在异步调用上的运用. 可以参考ES6教程

http://www.infoq.com/cn/articles/es6-in-depth-generators

http://es6.ruanyifeng.com/#docs/generator

##### 在RJIterator中,满足以下条件的c/Objective-C/Swift方法,闭包即可以作为生成器:

(1)返回值为id或void,接受最多8个id参数的OC类方法,实例方法,block;c函数;Swift类方法,实例方法.


(2)返回值为id,接受一个参数的Swift函数,闭包.

