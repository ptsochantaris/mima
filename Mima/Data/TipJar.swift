import Foundation
import StoreKit
import SwiftUI

@Observable @MainActor
final class Tip {
    enum State {
        case notPurchased, otherWasPurchased, purchased
    }

    let image: String
    let productId: String

    var fetchedProduct: Product? {
        didSet {
            if let fetchedProduct {
                priceString = fetchedProduct.displayPrice
            }
        }
    }

    var priceString: String
    var state: State

    init(productId: String, image: String) {
        priceString = "…"
        self.productId = productId
        self.image = image
        state = .notPurchased
    }
}

enum TipJarError: LocalizedError {
    case noFetchedProduct(String)

    var errorDescription: String? {
        switch self {
        case let .noFetchedProduct(error):
            error
        }
    }
}

@MainActor @Observable
final class TipJar {
    enum State {
        case busy, ready, success, error(Error)
    }

    let tip1 = Tip(productId: "build.bru.Mima.TipTier1", image: "🙂")
    let tip2 = Tip(productId: "build.bru.Mima.TipTier2", image: "🤗")
    let tip3 = Tip(productId: "build.bru.Mima.TipTier3", image: "😱")
    var state = State.busy

    init() {
        Task {
            do {
                var products = try await Product.products(for: [tip1.productId, tip2.productId, tip3.productId])
                if products.count < 3 {
                    log("Error fetching tip jar: Missing products")
                    state = .error(TipJarError.noFetchedProduct("Could not fetch products from App Store"))
                    return
                }
                products.sort { $0.id < $1.id }
                tip1.fetchedProduct = products[0]
                tip2.fetchedProduct = products[1]
                tip3.fetchedProduct = products[2]
                log("Fetched tip list")
                state = .ready
            } catch {
                log("Error fetching tip jar: \(error.localizedDescription)")
                state = .error(error)
            }
        }
        Task {
            for await transactionResult in Transaction.updates {
                await completeTransaction(transactionResult)
            }
        }
        Task {
            for await transactionResult in Transaction.unfinished {
                await completeTransaction(transactionResult)
            }
        }
    }

    private func completeTransaction(_ transaction: VerificationResult<StoreKit.Transaction>) async {
        switch transaction {
        case let .unverified(transaction, error):
            state = .error(error)
            await transaction.finish()

        case let .verified(transaction):
            for tip in [tip1, tip2, tip3] {
                tip.state = transaction.productID == tip.productId ? .purchased : .otherWasPurchased
            }
            state = .success
            await transaction.finish()
        }
    }

    func purchase(_ tip: Tip) {
        state = .busy
        Task {
            do {
                guard let product = tip.fetchedProduct else {
                    state = .error(TipJarError.noFetchedProduct("Did not find an associated App Store product for this tip"))
                    return
                }

                switch try await product.purchase() {
                case let .success(result):
                    await completeTransaction(result)

                case .userCancelled:
                    state = .ready

                case .pending:
                    fallthrough

                @unknown default:
                    break
                }
            } catch {
                state = .error(error)
            }
        }
    }
}
