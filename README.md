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
- (void)loadIntroduceFileWithCallback:(void (^)(id value, id error))callback{
    NSString *path = @"...";
    read(path, ^(id data, error) {
        callback(data.encodeUtfString, error);
    });
}

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
                        UIImage *image = (UIImage *)image;
                        [self loadIntroduceFileWithCallback:^(id value, id error) {
                            if (error) {
                                [ProgressHud show];
                                NSLog(@"Error happened:%@", error);
                            }
                            else {
                                [ProgressHud dismiss];
                                NSString *introduce = value;
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
- (RJAsyncClosure)loadIntroduceFile{
    return ^(RJAsyncCallback callback){
        NSString *path = @"...";
        read(path, ^(id data, error) {
            callback(data.encodeUtfString, error);
        });
    };
}
- (void)onLogin:(id)sender {
    [ProgressHud show];
    rj_async(^{
        NSDictionary *login_josn = rj_yield( [self loginWithAccount:@"112233" pwd:@"12345"] );
        NSDictionary *query_json = rj_yield( [self queryInfoWithUid:login_josn[@"uid"] token:login_josn[@"token"]] );
        UIImage *image = rj_yield( [self downloadHeadImage:query_json[@"url"]] );
        NSString *text = rj_yield( [self loadIntroduceFile] );
        NSLog(@"all done");
    })
    .error(^(id error) {
        NSLog(@"error happened");
    })
    .finally(^{
        [ProgressHud dismise];
    });
}
```
