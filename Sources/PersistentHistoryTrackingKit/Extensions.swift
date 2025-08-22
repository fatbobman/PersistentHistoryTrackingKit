//
//  Extensions.swift
//
//
//  Created by Yang Xu on 2022/2/12
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

import CoreData
import Foundation

extension NSManagedObjectContext {
    @discardableResult
    func performAndWaitWithResult<T>(_ block: () throws -> T) throws -> T {
        var result: Result<T, Error>?
        performAndWait {
            result = Result { try block() }
        }
        return try result!.get()
    }

    @discardableResult
    func performAndWaitWithResult<T>(_ block: () -> T) -> T {
        var result: T?
        performAndWait {
            result = block()
        }
        return result!
    }
}

public extension Task where Success == Never, Failure == Never {
    static func sleep(seconds duration: Double) async throws {
        try await sleep(nanoseconds: UInt64(duration * 1000000000))
    }
}

import Combine
/// 将Publisher转换成异步序列。
///
/// 同系统内置的 publisher.values 不同，本实现将首先对数据进行缓存。尤其适用于NotificationCenter之类的应用。
struct CombineAsyncPublisher<P>: AsyncSequence, AsyncIteratorProtocol where P: Publisher, P.Failure == Never {
    typealias Element = P.Output
    typealias AsyncIterator = CombineAsyncPublisher<P>

    func makeAsyncIterator() -> Self {
        return self
    }

    private let stream: AsyncStream<P.Output>
    private var iterator: AsyncStream<P.Output>.Iterator
    private var cancellable: AnyCancellable?

    init(_ upstream: P, bufferingPolicy limit: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded) {
        var subscription: AnyCancellable?
        stream = AsyncStream<P.Output>(P.Output.self, bufferingPolicy: limit) { continuation in
            subscription = upstream
                .sink(receiveValue: { value in
                    continuation.yield(value)
                })
        }
        cancellable = subscription
        iterator = stream.makeAsyncIterator()
    }

    mutating func next() async -> P.Output? {
        await iterator.next()
    }
}

extension Publisher where Self.Failure == Never {
    var sequence: CombineAsyncPublisher<Self> {
        CombineAsyncPublisher(self)
    }
}
