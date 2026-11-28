import Testing
@testable import GremloCore

struct SetupTests {
    @Test func petLookupSaysWhyInPlainWords() {
        #expect(Setup.petProblem(name: "pip", error: nil) == nil)
        #expect(Setup.petProblem(name: "pip", error: #"HTTP 404 {"error":"unknown pet"}"#)?.hasPrefix("No pet called pip yet") == true)
        #expect(Setup.petProblem(name: "pip", error: #"HTTP 500 {"error":"get_pet failed"}"#) == "The server said: get_pet failed. Press Retry.")
        #expect(Setup.petProblem(name: "pip", error: "The Internet connection appears to be offline.")?.hasPrefix("Can't reach the server") == true)
    }

    @Test func pairingWaitsForThisMacsKey() {
        #expect(Setup.pairProblem(secureEnclave: true, paired: true, error: nil) == nil)
        #expect(Setup.pairProblem(secureEnclave: true, paired: false, error: nil)?.hasPrefix("Not paired yet") == true)
        #expect(Setup.pairProblem(secureEnclave: true, paired: nil, error: "timed out")?.hasPrefix("Can't check the pairing") == true)
        #expect(Setup.pairProblem(secureEnclave: false, paired: true, error: nil)?.contains("no Secure Enclave") == true, "no enclave wins over anything the server says")
    }

    @Test func testProblemNamesTheFirstMissingPiece() {
        #expect(Setup.testProblem(connected: true, scriptExists: true, headerExists: true, heard: true, exitCode: 0) == nil)
        #expect(Setup.testProblem(connected: false, scriptExists: false, headerExists: false, heard: false, exitCode: nil)?.hasPrefix("Claude Code isn't connected") == true)
        #expect(Setup.testProblem(connected: true, scriptExists: true, headerExists: false, heard: false, exitCode: 0)?.contains("hook-header") == true)
        #expect(Setup.testProblem(connected: true, scriptExists: true, headerExists: true, heard: false, exitCode: 7)?.contains("exit 7") == true)
        #expect(Setup.testProblem(connected: true, scriptExists: true, headerExists: true, heard: false, exitCode: 0)?.contains("47474") == true)
    }
}
