//
//  RJIterator.h
//  RJIterator
//
//  Created by renjinkui on 2018/4/12.
//  Copyright © 2018年 JK. All rights reserved.
//

#import <Foundation/Foundation.h>

@class RJResult;
@class RJIterator;
@class RJAsyncEpilog;

id _Nullable rj_yield(id _Nullable value);
RJResult * _Nonnull rj_await(id _Nullable value);
RJAsyncEpilog *_Nonnull rj_async(dispatch_block_t _Nonnull block);


typedef id _Nullable (*RJGenetarorFunc)(id _Nullable);
typedef void (^RJAsyncCallback)(id _Nullable value, id _Nullable error);
typedef void (^RJAsyncClosure)(RJAsyncCallback _Nonnull callback);

@interface RJIterator : NSObject
{
    int *_ev_leave;
    int *_ev_entry;
    BOOL _ev_entry_valid;
    void *_stack;
    int _stack_size;
    RJIterator * _nest;
    RJGenetarorFunc _func;
    id _target;
    SEL _selector;
    id _block;
    NSMutableArray *_args;
    NSMethodSignature *_signature;
    BOOL _done;
    id _value;
    id _error;
}


- (id _Nonnull)initWithFunc:(RJGenetarorFunc _Nonnull)func arg:(id _Nullable)arg;
- (id _Nonnull)initWithTarget:(id _Nonnull)target selector:(SEL _Nonnull)selector, ...;
- (id _Nonnull)initWithBlock:(id _Nonnull)block, ...;

//兼容swift
- (id _Nonnull)initWithTarget:(id _Nonnull)target selector:(SEL _Nonnull)selector args:(NSArray *_Nullable)args;
- (id _Nonnull)initWithBlock:(id _Nullable (^ _Nonnull)(id _Nullable))block arg:(id _Nullable)arg;
- (id _Nonnull)initWithStandardBlock:(dispatch_block_t _Nonnull)block;


- (RJResult * _Nonnull)next;
- (RJResult * _Nonnull)next:(id _Nonnull)value;
@end


@interface RJResult: NSObject
{
    id _value;
    BOOL _done;
}
@property (nonatomic, strong, readonly) id _Nullable value;
@property (nonatomic, strong, readonly) id _Nullable error;
@property (nonatomic, readonly) BOOL done;
+ (instancetype _Nonnull)resultWithValue:(id _Nullable)value error:(id _Nullable)error done:(BOOL)done;
@end


typedef void  (^RJFinallyConfiger)(dispatch_block_t _Nonnull);
@interface RJAsyncEpilog: NSObject
{
    id _finally_handler;
}
@property (nonatomic, readonly) RJFinallyConfiger _Nonnull finally ;
@end
