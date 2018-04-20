 //
//  RJIterator.m
//  RJIterator
//
//  Created by renjinkui on 2018/4/12.
//  Copyright © 2018年 JK. All rights reserved.
//

#import "RJIterator.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <setjmp.h>
#import <pthread.h>

#if DEMO
#import "RJIterator-Swift.h"
#else
#import <RJIterator/RJIterator-Swift.h>
#endif

#if __has_feature(objc_arc)
//ARC下存在跳转导致的编译器生成的释放函数执行不到的问题
//MRC就可以回避编译器的这种 “干扰”
//以pod 安装可正常运行,不用手动配MRC
#error RJIterator Must be compiled with MRC
#endif

#define DEFAULT_STACK_SIZE (256 * 1024)

#define JMP_CONTINUE 1
#define JMP_DONE 2

#define is_null(arg) (!(arg) || [(arg) isKindOfClass:NSNull.self])
#define arg_or_nil(arg) (is_null(arg) ? nil : arg)

static NSMethodSignature *NSMethodSignatureForBlock(id block);

#pragma mark - RJAsyncEpilog
@interface RJAsyncEpilog()
- (void)do_finally;
@property (nonatomic, copy) dispatch_block_t finally_hanler;
@end

@implementation RJAsyncEpilog
@synthesize finally_hanler = _finally_handler;

- (RJFinallyConfiger)finally {
    RJFinallyConfiger configer = ^(dispatch_block_t handler){
        self.finally_hanler = handler;
    };
    return [[(id)configer copy] autorelease];
}

- (void)dealloc {
#if DEMO
    NSLog(@"== %@ dealoc", self);
#endif
    if (_finally_handler) {
        Block_release(_finally_handler);
    }
    [super dealloc];
}

- (void)do_finally {
    if (_finally_handler) {
        ((dispatch_block_t)_finally_handler)();
    }
}

@end

#pragma mark - RJResult

@implementation RJResult
@synthesize value = _value;
@synthesize done = _done;

- (id)initWithValue:(id)value error:(id)error done:(BOOL)done {
    if (self = [super init]) {
        _value = [value retain];
        _error = [error retain];
        _done = done;
    }
    return self;
}

- (void)dealloc {
#if DEMO
    NSLog(@"== %@ dealoc", self);
#endif
    [_value release];
    [_error release];
    [super dealloc];
}

+ (instancetype)resultWithValue:(id)value error:(id)error done:(BOOL)done{
    return [[[self alloc] initWithValue:value error:error done:done] autorelease];
}
@end

#pragma mark - RJIteratorStack

static pthread_key_t iterator_stack_key;
static void destroy_iterator_stack(void * stack) {
    CFRelease((CFArrayRef)stack);
}

@interface RJIteratorStack: NSObject
+ (void)push:(RJIterator *)iterator;
+ (RJIterator *)pop;
+ (RJIterator *)top;
@end

@implementation RJIteratorStack
+ (void)load {
    pthread_key_create(&iterator_stack_key, destroy_iterator_stack);
}

+ (void)push:(RJIterator *)iterator {
    CFMutableArrayRef stack = pthread_getspecific(iterator_stack_key);
    if (!stack) {
        stack = CFArrayCreateMutable(kCFAllocatorSystemDefault, 16, &kCFTypeArrayCallBacks);
        pthread_setspecific(iterator_stack_key, (void *)stack);
    }
    CFArrayAppendValue(stack, (void *)iterator);
}

+ (RJIterator *)pop {
    CFMutableArrayRef stack = pthread_getspecific(iterator_stack_key);
    CFIndex count = stack ? CFArrayGetCount(stack) : 0;
    if (count > 0) {
        RJIterator *iterator = (RJIterator *)CFArrayGetValueAtIndex(stack, count - 1);
        [iterator retain];
        CFArrayRemoveValueAtIndex(stack, count - 1);
        return iterator.autorelease;
    }
    return nil;
}

+ (RJIterator *)top {
    CFMutableArrayRef stack = pthread_getspecific(iterator_stack_key);
    CFIndex count = stack ? CFArrayGetCount(stack) : 0;
    if (count > 0) {
        RJIterator *iterator = (RJIterator *)CFArrayGetValueAtIndex(stack, count - 1);
        return iterator;
    }
    return nil;
}
@end

#pragma mark - RJIterator

@interface RJIterator()
@property (nonatomic, strong) RJIterator * nest;
@property (nonatomic, strong) id value;
@property (nonatomic, strong) id error;
@property (nonatomic, assign) BOOL done;
@end

@implementation RJIterator
@synthesize nest = _nest;
@synthesize value = _value;
@synthesize error = _error;
@synthesize done = _done;

- (id)init {
    if (self = [super init]) {
        _stack = malloc(DEFAULT_STACK_SIZE);
        memset(_stack, 0x00, DEFAULT_STACK_SIZE);
        _stack_size = DEFAULT_STACK_SIZE;
        
        _ev_leave = malloc(sizeof(jmp_buf));
        memset(_ev_leave, 0x00, sizeof(jmp_buf));
        _ev_entry = malloc(sizeof(jmp_buf));
        memset(_ev_entry, 0x00, sizeof(jmp_buf));
        
        _args = [NSMutableArray arrayWithCapacity:8].retain;
    }
    return self;
}

- (void)dealloc {
#if DEMO
    NSLog(@"== %@ dealoc", self);
#endif
    [_args release];
    [_target release];
    [_signature release];
    [_value release];
    [_error release];
    [_nest release];
    
    if (_stack) {
        free(_stack);
        _stack = NULL;
    }
    if (_ev_leave) {
        free(_ev_leave);
        _ev_leave = NULL;
    }
    if (_ev_entry) {
        free(_ev_entry);
        _ev_entry = NULL;
    }
    
    [super dealloc];
}

- (id _Nonnull)initWithFunc:(RJGenetarorFunc _Nonnull)func arg:(id _Nullable)arg {
    if (self = [self init]) {
        _func = func;
        [_args addObject:arg ?: NSNull.null];
    }
    return self;
}

- (id _Nonnull)initWithTarget:(id _Nonnull)target selector:(SEL _Nonnull)selector, ... {
    NSAssert(target && selector, @"target and selector must not be nil");
    
    NSMethodSignature *signature = [self.class signatureForTarget:target selector:selector];
    [self.class checkGeneratorSignature:signature is_block:NO];
    
    NSMutableArray *args = [NSMutableArray array];
    va_list ap;
    va_start(ap, selector);
    for (int i=0; i < (int)signature.numberOfArguments - 2; ++i) {
        id arg = va_arg(ap, id);
        [args addObject:arg ?: NSNull.null];
    }
    va_end(ap);
    
    return [self _initWithTarget:target selector:selector args:args signature:signature];
}

- (id _Nonnull)initWithTarget:(id _Nonnull)target selector:(SEL _Nonnull)selector args:(NSArray *_Nullable)args {
    NSAssert(target && selector, @"target and selector must not be nil");
    
    NSMethodSignature *signature = [self.class signatureForTarget:target selector:selector];
    [self.class checkGeneratorSignature:signature is_block:NO];
    
    return [self _initWithTarget:target selector:selector args:args signature:signature];
}

- (id)_initWithTarget:(id)target selector:(SEL)selector args:(NSArray *)args signature:(NSMethodSignature *)signature {
    if (self = [self init]) {
        _target = [target retain];
        _selector = selector;
        _signature = signature.retain;
        _args = [args copy];
    }
    return self;
}

- (id _Nonnull)initWithBlock:(id _Nonnull)block, ... {
    NSAssert(block, @"block must not be nil");
    
    NSMethodSignature *signature = NSMethodSignatureForBlock(block);
    [self.class checkGeneratorSignature:signature is_block:YES];
    
    NSMutableArray *args = [NSMutableArray array];
    va_list ap;
    va_start(ap, block);
    for (int i=0; i < (int)signature.numberOfArguments - 1; ++i) {
        id arg = va_arg(ap, id);
        [args addObject:arg ?: NSNull.null];
    }
    va_end(ap);
    
    return [self _initWithBlock:block args:args signature:signature];
}

- (id _Nonnull)initWithBlock:(id _Nullable (^ _Nonnull)(id _Nullable))block arg:(id _Nullable)arg {
    NSAssert(block, @"block must not be nil");
    
    NSMethodSignature *signature = NSMethodSignatureForBlock(block);
    [self.class checkGeneratorSignature:signature is_block:YES];
    
    return [self _initWithBlock:block args:arg ? @[arg] : @[] signature:signature];
}

- (id _Nonnull)initWithStandardBlock:(dispatch_block_t _Nonnull)block {
    return [self initWithBlock:(id)block arg:nil];
}

- (id)_initWithBlock:(id _Nonnull)block args:(NSArray *_Nullable)args signature:(NSMethodSignature *)signature {
    if (self = [self init]) {
        _block = [block copy];
        _signature = signature.retain;
        _args = [args copy];
    }
    return self;
}

+ (NSMethodSignature *)signatureForTarget:(id)target selector:(SEL)selector {
    Method m = NULL;
    //生成器是类方法
    if (object_isClass(target)) {
        Class cls = (Class)target;
        m = class_getClassMethod(cls, selector);
    }
    //生成器是实例方法
    else {
        Class cls = [target class];
        m = class_getInstanceMethod(cls, selector);
    }
    const char *encoding = method_getTypeEncoding(m);
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:encoding];
    return signature;
}

+ (void)checkGeneratorSignature:(NSMethodSignature *)signature is_block:(BOOL)is_block{
    //返回值必须是id或者void
    __unused BOOL ret_valid = signature.methodReturnType[0] == 'v' || signature.methodReturnType[0] == '@';
    NSAssert(ret_valid, @"return type of generator must be id or void");
    BOOL args_valid = YES;
    if (is_block) {
        //block最多支持8个参数，block调用默认有第一个参数:block自身
        NSAssert(signature.numberOfArguments <= 9, @"arguments count of block must <= 8");
        //所有参数必须为对象类型
        if (signature.numberOfArguments > 1) {
            for (int i=1; i < signature.numberOfArguments; ++i) {
                if ([signature getArgumentTypeAtIndex:i][0] != '@') {
                    args_valid = NO;
                    break;
                }
            }
        }
    }
    else {
        //方法调用最多支持8个参数,方法调用默认有第一个参数self(target)，第二个参数_cmd(selector)
        NSAssert(signature.numberOfArguments <= 10, @"arguments count of method must <= 8");
        //所有参数必须为对象类型
        if (signature.numberOfArguments > 2) {
            for (int i=2; i < signature.numberOfArguments; ++i) {
                if ([signature getArgumentTypeAtIndex:i][0] != '@') {
                    args_valid = NO;
                    break;
                }
            }
        }
    }
    
    NSAssert(args_valid, @"argument type of generator must all be id");
}


- (RJResult *)next {
    return [self next:nil set_value:NO];
}

- (RJResult *)next:(id)value {
    return [self next:value set_value:YES];
}

- (RJResult *)next:(id)value set_value:(BOOL)set_value {
    if (_done) {
        return [RJResult resultWithValue:_value error:_error done:_done];
    }
    
    [RJIteratorStack push:self];
    
    //设置跳转返回点
    int leave_value = setjmp(_ev_leave);
    //非跳转返回
    if (leave_value == 0) {
        //已经设置了生成器进入点
        if (_ev_entry_valid) {
            //直接从生成器进入点进入
            if (set_value) {
                self.value = value;
            }
            longjmp(_ev_entry, JMP_CONTINUE);
        }
        else {
            //wrapper进入
            
            //next栈会销毁,所以为wrapper启用新栈
            intptr_t sp = (intptr_t)(_stack + _stack_size);
            //预留安全空间，防止直接move [sp] 传参 以及msgsend向上访问堆栈
            sp -= 256;
            //对齐sp
            sp &= ~0x07;
            
#if defined(__arm__)
            asm volatile("mov sp, %0" : : "r"(sp));
#elif defined(__arm64__)
            asm volatile("mov sp, %0" : : "r"(sp));
#elif defined(__i386__)
            asm volatile("movl %0, %%esp" : : "r"(sp));
#elif defined(__x86_64__)
            asm volatile("movq %0, %%rsp" : : "r"(sp));
#endif
            //在新栈上调用wrapper,至此可以认为wrapper,以及生成器函数的运行栈和next无关
            [self wrapper];
        }
    }
    //生成器内部跳转返回
    else if (leave_value == JMP_CONTINUE) {
        //还可以继续迭代
    }
    //生成器wrapper跳转返回
    else if (leave_value == JMP_DONE) {
        //生成器结束，迭代完成
        _done = YES;
    }
    
    [RJIteratorStack pop];
    
    return [RJResult resultWithValue:_value error:_error done:_done];
}


- (void)wrapper {
    id value = nil;
    if (_func) {
        value = _func(arg_or_nil(_args.firstObject));
    }
    else if (_target && _selector) {
        id arg0 = _signature.numberOfArguments > 2 ? arg_or_nil(_args[0]) : nil;
        id arg1 = _signature.numberOfArguments > 3 ? arg_or_nil(_args[1]) : nil;
        id arg2 = _signature.numberOfArguments > 4 ? arg_or_nil(_args[2]) : nil;
        id arg3 = _signature.numberOfArguments > 5 ? arg_or_nil(_args[3]) : nil;
        id arg4 = _signature.numberOfArguments > 6 ? arg_or_nil(_args[4]) : nil;
        id arg5 = _signature.numberOfArguments > 7 ? arg_or_nil(_args[5]) : nil;
        id arg6 = _signature.numberOfArguments > 8 ? arg_or_nil(_args[6]) : nil;
        id arg7 = _signature.numberOfArguments > 9 ? arg_or_nil(_args[7]) : nil;
        if (_signature.methodReturnType[0] == 'v') {
            ((void (*)(id, SEL, id, id, id, id, id, id, id, id))objc_msgSend)(_target, _selector,
                                                                              arg0,arg1,arg2,arg3,arg4,arg5,arg6,arg7
                                                                              );
            
        }
        else {
            value = ((id (*)(id, SEL, id, id, id, id, id, id, id, id))objc_msgSend)(_target, _selector,
                                                                                      arg0,arg1,arg2,arg3,arg4,arg5,arg6,arg7
                                                                                      );
        }
    }
    else if (_block) {
        id arg0 = _signature.numberOfArguments > 1 ? arg_or_nil(_args[0]) : nil;
        id arg1 = _signature.numberOfArguments > 2 ? arg_or_nil(_args[1]) : nil;
        id arg2 = _signature.numberOfArguments > 3 ? arg_or_nil(_args[2]) : nil;
        id arg3 = _signature.numberOfArguments > 4 ? arg_or_nil(_args[3]) : nil;
        id arg4 = _signature.numberOfArguments > 5 ? arg_or_nil(_args[4]) : nil;
        id arg5 = _signature.numberOfArguments > 6 ? arg_or_nil(_args[5]) : nil;
        id arg6 = _signature.numberOfArguments > 7 ? arg_or_nil(_args[6]) : nil;
        id arg7 = _signature.numberOfArguments > 8 ? arg_or_nil(_args[7]) : nil;
        
        if (_signature.methodReturnType[0] == 'v') {
            ((void (^)(id, id, id, id, id, id, id, id))_block)(arg0,arg1,arg2,arg3,arg4,arg5,arg6,arg7);
        }
        else {
            value = ((id (^)(id, id, id, id, id, id, id, id))_block)(arg0,arg1,arg2,arg3,arg4,arg5,arg6,arg7);
        }
    }
    //从生成器返回，说明生成器完全执行结束
    //直接返回到迭代器设置的返回点
    self.value = value;
    
    longjmp(_ev_leave, JMP_DONE);
    //不会到此
    assert(0);
}

- (id)yield:(id)value {
    id yield_value = value;
    if ([value isKindOfClass:self.class]) {
        //嵌套的迭代器
        self.nest = (RJIterator *)value;
    }
    
    next: {
        RJResult * result = [self.nest next];
        if (result) {
            yield_value = result.value;
        }
        
        _ev_entry_valid = YES;
        if (setjmp(_ev_entry) == 0) {
            self.value = yield_value;
            longjmp(_ev_leave, JMP_CONTINUE);
        }
    }
    
    //嵌套迭代器还可继续
    if (self.nest && !self.nest.done) {
        goto next;
    }
    
    self.nest = nil;
    
    return self.value;
}

@end


id rj_yield(id value) {
    RJIterator *iterator = [RJIteratorStack top];
    return [iterator yield: value];
}

RJResult * _Nonnull rj_await(id _Nullable value) {
    return (RJResult *) rj_yield(value);
}

@protocol LikePromise <NSObject>
- (id<LikePromise> __nonnull (^ __nonnull)(id __nonnull))then;
- (id<LikePromise>  __nonnull(^ __nonnull)(id __nonnull))catch;
@end


RJAsyncEpilog * rj_async(dispatch_block_t block) {
    RJIterator *  iterator = [[RJIterator alloc] initWithStandardBlock:block];
    RJAsyncEpilog *  epilog = [[RJAsyncEpilog alloc] init];
    RJResult * __block result = nil;
    
    dispatch_block_t __block step;
    step = ^{
        if (!result.done) {
            id value = result.value;
            //oc闭包
            if ([value isKindOfClass:NSClassFromString(@"__NSGlobalBlock__")] ||
                [value isKindOfClass:NSClassFromString(@"__NSStackBlock__")] ||
                [value isKindOfClass:NSClassFromString(@"__NSMallocBlock__")]
                ) {
                ((RJAsyncClosure)value)(^(id value, id error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [result release];
                        result = [iterator next: [RJResult resultWithValue:value error:error done:NO]].retain;
                        step();
                    });
                });
            }
            //swift 闭包
            else if (NSClassFromString(@"_SwiftValue") &&
                     [value isKindOfClass:NSClassFromString(@"_SwiftValue")] &&
                     [[value description] containsString:@"(Function)"]
                     ) {
                [RJAsyncClosureCaller callWithClosure:value finish:^(id  _Nullable value, id  _Nullable error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [result release];
                        result = [iterator next: [RJResult resultWithValue:value error:error done:NO]].retain;
                        step();
                    });
                }];
            }
            //AnyPromise
            else if (NSClassFromString(@"AnyPromise") &&
                     [value isKindOfClass:NSClassFromString(@"AnyPromise")] &&
                     [value respondsToSelector:@selector(then)] &&
                     [value respondsToSelector:@selector(catch)]
                     ) {
                id <LikePromise> promise = (id <LikePromise>)value;
                void (^__block then_block)(id) = NULL;
                void (^__block catch_block)(id) = NULL;
                
                then_block = Block_copy(^(id value){
                    if (then_block) { Block_release(then_block); then_block = NULL; }
                    if (catch_block) { Block_release(catch_block); catch_block = NULL; }
                    
                    [result release];
                    result = [iterator next: [RJResult resultWithValue:value error:nil done:NO]].retain;
                    step();
                });
                
                catch_block = Block_copy(^(id error){
                    if (then_block) { Block_release(then_block); then_block = NULL; }
                    if (catch_block) { Block_release(catch_block); catch_block = NULL; }
                    
                    [result release];
                    result = [iterator next: [RJResult resultWithValue:nil error:error done:NO]].retain;
                    step();
                });
                
                promise.then(then_block).catch(catch_block);
            }
            //普通对象
            else {
                RJResult *old_result = result;
                result = [iterator next: old_result].retain;
                [old_result release];
                
                step();
            }
        }
        else {
            [epilog do_finally];
            
            [epilog release];
            Block_release(step);
            [result release];
            [iterator release];
        }
    };
    
    step =  Block_copy(step);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        result = iterator.next.retain;
        step();
    });
    
    return epilog.retain.autorelease;
}



///////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////
/*
 获取block签名
 以下代码片段 拷贝 自PromiseKit项目NSMethodSignatureForBlock.m文件，用以获取block签名
 https://github.com/mxcl/PromiseKit/blob/master/Sources/NSMethodSignatureForBlock.m
 //如果和PromiseKit一起编译,不会冲突,这里全是局部类型/变量
 */
///////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////

struct PMKBlockLiteral {
    void *isa; // initialized to &_NSConcreteStackBlock or &_NSConcreteGlobalBlock
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    struct block_descriptor {
        unsigned long int reserved;    // NULL
        unsigned long int size;         // sizeof(struct Block_literal_1)
        // optional helper functions
        void (*copy_helper)(void *dst, void *src);     // IFF (1<<25)
        void (*dispose_helper)(void *src);             // IFF (1<<25)
        // required ABI.2010.3.16
        const char *signature;                         // IFF (1<<30)
    } *descriptor;
    // imported variables
};

typedef NS_OPTIONS(NSUInteger, PMKBlockDescriptionFlags) {
    PMKBlockDescriptionFlagsHasCopyDispose = (1 << 25),
    PMKBlockDescriptionFlagsHasCtor = (1 << 26), // helpers have C++ code
    PMKBlockDescriptionFlagsIsGlobal = (1 << 28),
    PMKBlockDescriptionFlagsHasStret = (1 << 29), // IFF BLOCK_HAS_SIGNATURE
    PMKBlockDescriptionFlagsHasSignature = (1 << 30)
};

// It appears 10.7 doesn't support quotes in method signatures. Remove them
// via @rabovik's method. See https://github.com/OliverLetterer/SLObjectiveCRuntimeAdditions/pull/2
#if defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_8
NS_INLINE static const char * pmk_removeQuotesFromMethodSignature(const char *str){
    char *result = malloc(strlen(str) + 1);
    BOOL skip = NO;
    char *to = result;
    char c;
    while ((c = *str++)) {
        if ('"' == c) {
            skip = !skip;
            continue;
        }
        if (skip) continue;
        *to++ = c;
    }
    *to = '\0';
    return result;
}
#endif

static NSMethodSignature *NSMethodSignatureForBlock(id block) {
    if (!block)
        return nil;
    
    struct PMKBlockLiteral *blockRef = (__bridge struct PMKBlockLiteral *)block;
    PMKBlockDescriptionFlags flags = (PMKBlockDescriptionFlags)blockRef->flags;
    
    if (flags & PMKBlockDescriptionFlagsHasSignature) {
        void *signatureLocation = blockRef->descriptor;
        signatureLocation += sizeof(unsigned long int);
        signatureLocation += sizeof(unsigned long int);
        
        if (flags & PMKBlockDescriptionFlagsHasCopyDispose) {
            signatureLocation += sizeof(void(*)(void *dst, void *src));
            signatureLocation += sizeof(void (*)(void *src));
        }
        
        const char *signature = (*(const char **)signatureLocation);
#if defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_8
        signature = pmk_removeQuotesFromMethodSignature(signature);
        NSMethodSignature *nsSignature = [NSMethodSignature signatureWithObjCTypes:signature];
        free((void *)signature);
        
        return nsSignature;
#endif
        return [NSMethodSignature signatureWithObjCTypes:signature];
    }
    return 0;
}

