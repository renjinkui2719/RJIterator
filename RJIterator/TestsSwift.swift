//
//  TestsSwift.swift
//  RJIterator
//
//  Created by renjinkui on 2018/4/14.
//  Copyright © 2018年 renjinkui. All rights reserved.
//

import UIKit

fileprivate func talk(name: Any?) -> Any? {
    var cmd = ""
    repeat {
        rj_yield("Hello \(name ?? ""), How are you?");
        rj_yield("Today is Friday");
        rj_yield("So yestday is Thursday");
        rj_yield("And tomorrow is Saturday");
        cmd = rj_yield("Over") as? String ?? "";
    }while cmd != "Over"
    
    return "==talk done==";
}

func count_1_3(_: Any?) -> Any? {
    rj_yield(1)
    rj_yield(2)
    return 3
}
func count_4_5(_: Any?) -> Any? {
    rj_yield(4)
    rj_yield(5)
    return 6
}
func count_7_9(_: Any?) -> Any? {
    rj_yield(7)
    rj_yield(8)
    return 9
}

func count(_: Any?) -> Any? {
    rj_yield(RJIterator.init(withFunc: count_1_3, arg: nil))
    rj_yield(RJIterator.init(withFunc: count_4_5, arg: nil))
    rj_yield(RJIterator.init(withFunc: count_7_9, arg: nil))
    return nil
}

class TestsSwift: NSObject {
    
    static func verboseTests() {
        test0()
        test1()
        test2()
        test3()
        test4()
        test5()
        test6()
        test7()
        async1()
        async2()
    }
    
    static func test0() {
        print("************************ Begin test0 *******************************");
        var it: RJIterator;
        var r: RJResult;
        
        it = RJIterator.init(withFunc: count, arg:nil)
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next("again")
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next("again")
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next("again")
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next("again")
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next("again")
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        print("************************ End test0 *******************************");
    }

    
    static func test1() {
        print("************************ Begin test1 *******************************");
        var it: RJIterator;
        var r: RJResult;
        
        it = RJIterator.init(withFunc: talk, arg: "爱德华")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next("again")
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next("again")
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next("again")
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next("again")
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        r = it.next("again")
        print("value: \(r.value), done:\(r.done)")
        r = it.next()
        print("value: \(r.value), done:\(r.done)")
        print("************************ End test1 *******************************");
    }
    
    @objc func Fibonacci() -> NSNumber {
        var prev = 0;
        var cur = 1;
        while(true) {
            rj_yield(cur);
            
            let p = prev;
            prev = cur;
            cur = p + cur;
            
            if (cur > 6765) {
                break;
            }
        }
        return (cur as NSNumber);
    }
    
    static func test2() {
        print("************************ Begin test2 *******************************");
        var it: RJIterator;
        var r: RJResult;
        
        it = RJIterator.init(target: TestsSwift.init(), selector: #selector(Fibonacci), args: nil)
        
        repeat {
            r = it.next()
            print("value: \(r.value), done:\(r.done)")
        }while(!r.done)
        
        print("************************ End test2 *******************************");
    }
    
    
    //迭代器嵌套
    @objc func dataBox(name: String, age: NSNumber) -> String {
        print("==in dataBox/enter");
        rj_yield("Hello, I know you name:\(name), age:\(age), you want some data");
        rj_yield("Fibonacci:");
        print("==in dataBox/will return Fibonacci");
        rj_yield(RJIterator.init(target: self, selector: #selector(Fibonacci), args: nil));
        rj_yield("Random Data:");
        print("==in dataBox/will return Random Data");
        rj_yield("🐶");
        rj_yield([]);
        rj_yield(12345 as NSNumber);
        rj_yield(self);
        return "dataBox Over";
    }
    
    
    @objc func dataBox2(name: String, age: NSNumber) -> String {
        //更深嵌套
        rj_yield(RJIterator.init(target: TestsSwift.init(), selector: #selector(dataBox(name:age:)), args: ["RJK", 28]))
        
        print("==in dataBox2/enter");
        rj_yield("Hello, I know you name:\(name), age:\(age), you want some data");
        rj_yield("Fibonacci:");
        print("==in dataBox2/will return Fibonacci");
        rj_yield(RJIterator.init(target: self, selector: #selector(Fibonacci), args: nil));
        rj_yield("Random Data:");
        print("==in dataBox2/will return Random Data");
        rj_yield("🐶");
        rj_yield([]);
        rj_yield(12345 as NSNumber);
        rj_yield(self);
        return "dataBox2 Over";
    }
    
    
    static func test3() {
        print("************************ Begin test3 *******************************");
        var it: RJIterator;
        var r: RJResult;
        
        it = RJIterator.init(target: TestsSwift.init(), selector: #selector(dataBox(name:age:)), args: ["RJK", 28]);
        
        repeat {
            r = it.next()
            print("value: \(r.value), done:\(r.done)")
        }while(!r.done)
        print("************************ End test3 *******************************");
    }
    
    static func test4() {
        print("************************ Begin test4 *******************************");
        var it: RJIterator;
        var r: RJResult;
        
        it = RJIterator.init(target: TestsSwift.init(), selector: #selector(dataBox2(name:age:)), args: ["Walt White", 48]);
        
        repeat {
            r = it.next()
            print("value: \(r.value), done:\(r.done)")
        }while(!r.done)
        print("************************ End test4 *******************************");
    }
    
    static func test5() {
        print("************************ Begin test5 *******************************");
        var it: RJIterator;
        var r: RJResult;
        
        it = RJIterator.init(standardBlock: {
            print("Hello");
            rj_yield("🐶");
            rj_yield([]);
            rj_yield(12345 as NSNumber);
            rj_yield(self);
        })
        
        repeat {
            r = it.next()
            print("value: \(r.value), done:\(r.done)")
        }while(!r.done)
        
        it = RJIterator.init(block: { (name) -> Any? in
            print("Hello \(name)");
            rj_yield("🐶");
            rj_yield([]);
            rj_yield(12345 as NSNumber);
            rj_yield(self);
            return "Done"
        }, arg: "JJK")
        
        repeat {
            r = it.next()
            print("value: \(r.value), done:\(r.done)")
        }while(!r.done)
        print("************************ End test5 *******************************");
    }
    
    @objc static func ClassFibonacci() -> NSNumber {
        var prev = 0;
        var cur = 1;
        while(true) {
            rj_yield(cur);
            
            let p = prev;
            prev = cur;
            cur = p + cur;
            
            if (cur > 6765) {
                break;
            }
        }
        return (cur as NSNumber);
    }
    
    static func test6() {
        print("************************ Begin test6 *******************************");
        var it: RJIterator;
        var r: RJResult;
        
        it = RJIterator.init(target: TestsSwift.self, selector: #selector(ClassFibonacci), args: nil)
        
        repeat {
            r = it.next()
            print("value: \(r.value), done:\(r.done)")
        }while(!r.done)
        
        print("************************ End test6 *******************************");
    }
    
    @objc static func talk2(name: String) {
        let really_name = rj_yield("FakeName: \(name)")
        print("==talk2/really_name:\(really_name)")
    }
    
    static func test7() {
        print("************************ Begin test7 *******************************");
        var it: RJIterator;
        var r: RJResult;

        it = RJIterator.init(target: TestsSwift.self, selector: #selector(talk2(name:)), args: ["第一帅"])
        r = it.next();
        print("value: \(r.value), done:\(r.done)")
        r = it.next("JK");
        print("value: \(r.value), done:\(r.done)")
        print("************************ End test7 *******************************");
    }
    
    static func s1() -> RJAsyncClosure {
        return { (callback: @escaping RJAsyncCallback) in
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2, execute: {
                callback(["a1": 1, "a2":2], nil);
            })
        };
    }
    static func s2() -> RJAsyncClosure {
        return { (callback: @escaping RJAsyncCallback) in
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2, execute: {
                callback(["b1": 1, "b2":2], /*NSError.init(domain: "s2", code: -1, userInfo: nil)*/nil);
            })
        };
    }
    static func s3() -> RJAsyncClosure {
        return {(callback: @escaping RJAsyncCallback) in
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2, execute: {
                callback(["c1": 1, "c2":2], nil);
            })
        };
    }
    static func s4() -> RJAsyncClosure {
        return { (callback: @escaping RJAsyncCallback) in
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2, execute: {
                callback(["d1": 1, "d2":2], nil);
            })
        };
    }

    static func async1() {
      print("************************ Begin async1 *******************************");
        rj_async {
            var v: Any? = nil
            print("...begin s1")
            v = rj_yield(s1())
            print("finis s1, v:\(v)")
            print("...begin s2")
            v = rj_yield(s2())
            print("finis s2, v:\(v)")
            print("...begin s3")
            v = rj_yield(s3())
            print("finis s3, v:\(v)")
            print("...begin s4")
            v = rj_yield(s4())
            print("finis s4, v:\(v)")
            print("all done")
        }
        .error{error in
            print("error happen:\(error)");
        }
        .finally {
            print("finally");
        }
       print("************************ End async1 *******************************");
    }
    

    static func s2_error() -> RJAsyncClosure {
        return { (callback: @escaping RJAsyncCallback) in
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2, execute: {
                callback(["b1": 1, "b2":2], NSError.init(domain: "s2", code: -1, userInfo: nil));
            })
        };
    }
    
    static func async2() {
        print("************************ Begin async2 *******************************");
        rj_async {
            var v: Any? = nil
            print("...begin s1")
            v = rj_yield(s1())
            print("finis s1, v:\(v)")
            print("...begin s2")
            v = rj_yield(s2_error())
            print("finis s2, v:\(v)")
            print("...begin s3")
            v = rj_yield(s3())
            print("finis s3, v:\(v)")
            print("...begin s4")
            v = rj_yield(s4())
            print("finis s4, v:\(v)")
            print("all done")
            }
            .error{error in
                print("error happen:\(error)");
            }
            .finally {
                print("finally");
        }
        print("************************ End async2 *******************************");
    }
}
