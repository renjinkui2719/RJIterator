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
            [ProgressHud show];
            NSLog(@"Error happened:%@", error);
        }
        else {
            NSDictionary *json = (NSDictionary *)value;
            [self queryInfoWithUid:json[@"uid"] token:json[@"token"] callback:^(id value, id error) {
                if (error) {
                    [ProgressHud show];
                    NSLog(@"Error happened:%@", error);
                }
                else {
                    NSDictionary *json = (NSDictionary *)value;
                    [self downloadHeadImage:json[@"url"] callback:^(id value, id error) {
                        if (error) {
                            [ProgressHud show];
                            NSLog(@"Error happened:%@", error);
                        }
                        else {
                            UIImage *image = (UIImage *)value;
                            [self makeEffect:image callback:^(id value, id error) {
                                if (error) {
                                    [ProgressHud show];
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

```Objective-C
- (RJAsyncClosure)loginWithAccount:(NSString *)account pwd:(NSString *)pwd {
    return ^(RJAsyncCallback callback){
        post(@"/login", account, pwd, ^(id response, error) {
            callback(response.data, error);
        });
    };
}
- (RJAsyncClosure)queryInfoWithUid:(NSString *)uid token:(NSString *)token{
    return ^(RJAsyncCallback callback){
        get(@"query", uid, token, ^(id response, error) {
            callback(response.data, error);
        });
    };
}
- (RJAsyncClosure)downloadHeadImage:(NSString *)url{
    return ^(RJAsyncCallback callback){
        get(@"file", url, ^(id response, error) {
            callback(response.data, error);
        });
    };
}
- (RJAsyncClosure)makeEffect:(UIImage *)image{
    return ^(RJAsyncCallback callback){
        make(image, ^(id data, error) {
            callback(data, error);
        });
    };
}
- (void)onLogin:(id)sender {
    [ProgressHud show];
    rj_async(^{
        NSDictionary *login_josn = rj_yield( [self loginWithAccount:@"112233" pwd:@"12345"] );
        NSDictionary *query_json = rj_yield( [self queryInfoWithUid:login_josn[@"uid"] token:login_josn[@"token"]] );
        UIImage *image = rj_yield( [self downloadHeadImage:query_json[@"url"]] );
        NSString *beautiful_image = rj_yield( [self makeEffect:image] );
        NSLog(@"all done");
    })
    .error(^(id error) {
        NSLog(@"error happened");
    })
    .finally(^{
        [ProgressHud dismise];
    });
}

[self loginWithAccount:@"112233" pwd:@"12345"].promise
.then(^(NSDictionary *json) {
    return [self queryInfoWithUid:login_josn[@"uid"] token:login_josn[@"token"]].promise
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
    [ProgressHud dismise];
});
```
