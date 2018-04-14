//
//  ViewController.m
//  RJIterator
//
//  Created by renjinkui on 2018/4/13.
//  Copyright © 2018年 renjinkui. All rights reserved.
//

#import "ViewController.h"
#import "Tests.h"
#import "RJIterator-Swift.h"
#import "RJIterator.h"
#import "UserInfoViewController.h"

@interface ViewController ()
@property (nonatomic, strong) UIButton *loginButton;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
     _loginButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_loginButton setTitle:@"登录" forState:UIControlStateNormal];
    [_loginButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _loginButton.backgroundColor = [UIColor blueColor];
    [_loginButton addTarget:self action:@selector(onLogin:) forControlEvents:UIControlEventTouchUpInside];
    _loginButton.frame = CGRectMake(0, 0, 100, 50);
    _loginButton.center = self.view.center;
    
    [self.view addSubview:_loginButton];
    
//    [Tests verboseTest];
    [TestsSwift verboseTests];
}


- (RJAsyncClosure)loginWithAccount:(NSString *)account pwd:(NSString *)pwd {
    return ^(RJAsyncCallback callback){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            callback(@{@"uid": @"0001", @"token": @"ffccdd566"}, nil);
        });
    };
}

- (RJAsyncClosure)queryInfoWithUid:(NSString *)uid token:(NSString *)token{
    return ^(RJAsyncCallback callback){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            callback(@{@"url": @"http://oem96wx6v.bkt.clouddn.com/bizhi-1030-1097-2.jpg", @"name": @"LiLei"},
                     /*[NSError errorWithDomain:NSURLErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Query error, please check network"}]*/nil
                     );
        });
    };
}

- (RJAsyncClosure)downloadHeadImage:(NSString *)url{
    return ^(RJAsyncCallback callback){
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
            callback(data ? [UIImage imageWithData:data] : nil,
                     data ? nil : [NSError errorWithDomain:NSURLErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Download error, please check network"}]);
        });
    };
}

- (RJAsyncClosure)makeEffect:(UIImage *)image{
    return ^(RJAsyncCallback callback){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            callback(image, nil);
        });
    };
}

- (void)onLogin:(id)sender {
    NSLog(@"==enter %s", __func__);
    NSLog(@"...begin");
    rj_async(^{
        _loginButton.enabled = NO;
        [_loginButton setTitle:@"登录中..." forState:UIControlStateNormal];
        
        NSLog(@"...begin login");
        NSDictionary *login_josn = rj_yield( [self loginWithAccount:@"112233" pwd:@"12345"] );
        NSLog(@"login_josn finish: %@", login_josn);
        
        NSLog(@"...begin query info");
        NSDictionary *query_json = rj_yield( [self queryInfoWithUid:login_josn[@"uid"] token:login_josn[@"token"]] );
        NSLog(@"query info finish: %@", query_json);
        
        NSLog(@"...begin download image");
        UIImage *image = rj_yield( [self downloadHeadImage:query_json[@"url"]] );
        NSLog(@"download image finish: %@", image);
        
        NSLog(@"...begin make image effect");
        UIImage *beautiful_image = rj_yield( [self makeEffect:image] );
        NSLog(@"make image effect finish: %@", beautiful_image);
        
        NSLog(@"all done");
        
        UserInfoViewController *vc = [[UserInfoViewController alloc] init];
        vc.uid = login_josn[@"uid"];
        vc.token = login_josn[@"token"];
        vc.name = query_json[@"name"];
        vc.headimg = beautiful_image;
        [self presentViewController:vc animated:YES completion:NULL];
    })
    .error(^(id error) {
        NSLog(@"error happened: %@", error);
    })
    .finally(^{
        NSLog(@"... finish");
        _loginButton.enabled = YES;
        [_loginButton setTitle:@"登录" forState:UIControlStateNormal];
    });
    NSLog(@"==leave %s", __func__);
}



- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
