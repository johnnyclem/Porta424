import XCTest
@testable import PortaDSPKit

final class PlaceholderTests: XCTestCase {
    func testPortaDSPParamsBridgeRoundTrip() {
        var params = PortaDSP.Params()
        params.wowDepth = 0.5
        let cStruct = params.makeCParams()
        XCTAssertEqual(cStruct.wowDepth, params.wowDepth)
        XCTAssertEqual(cStruct.nrTrack4Bypass, params.nrTrack4Bypass ? 1 : 0)
    }
}
