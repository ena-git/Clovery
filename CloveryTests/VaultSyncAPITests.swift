import Foundation
import XCTest
@testable import Clovery

@MainActor
final class VaultSyncAPITests: XCTestCase {
    override func tearDown() {
        VaultAPIURLProtocolStub.reset()
        super.tearDown()
    }

    func testPushAndPullMatchGoHTTPContract() async throws {
        VaultAPIURLProtocolStub.handler = { request in
            if request.url?.path == "/v1/vault/sync/push" {
                return Self.response(
                    status: 200,
                    body: #"{"results":[{"operation_id":"11111111-1111-4111-8111-111111111111","status":"applied","entry":{"entry_id":"22222222-2222-4222-8222-222222222222","revision":1,"payload":{"id":"22222222-2222-4222-8222-222222222222","text":"hello"}},"cursor":9}]}"#
                )
            }
            return Self.response(
                status: 200,
                body: #"{"changes":[{"cursor":10,"entity_type":"journal_entry","entity_id":"22222222-2222-4222-8222-222222222222","revision":2,"operation_id":"33333333-3333-4333-8333-333333333333","payload":{"id":"legacy-id","text":"updated"},"deleted":false,"changed_at":"2026-07-27T00:00:00Z"}],"next_cursor":10,"has_more":false}"#
            )
        }
        let api = makeAPI()
        let operation = VaultSyncOperation(
            operationID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            entryID: "22222222-2222-4222-8222-222222222222",
            baseRevision: 0,
            payload: .object(["text": .string("hello")]),
            deleted: false
        )

        let decisions = try await api.push([operation])
        let page = try await api.pull(cursor: 9, limit: 50)

        XCTAssertEqual(decisions.first?.status, .applied)
        XCTAssertEqual(decisions.first?.cursor, 9)
        XCTAssertEqual(page.nextCursor, 10)
        XCTAssertEqual(page.changes.first?.entityID, operation.entryID)
        XCTAssertEqual(
            VaultAPIURLProtocolStub.requests.map { $0.url?.path },
            ["/v1/vault/sync/push", "/v1/vault/sync/pull"]
        )
        XCTAssertEqual(VaultAPIURLProtocolStub.requests[1].url?.query, "cursor=9&limit=50")
        let pushJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try XCTUnwrap(VaultAPIURLProtocolStub.requests[0].capturedBodyData)
            ) as? [String: Any]
        )
        let operations = try XCTUnwrap(pushJSON["operations"] as? [[String: Any]])
        XCTAssertEqual(operations.first?["operation_id"] as? String, operation.operationID.uuidString.lowercased())
        XCTAssertEqual(operations.first?["entry_id"] as? String, operation.entryID)
        XCTAssertNil(operations.first?["account_id"])
        XCTAssertNil(operations.first?["vault_id"])
        VaultAPIURLProtocolStub.requests.forEach {
            XCTAssertEqual($0.value(forHTTPHeaderField: "Authorization"), "Bearer vault-access")
        }
    }

    private func makeAPI() -> VaultSyncAPI {
        VaultSyncAPI(client: makeVaultAuthenticatedClient())
    }

    nonisolated private static func response(
        status: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: URL(string: "https://api.example")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }
}

