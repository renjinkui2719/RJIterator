//
//  Tests.m
//  RJIterator
//
//  Created by renjinkui on 2018/4/13.
//  Copyright © 2018年 JK. All rights reserved.
//

#import "Tests.h"
#import <UIKit/UIKit.h>
#import "RJIterator.h"

static NSString* talk(NSString *name) {
    rj_yield([NSString stringWithFormat:@"Hello %@, How are you?", name]);
    rj_yield(@"Today is Friday");
    rj_yield(@"So yestday is Thursday");
    rj_yield(@"And tomorrow is Saturday");
    rj_yield(@"Over");
    return @"==talk done==";
}

@implementation Tests

+ (void)verboseTest {
    [self test1];
    [self test2];
    [self test3];
    [self test4];
    [self test5];
    [self test6];
    [self test7];
    [self test8];
}


+ (void)test1 {
    NSLog(@"************************ Begin %s *******************************", __func__);
    RJIterator *it = nil;
    RJResult *r = nil;
    
    it = [[RJIterator alloc] initWithFunc:talk arg:@"乌卡卡"];
    r = [it next];
    NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    r = [it next];
    NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    r = [it next];
    NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    r = [it next];
    NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    r = [it next];
    NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    r = [it next];
    NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    r = [it next];
    NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    
    NSLog(@"************************ End %s *******************************", __func__);
}

- (NSNumber *)Fibonacci {
    int prev = 0;
    int cur = 1;
    for (;;) {
        rj_yield(@(cur));
        
        int p = prev;
        prev = cur;
        cur = p + cur;
        
        if (cur > 6765) {
            break;
        }
    }
    return @(cur);
}

+ (void)test2 {
    NSLog(@"************************ Begin %s *******************************", __func__);
    RJIterator *it = nil;
    RJResult *r = nil;
    
    it = [[RJIterator alloc] initWithTarget:[self new] selector:@selector(Fibonacci)];
    for (int i = 0; i < 22; ++i) {
        r = [it next];
        NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    }
    
    NSLog(@"************************ End %s *******************************", __func__);
}

//迭代器嵌套
- (id)dataBox:(NSString *)name age:(NSNumber *)age {
    NSLog(@"==in dataBox/enter");
    rj_yield([NSString stringWithFormat:@"Hello, I know you name:%@, age:%@, you want some data", name, age]);
    rj_yield(@"Fibonacci:");
    NSLog(@"==in dataBox/will return Fibonacci");
    rj_yield([[RJIterator alloc] initWithTarget:self selector:@selector(Fibonacci)]);
    rj_yield(@"Random Data:");
    NSLog(@"==in dataBox/will return Random Data");
    rj_yield(@"🐶");
    rj_yield([NSArray new]);
    rj_yield(@12345);
    rj_yield(self);
    return @"dataBox Over";
}

//更深嵌套
- (id)dataBox2:(NSString *)name age:(NSNumber *)age {
    rj_yield([[RJIterator alloc] initWithTarget:self selector:@selector(dataBox:age:), name, age]);
    
    NSLog(@"==in dataBox2/enter");
    rj_yield([NSString stringWithFormat:@"Hello, I know you name:%@, age:%@, you want some data", name, age]);
    rj_yield(@"Fibonacci:");
    NSLog(@"==in dataBox2/will return Fibonacci");
    rj_yield([[RJIterator alloc] initWithTarget:self selector:@selector(Fibonacci)]);
    rj_yield(@"Random Data:");
    NSLog(@"==in dataBox2/will return Random Data");
    rj_yield(@"🐶");
    rj_yield([NSArray new]);
    rj_yield(@12345);
    rj_yield(self);
    return @"dataBox2 Over";
}

+ (void)test3 {
    NSLog(@"************************ Begin %s *******************************", __func__);
    RJIterator *it = nil;
    RJResult *r = nil;
    
    it = [[RJIterator alloc] initWithTarget:[self new] selector:@selector(dataBox:age:), @"大表哥", @28];
    do {
        r = [it next];
        NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    }while(!r.done);
    
    NSLog(@"************************ End %s *******************************", __func__);
}

+ (void)test4 {
    NSLog(@"************************ Begin %s *******************************", __func__);
    RJIterator *it = nil;
    RJResult *r = nil;
    
    it = [[RJIterator alloc] initWithTarget:[self new] selector:@selector(dataBox2:age:), @"古德曼", @30];
    do {
        r = [it next];
        NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    }while(!r.done);
    
    NSLog(@"************************ End %s *******************************", __func__);
}

+ (void)test5 {
    NSLog(@"************************ Begin %s *******************************", __func__);
    RJIterator *it = nil;
    RJResult *r = nil;
    
    it = [[RJIterator alloc] initWithBlock:^{
        rj_yield(@100);
        rj_yield(@101);
        rj_yield(@102);
        rj_yield(@103);
    }];
    
    do {
        r = [it next];
        NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    }while(!r.done);
    
    NSLog(@"************************");
    
    it = [[RJIterator alloc] initWithBlock:^(NSString *name, NSNumber *age) {
        rj_yield([NSString stringWithFormat:@"Hello %@, your age is:%@", name, age]);
        rj_yield(@100);
        rj_yield(@101);
        rj_yield(@102);
        rj_yield(@103);
        NSLog(@"==in block/block done");
    }, @"索尔", @33];
    do {
        r = [it next];
        NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    }while(!r.done);
    
    NSLog(@"************************ End %s *******************************", __func__);
}

+ (void)test6 {
    NSLog(@"************************ Begin %s *******************************", __func__);
    RJIterator *it = nil;
    RJResult *r = nil;
    
    it = [[RJIterator alloc] initWithBlock:^(NSString *name, NSNumber *age) {
        rj_yield([NSString stringWithFormat:@"Hello %@, your age is:%@", name, age]);
        rj_yield(@100);
        rj_yield(@101);
        rj_yield(@102);
        rj_yield(@103);
        return @"i tell you : block done";
    }, @"索尔", @33];
    do {
        r = [it next];
        NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    }while(!r.done);
    
    NSLog(@"************************ End %s *******************************", __func__);
}

+ (NSNumber *)ClassFibonacci {
    int prev = 0;
    int cur = 1;
    for (;;) {
        rj_yield(@(cur));
        
        int p = prev;
        prev = cur;
        cur = p + cur;
        
        if (cur > 6765) {
            break;
        }
    }
    return @(cur);
}

+ (void)test7 {
    NSLog(@"************************ Begin %s *******************************", __func__);
    RJIterator *it = nil;
    RJResult *r = nil;
    
    it = [[RJIterator alloc] initWithTarget:self selector:@selector(ClassFibonacci)];
    for (int i = 0; i < 22; ++i) {
        r = [it next];
        NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    }
    
    NSLog(@"************************ End %s *******************************", __func__);
}

+ (void)talk2:(NSString *)name {
    NSString *really_name = rj_yield([NSString stringWithFormat:@"FakeName: %@", name]);
    NSLog(@"== talk2/really_name: %@", really_name);
}

+ (void)test8 {
    NSLog(@"************************ Begin %s *******************************", __func__);
    RJIterator *it = nil;
    RJResult *r = nil;
    
    it = [[RJIterator alloc] initWithTarget:self selector:@selector(talk2:), @"第一帅"];
    r = [it next];
    NSLog(@"== value: %@, done:%@", r.value, r.done ? @"YES" : @"NO");
    
    //为next传参,将在rj_yield返回前改变返回值， 即修改really_name
    r = [it next:@"RJK"]; //打印 RJK
    //如果不传参，将打印 //FakeName: 第一帅
    
    NSLog(@"************************ End %s *******************************", __func__);
}

@end
