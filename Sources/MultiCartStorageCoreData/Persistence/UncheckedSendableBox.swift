//
//  UncheckedSendableBox.swift
//  MultiCart
//
//  Created by Karim Ezzedine on 17/12/2025.
//


import Foundation

/// A minimal wrapper used to pass non-Sendable references across `@Sendable` closures.
///
/// This is safe here because `NSManagedObjectContext` is still used correctly:
/// all access happens within `context.perform {}` which enforces Core Data thread confinement.
final class UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
