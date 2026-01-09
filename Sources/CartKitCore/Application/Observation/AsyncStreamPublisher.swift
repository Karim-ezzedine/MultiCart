import Combine
import Foundation

@MainActor
public struct AsyncStreamPublisher<Output: Sendable>: @MainActor Publisher {
    public typealias Failure = Never

    private let stream: AsyncStream<Output>

    public init(_ stream: AsyncStream<Output>) {
        self.stream = stream
    }

    public func receive<S: Subscriber>(subscriber: S)
    where S.Input == Output, S.Failure == Never {
        let subscription = StreamSubscription(stream: stream, subscriber: subscriber)
        subscriber.receive(subscription: subscription)
    }

    @MainActor
    private final class StreamSubscription<S: Subscriber>: @MainActor Subscription
    where S.Input == Output, S.Failure == Never {

        private var task: Task<Void, Never>?
        private var subscriber: S?

        init(stream: AsyncStream<Output>, subscriber: S) {
            self.subscriber = subscriber

            // MainActor isolation ensures we never touch `subscriber` off-main,
            // avoiding Sendable/data-race issues in Swift 6.
            self.task = Task { [weak self] in
                guard let self else { return }

                for await value in stream {
                    _ = self.subscriber?.receive(value)
                }
                self.subscriber?.receive(completion: .finished)
            }
        }

        func request(_ demand: Subscribers.Demand) {
            // Demand is not enforced for this lightweight bridge.
        }

        func cancel() {
            task?.cancel()
            task = nil
            subscriber = nil
        }
    }
}
