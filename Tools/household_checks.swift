import Foundation

@main
struct HouseholdChecks {
    static func main() {
        let failures = HouseholdLogicChecks.runAll()
        if failures.isEmpty {
            print("household checks passed")
        } else {
            for failure in failures {
                fputs("\(failure)\n", stderr)
            }
            exit(1)
        }
    }
}
