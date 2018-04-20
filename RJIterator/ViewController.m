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
@property (nonatomic, strong) NSHashTable *ht;
@property (nonatomic, strong) UIViewController *vc;
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
//    [TestsSwift verboseTests];
}

- (void)dealloc {
    NSLog(@"== %@ dealloc", self);
}

//登录
- (RJAsyncClosure)loginWithAccount:(NSString *)account pwd:(NSString *)pwd {
    //返回RJAsyncClosure类型block
    return ^(RJAsyncCallback callback){
        //以dispatch_after模拟Http请求
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            //登录成功
            callback(@{@"uid": @"0001", @"token": @"ffccdd566"}, nil);
        });
    };
}

//查询信息
- (RJAsyncClosure)queryInfoWithUid:(NSString *)uid token:(NSString *)token{
    return ^(RJAsyncCallback callback){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            //查询成功
            callback(@{@"url": @"http://oem96wx6v.bkt.clouddn.com/bizhi-1030-1097-2.jpg", @"name": @"LiLei"},
                     /*[NSError errorWithDomain:NSURLErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Query error, please check network"}]*/nil
                     );
        });
    };
}

//下载头像
- (RJAsyncClosure)downloadHeadImage:(NSString *)url{
    return ^(RJAsyncCallback callback){
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            //下载头像
            NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
            callback(data ? [UIImage imageWithData:data] : nil,
                     data ? nil : [NSError errorWithDomain:NSURLErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Download error, please check network"}]);
        });
    };
}

//处理头像
- (RJAsyncClosure)handle:(UIImage *)image{
    return ^(RJAsyncCallback callback){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            //处理成功
            callback(image, nil);
        });
    };
}

#define toast NSLog

- (void)onLogin:(id)sender {
    rj_async(^{
        //每次await 的 result
        RJResult *result = nil;
        
        _loginButton.enabled = NO;
        [_loginButton setTitle:@"登录中..." forState:UIControlStateNormal];
        
        NSLog(@"开始登录...");
        result = rj_await( [self loginWithAccount:@"112233" pwd:@"12345"] );
        if (result.error) {
            toast(@"登录失败, error:%@", result.error);
            return ;
        }
        NSDictionary *login_josn = result.value;
        NSLog(@"登录完成,json: %@", login_josn);
        
        NSLog(@"开始拉取个人信息...");
        result = rj_await( [self queryInfoWithUid:login_josn[@"uid"] token:login_josn[@"token"]] );
        if (result.error) {
            toast(@"拉取个人信息失败, error:%@", result.error);
            return ;
        }
        NSDictionary *info_josn = result.value;
        NSLog(@"拉取个人信息完成,json: %@", info_josn);
        
        NSLog(@"开始下载头像...");
        result = rj_await( [self downloadHeadImage:info_josn[@"url"]] );
        if (result.error) {
            toast(@"下载头像失败, error:%@", result.error);
            return ;
        }
        UIImage *head_image = result.value;
        NSLog(@"下载头像完成,head_image: %@", head_image);
        
        NSLog(@"开始处理头像...");
        result = rj_await( [self handle:head_image] );
        if (result.error) {
            toast(@"处理头像失败, error:%@", result.error);
            return ;
        }
        head_image = result.value;
        NSLog(@"处理头像完成,head_image: %@", head_image);

        NSLog(@"全部完成,进入详情界面");

        UserInfoViewController *vc = [[UserInfoViewController alloc] init];
        vc.uid = login_josn[@"uid"];
        vc.token = login_josn[@"token"];
        vc.name = info_josn[@"name"];
        vc.headimg = head_image;
        [self presentViewController:vc animated:YES completion:NULL];
    })
    .finally(^{
        NSLog(@"...finally 收尾");
        _loginButton.enabled = YES;
        [_loginButton setTitle:@"登录" forState:UIControlStateNormal];
    });
}



- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
