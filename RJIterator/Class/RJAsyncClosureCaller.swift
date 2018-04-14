//
//  RJAsyncClosureCaller.swift
//  RJIterator
//
//  Created by renjinkui on 2018/4/14.
//  Copyright © 2018年 renjinkui. All rights reserved.
//

import Foundation

class RJAsyncClosureCaller: NSObject {
    static func call(closure: Any, finish: @escaping RJAsyncCallback) {
        (closure as? RJAsyncClosure)?(finish)
    }
}
