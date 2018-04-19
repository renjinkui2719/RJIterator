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

#if DEMO
#import <RJIterator-Swift.h>
#else
#import <RJIterator/RJIterator-Swift.h>
#endif

#if __has_feature(objc_arc)
//ARC下存在跳转导致的编译器生成的释放函数执行不到的问题
//MRC就可以回避编译器的这种 “干扰”
//以pod 安装可正常运行,不用手动配MRC
#error RJIterator Must be compiled with MRC
#endif

#define DEFAULT_STACK_SIZE (128 * 1024)

#define JMP_CONTINUE 1
#define JMP_DONE 2

#define is_null(arg) (!(arg) || [(arg) isKindOfClass:NSNull.self])
#define arg_or_nil(arg) (is_null(arg) ? nil : arg)

static NSMethodSignature *NSMethodSignatureForBlock(id block);

@interface RJAsyncEpilog()
- (void)do_error:(id)error;
- (void)do_finally;

@property (nonatomic, copy) RJErrorHandler error_handler;
@property (nonatomic, copy) dispatch_block_t finally_hanler;
@end

@implementation RJAsyncEpilog
@synthesize error_handler = _error_handler;
@synthesize finally_hanler = _finally_handler;

- (RJErrorConfiger)error {
    RJErrorConfiger configer = ^(RJErrorHandler handler){
        self.error_handler = handler;
        return self;
    };
    return [[(id)configer copy] autorelease];
}

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
    if (_error_handler) {
        Block_release(_error_handler);
    }
    if (_finally_handler) {
        Block_release(_finally_handler);
    }
    [super dealloc];
}

- (void)do_error:(id)error {
    if (_error_handler) {
        ((RJErrorHandler)_error_handler)(error);
    }
}

- (void)do_finally {
    if (_finally_handler) {
        ((dispatch_block_t)_finally_handler)();
    }
}



@end

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


static RJIterator *top;

@interface RJIteratorStack: NSObject
+ (void)push:(RJIterator *)iterator;
+ (RJIterator *)pop;
@end
@implementation RJIteratorStack
+ (void)push:(RJIterator *)iterator {
    NSMutableArray *stack = [NSThread currentThread].threadDictionary[@"RJIteratorStack"];
    if (!stack) {
        stack = [NSMutableArray arrayWithCapacity:16];
        [NSThread currentThread].threadDictionary[@"RJIteratorStack"] = stack;
    }
    [stack addObject:iterator];
    top = iterator;
}

+ (RJIterator *)pop {
    NSMutableArray *stack = [NSThread currentThread].threadDictionary[@"RJIteratorStack"];
    RJIterator *iterator = stack.lastObject;
    NSAssert(iterator, @"Error: Iterator Stack of current thread is damadged!!");
    [stack removeLastObject];
    if (top == iterator) {
        top = [self top];
    }
    return iterator;
}

+ (RJIterator *)top {
    NSMutableArray *stack = [NSThread currentThread].threadDictionary[@"RJIteratorStack"];
    RJIterator *iterator = stack.lastObject;
    //NSAssert(iterator, @"Error: Iterator Stack of current thread is damadged!!");
    return iterator;
}
@end




//static void (* origin_release)(Class self, SEL _cmd);
//static void hook_release(Class self, SEL _cmd) {
//    origin_release(self, _cmd);
//}
//
//static id (* origin_autorelease)(Class self, SEL _cmd);
//static id hook_autorelease(Class self, SEL _cmd) {
//    return origin_autorelease(self, _cmd);
//}

//static objc_retainAutoreleasedReturnValue;
//objc_initWeak
//objc_destroyWeak
//objc_storeStrong

@interface RJIterator()
@property (nonatomic, strong) RJIterator * nest;
@property (nonatomic, strong) id value;
@property (nonatomic, strong) id error;
@property (nonatomic, assign) BOOL done;
@property (nonatomic, assign) BOOL collect_leak;
@property (nonatomic, strong) NSHashTable * leak_table;
@end

@implementation RJIterator
@synthesize nest = _nest;
@synthesize value = _value;
@synthesize error = _error;
@synthesize done = _done;
@synthesize collect_leak = _collect_leak;
@synthesize leak_table = _leak_table;

static void fullyrelease_object(id obj) {
    NSInteger cnt = [obj retainCount];
    while (cnt > 0) {
        [obj release];
        if (cnt > 1) {
            cnt = [obj retainCount];
        }
        else {
            cnt = 0;
        }
    }
}


static id (* origin_allocWithZone)(Class self, SEL _cmd, struct _NSZone *zone);
static id hook_allocWithZone(Class self, SEL _cmd, struct _NSZone *zone) {
    id obj = origin_allocWithZone(self, _cmd, zone);
    
    RJIterator *it = top;//[RJIteratorStack top];
    if (it.collect_leak) {
        [it.leak_table addObject:obj];
    }
    
    return obj;
}

//static id (* origin_retain)(Class self, SEL _cmd);
//static id hook_retain(Class self, SEL _cmd) {
//    return origin_retain(self, _cmd);
//    RJIterator *it = [RJIteratorStack top];
//    if (it.collect_leak) {
//        [it.leak_table addObject:obj];
//    }
//}

+ (void)load {
    Method m = NULL;
    const char *encoding = NULL;
    //hook allocWithZone
//    m = class_getClassMethod(NSObject.self, @selector(allocWithZone:));
//    origin_allocWithZone = (id (*)(id, SEL, struct _NSZone *))method_getImplementation(m);
//    encoding = method_getTypeEncoding(m);
//    class_replaceMethod(object_getClass(NSObject.self), @selector(allocWithZone:), (IMP)hook_allocWithZone, encoding);
    //hook retain
//    m = class_getInstanceMethod(NSObject.self, @selector(retain));
//    origin_retain = (id (*)(id, SEL))method_getImplementation(m);
//    encoding = method_getTypeEncoding(m);
//    class_replaceMethod(NSObject.self, @selector(retain), (IMP)hook_retain, encoding);
//    //hook release
//    m = class_getInstanceMethod(NSObject.self, @selector(release));
//    origin_release = (void (*)(id, SEL))method_getImplementation(m);
//    encoding = method_getTypeEncoding(m);
//    class_replaceMethod(NSObject.self, @selector(release), (IMP)hook_release, encoding);
//    //hook autorelase
//    m = class_getInstanceMethod(NSObject.self, @selector(autorelease));
//    origin_autorelease = (id (*)(id, SEL))method_getImplementation(m);
//    encoding = method_getTypeEncoding(m);
//    class_replaceMethod(NSObject.self, @selector(autorelease), (IMP)hook_autorelease, encoding);
    
}


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
        
        _leak_table = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory].retain;
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
    
    if (_leak_table.count) {
        for (id obj in _leak_table) {
            fullyrelease_object(obj);
        }
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
        //NSLog(@"iterator has done!!");
        return [RJResult resultWithValue:_value error:_error done:_done];
    }
    [RJIteratorStack push:self];
    self.collect_leak = YES;
    
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
    
    //NSLog(@"end of next");
    self.collect_leak = NO;
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

@protocol LikePromise <NSObject>
- (id<LikePromise> __nonnull (^ __nonnull)(id __nonnull))then;
- (id<LikePromise>  __nonnull(^ __nonnull)(id __nonnull))catch;
@end


RJAsyncEpilog * rj_async(dispatch_block_t block) {
    RJIterator *  iterator = [[RJIterator alloc] initWithStandardBlock:block];
    RJAsyncEpilog *  epilog = [[RJAsyncEpilog alloc] init];
    RJResult * __block result = nil;
    
#define Release() do {\
[epilog release];\
Block_release(step);\
[result release];\
[iterator release];\
}while(0);
    
    dispatch_block_t __block step;
    step = ^{
        if (result.error) {
            [epilog do_error:result.error];
            [epilog do_finally];
            Release();
            return ;
        }
        if (!result.done) {
            id value = result.value;
            //oc闭包
            if ([value isKindOfClass:NSClassFromString(@"__NSGlobalBlock__")] ||
                [value isKindOfClass:NSClassFromString(@"__NSStackBlock__")] ||
                [value isKindOfClass:NSClassFromString(@"__NSMallocBlock__")]
                ) {
                ((RJAsyncClosure)value)(^(id value, id error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (error) {
                            [result release];
                            result = [RJResult resultWithValue:value error:error done:NO].retain;
                        }
                        else {
                            [result release];
                            result = [iterator next:value].retain;
                        }
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
                        if (error) {
                            [result release];
                            result = [RJResult resultWithValue:value error:error done:NO].retain;
                        }
                        else {
                            [result release];
                            result = [iterator next:value].retain;
                        }
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
                    result = [iterator next:value].retain;
                    step();
                });
                
                catch_block = Block_copy(^(id error){
                    if (then_block) { Block_release(then_block); then_block = NULL; }
                    if (catch_block) { Block_release(catch_block); catch_block = NULL; }
                    
                    [result release];
                    result = [RJResult resultWithValue:nil error:error done:NO].retain;
                    step();
                });
                
                promise.then(then_block).catch(catch_block);
            }
            else {
                [result release];
                result = [iterator next:value].retain;
                step();
            }
        }
        else {
            [epilog do_finally];
            Release();
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
 以下代码片段 拷贝、拷贝、拷贝 自PromiseKit项目NSMethodSignatureForBlock.m文件，用以获取block签名
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


///////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////
/*
 hook ARC 内存管理函数
 以下代码片段 拷贝、拷贝、拷贝 自fishhook项目fishhook.c文件，用以 hook ARC 内存管理函数
 https://github.com/facebook/fishhook
 //如果和fishhook一起编译,不会冲突,这里全是局部类型/变量
 */
///////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////
struct rebinding {
    const char *name;
    void *replacement;
    void **replaced;
};

#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>

#ifdef __LP64__
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct section_64 section_t;
typedef struct nlist_64 nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT_64
#else
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct section section_t;
typedef struct nlist nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT
#endif

#ifndef SEG_DATA_CONST
#define SEG_DATA_CONST  "__DATA_CONST"
#endif

struct rebindings_entry {
    struct rebinding *rebindings;
    size_t rebindings_nel;
    struct rebindings_entry *next;
};

static struct rebindings_entry *_rebindings_head;

static int prepend_rebindings(struct rebindings_entry **rebindings_head,
                              struct rebinding rebindings[],
                              size_t nel) {
    struct rebindings_entry *new_entry = (struct rebindings_entry *) malloc(sizeof(struct rebindings_entry));
    if (!new_entry) {
        return -1;
    }
    new_entry->rebindings = (struct rebinding *) malloc(sizeof(struct rebinding) * nel);
    if (!new_entry->rebindings) {
        free(new_entry);
        return -1;
    }
    memcpy(new_entry->rebindings, rebindings, sizeof(struct rebinding) * nel);
    new_entry->rebindings_nel = nel;
    new_entry->next = *rebindings_head;
    *rebindings_head = new_entry;
    return 0;
}

static void perform_rebinding_with_section(struct rebindings_entry *rebindings,
                                           section_t *section,
                                           intptr_t slide,
                                           nlist_t *symtab,
                                           char *strtab,
                                           uint32_t *indirect_symtab) {
    uint32_t *indirect_symbol_indices = indirect_symtab + section->reserved1;
    void **indirect_symbol_bindings = (void **)((uintptr_t)slide + section->addr);
    for (uint i = 0; i < section->size / sizeof(void *); i++) {
        uint32_t symtab_index = indirect_symbol_indices[i];
        if (symtab_index == INDIRECT_SYMBOL_ABS || symtab_index == INDIRECT_SYMBOL_LOCAL ||
            symtab_index == (INDIRECT_SYMBOL_LOCAL   | INDIRECT_SYMBOL_ABS)) {
            continue;
        }
        uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
        char *symbol_name = strtab + strtab_offset;
        bool symbol_name_longer_than_1 = symbol_name[0] && symbol_name[1];
        struct rebindings_entry *cur = rebindings;
        while (cur) {
            for (uint j = 0; j < cur->rebindings_nel; j++) {
                if (symbol_name_longer_than_1 &&
                    strcmp(&symbol_name[1], cur->rebindings[j].name) == 0) {
                    if (cur->rebindings[j].replaced != NULL &&
                        indirect_symbol_bindings[i] != cur->rebindings[j].replacement) {
                        *(cur->rebindings[j].replaced) = indirect_symbol_bindings[i];
                    }
                    indirect_symbol_bindings[i] = cur->rebindings[j].replacement;
                    goto symbol_loop;
                }
            }
            cur = cur->next;
        }
    symbol_loop:;
    }
}

static void rebind_symbols_for_image(struct rebindings_entry *rebindings,
                                     const struct mach_header *header,
                                     intptr_t slide) {
    Dl_info info;
    if (dladdr(header, &info) == 0) {
        return;
    }
    
    segment_command_t *cur_seg_cmd;
    segment_command_t *linkedit_segment = NULL;
    struct symtab_command* symtab_cmd = NULL;
    struct dysymtab_command* dysymtab_cmd = NULL;
    
    uintptr_t cur = (uintptr_t)header + sizeof(mach_header_t);
    for (uint i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (segment_command_t *)cur;
        if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            if (strcmp(cur_seg_cmd->segname, SEG_LINKEDIT) == 0) {
                linkedit_segment = cur_seg_cmd;
            }
        } else if (cur_seg_cmd->cmd == LC_SYMTAB) {
            symtab_cmd = (struct symtab_command*)cur_seg_cmd;
        } else if (cur_seg_cmd->cmd == LC_DYSYMTAB) {
            dysymtab_cmd = (struct dysymtab_command*)cur_seg_cmd;
        }
    }
    
    if (!symtab_cmd || !dysymtab_cmd || !linkedit_segment ||
        !dysymtab_cmd->nindirectsyms) {
        return;
    }
    
    // Find base symbol/string table addresses
    uintptr_t linkedit_base = (uintptr_t)slide + linkedit_segment->vmaddr - linkedit_segment->fileoff;
    nlist_t *symtab = (nlist_t *)(linkedit_base + symtab_cmd->symoff);
    char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);
    
    // Get indirect symbol table (array of uint32_t indices into symbol table)
    uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);
    
    cur = (uintptr_t)header + sizeof(mach_header_t);
    for (uint i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (segment_command_t *)cur;
        if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            if (strcmp(cur_seg_cmd->segname, SEG_DATA) != 0 &&
                strcmp(cur_seg_cmd->segname, SEG_DATA_CONST) != 0) {
                continue;
            }
            for (uint j = 0; j < cur_seg_cmd->nsects; j++) {
                section_t *sect =
                (section_t *)(cur + sizeof(segment_command_t)) + j;
                if ((sect->flags & SECTION_TYPE) == S_LAZY_SYMBOL_POINTERS) {
                    perform_rebinding_with_section(rebindings, sect, slide, symtab, strtab, indirect_symtab);
                }
                if ((sect->flags & SECTION_TYPE) == S_NON_LAZY_SYMBOL_POINTERS) {
                    perform_rebinding_with_section(rebindings, sect, slide, symtab, strtab, indirect_symtab);
                }
            }
        }
    }
}


static int rebind_symbols_image(void *header,
                         intptr_t slide,
                         struct rebinding rebindings[],
                         size_t rebindings_nel) {
    struct rebindings_entry *rebindings_head = NULL;
    int retval = prepend_rebindings(&rebindings_head, rebindings, rebindings_nel);
    rebind_symbols_for_image(rebindings_head, (const struct mach_header *) header, slide);
    if (rebindings_head) {
        free(rebindings_head->rebindings);
    }
    free(rebindings_head);
    return retval;
}

////
//static void rebind_symbol(const char *name, void *replacement, void **replaced) {
//    dladdr();
//    rebind_symbols_image((struct rebinding[1]){{name, replacement, replaced}}, 1);
//}

