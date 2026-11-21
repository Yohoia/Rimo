import Foundation

@main
struct ToastTest {
    @MainActor
    static func main() async throws {
        let center = RimoToastCenter()
        center.show("第一条", duration: .milliseconds(40))
        let previous = center.current!.id
        center.show("已改为长按", kind: .success, duration: .milliseconds(250))
        let current = center.current!.id
        center.dismiss(id: previous)
        precondition(center.current?.id == current, "A stale dismissal removed the new toast")
        try await Task.sleep(for: .milliseconds(90))
        precondition(center.current?.message == "已改为长按", "The previous timer removed a replacement toast")
        center.show("已改为长按", duration: .milliseconds(250))
        precondition(center.current?.id != current, "Repeated feedback must renew its lifetime")
        center.dismiss(id: center.current!.id)
        precondition(center.current == nil)
        center.show("动作执行失败", kind: .error, detail: "诊断详情", duration: .milliseconds(40))
        precondition(center.current?.detail == "诊断详情")
        try await Task.sleep(for: .milliseconds(100))
        precondition(center.current == nil, "Toast did not dismiss automatically")
        print("PASS: global replacement, stale dismissal, timer cancellation, repeated feedback, manual dismissal, details and automatic expiry")
    }
}
