//
//  UserInfoViewController.h
//  RJIterator
//
//  Created by renjinkui on 2018/4/14.
//  Copyright © 2018年 renjinkui. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UserInfoViewController : UIViewController
@property (nonatomic, copy) NSString *uid;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) UIImage *headimg;
@end
