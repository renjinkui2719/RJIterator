//
//  UserInfoViewController.m
//  RJIterator
//
//  Created by renjinkui on 2018/4/14.
//  Copyright © 2018年 renjinkui. All rights reserved.
//

#import "UserInfoViewController.h"

@interface UserInfoViewController ()

@end

@implementation UserInfoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor whiteColor];
    
    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    close.frame = CGRectMake(10, 80, 60, 50);
    [self.view addSubview:close];

    
    UIImageView *imgv = [[UIImageView alloc] initWithImage:_headimg];
    imgv.frame = CGRectMake(0, 0, 100, 100);
    imgv.center = self.view.center;
    [self.view addSubview:imgv];
    
    UILabel *infoLabel = [UILabel new];
    infoLabel.text = [NSString stringWithFormat:@"Hello: %@, you uid:%@, token:%@", _name, _uid, _token];
    infoLabel.textColor = [UIColor blackColor];
    infoLabel.textAlignment = NSTextAlignmentCenter;
    infoLabel.numberOfLines = 0;
    infoLabel.frame = CGRectMake(0, CGRectGetMaxY(imgv.frame), self.view.frame.size.width, 80.0);
    [self.view addSubview:infoLabel];
}

- (void)close {
    [self.presentingViewController dismissViewControllerAnimated:YES completion:NULL];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
