import Foundation

/// Priority and validation for the TestFlight server address.
///   Tools/run_api_base_url_checks.sh

private var failures = 0

private func check(_ condition: Bool, _ message: String) {
    if condition { return }
    failures += 1
    fputs("FAIL \(message)\n", stderr)
}

private func resolved(_ input: APIBaseURLResolver.Input) -> APIBaseURLResolver.Resolution {
    APIBaseURLResolver.resolve(input)
}

private func assertPriority() {
    let input = APIBaseURLResolver.Input(
        manual: "https://manual.example",
        cached: "https://cache.example",
        remote: "https://remote.example",
        plist: "https://plist.example",
        localFallback: "http://localhost:8080"
    )
    let manual = resolved(input)
    check(manual.source == .manual && manual.url?.absoluteString == "https://manual.example", "manual wins")

    var cache = input
    cache.manual = "  "
    let cached = resolved(cache)
    check(cached.source == .cache && cached.url?.absoluteString == "https://cache.example", "cache beats remote")

    var remote = cache
    remote.cached = nil
    let fromRemote = resolved(remote)
    check(fromRemote.source == .remote && fromRemote.url?.absoluteString == "https://remote.example", "remote beats plist")

    var plist = remote
    plist.remote = "$(MEALROUTINE_REMOTE_CONFIG_URL)"
    let fromPlist = resolved(plist)
    check(fromPlist.source == .plist && fromPlist.url?.absoluteString == "https://plist.example", "plist beats localhost")

    var local = plist
    local.plist = ""
    let fromLocal = resolved(local)
    check(fromLocal.source == .local && fromLocal.url?.absoluteString == "http://localhost:8080", "localhost fallback")

    var none = local
    none.localFallback = nil
    check(resolved(none).source == .none && resolved(none).url == nil, "missing address")
}

private func assertValidation() {
    check(APIBaseURLResolver.normalize("https://abc.trycloudflare.com/v1/health?x=1")?.absoluteString == "https://abc.trycloudflare.com", "strips path and query")
    check(APIBaseURLResolver.normalize("https://abc.trycloudflare.com:8443/")?.absoluteString == "https://abc.trycloudflare.com:8443", "keeps port")
    check(APIBaseURLResolver.normalize("http://localhost:8080/")?.absoluteString == "http://localhost:8080", "localhost http")
    check(APIBaseURLResolver.normalize("http://127.0.0.1:8080")?.absoluteString == "http://127.0.0.1:8080", "loopback http")
    check(APIBaseURLResolver.normalize("http://192.168.1.20:8080") == nil, "rejects public http")
    check(APIBaseURLResolver.normalize("https://user:secret@abc.trycloudflare.com") == nil, "rejects userinfo")
    check(APIBaseURLResolver.normalize("ftp://abc.trycloudflare.com") == nil, "rejects ftp")
    check(APIBaseURLResolver.normalize("$(MEALROUTINE_API_BASE_URL)") == nil, "rejects placeholder")
    check(APIBaseURLResolver.normalize("   ") == nil, "rejects blank")

    let payload = Data("{\"apiBaseURL\":\"https://new.trycloudflare.com/ignored\"}".utf8)
    check(APIBaseURLResolver.parseRemoteConfig(payload) == "https://new.trycloudflare.com", "parses gist json")
    let stale = "https://old.trycloudflare.com"
    check(APIBaseURLResolver.cacheAfterRemotePayload(payload, currentCache: stale) == "https://new.trycloudflare.com", "successful gist replaces cache")
    let broken = Data("not-json".utf8)
    check(APIBaseURLResolver.cacheAfterRemotePayload(broken, currentCache: stale) == stale, "failed gist keeps cache")
    check(APIBaseURLResolver.cacheAfterRemotePayload(broken, currentCache: "http://10.0.0.8") == nil, "invalid cache is not kept")
}

private func assertPushGate() {
    check(HouseholdLocalPushGate.deliversLocalNotification(testMode: false, remoteAPIConfigured: false), "local banner without remote api")
    check(!HouseholdLocalPushGate.deliversLocalNotification(testMode: false, remoteAPIConfigured: true), "suppress copy when remote push is configured")
    check(!HouseholdLocalPushGate.deliversLocalNotification(testMode: true, remoteAPIConfigured: false), "test mode does not schedule a local notification")
    check(APIBaseURLResolver.missingServerMessage == "sunucu adresi yok", "missing server copy")
}

@main
struct APIBaseURLChecks {
    static func main() {
        assertPriority()
        assertValidation()
        assertPushGate()
        if failures > 0 {
            fputs("\(failures) api base url checks failed\n", stderr)
            exit(1)
        }
        fputs("api base url checks passed\n", stderr)
    }
}
