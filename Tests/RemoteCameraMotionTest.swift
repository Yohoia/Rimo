import Foundation

@main
struct RemoteCameraMotionTest {
    static func main() {
        let start = Date(timeIntervalSince1970: 100)
        var camera = RemoteCameraMotion()
        precondition(camera.progress(at: start) == 0)

        camera.retarget(focused: true, at: start, pose: .detail, glow: 0.45, reduceMotion: false)
        let push = camera.movement!
        let midway = start.addingTimeInterval(0.20)
        let halfwayProgress = camera.progress(at: midway)
        precondition(halfwayProgress > 0 && halfwayProgress < 1)

        // Switching keys or sidebars shares the same camera target.
        camera.retarget(focused: true, at: midway, pose: .detail, glow: 0.45, reduceMotion: false)
        precondition(camera.movement?.startedAt == start)
        precondition(camera.progress(at: start.addingTimeInterval(push.duration + 0.01)) == 1)

        // Reverse from the currently rendered position, then interrupt that reversal.
        camera.retarget(focused: false, at: midway, pose: .detail, glow: 0.45, reduceMotion: false)
        precondition(abs(camera.progress(at: midway) - halfwayProgress) < 0.000001)
        let reversing = midway.addingTimeInterval(0.04)
        let reversingProgress = camera.progress(at: reversing)
        precondition(reversingProgress < halfwayProgress)
        camera.retarget(focused: true, at: reversing, pose: .detail, glow: 0.45, reduceMotion: false)
        precondition(abs(camera.progress(at: reversing) - reversingProgress) < 0.000001)

        // An older completion cannot clear a replacement transition.
        camera.finish(startedAt: push.startedAt)
        precondition(camera.movement?.startedAt == reversing)
        let finalPush = camera.movement!
        let finish = reversing.addingTimeInterval(finalPush.duration + 0.01)
        let beforeCompletion = camera.progress(at: finish)
        camera.finish(startedAt: finalPush.startedAt)
        precondition(camera.progress(at: finish) == beforeCompletion)
        precondition(camera.movement == nil && camera.focused)

        camera.reset(focused: false)
        precondition(camera.progress(at: finish) == 0 && camera.movement == nil)
        camera.retarget(focused: true, at: finish, pose: .detail, glow: 0.45, reduceMotion: true)
        precondition(camera.progress(at: finish) == 1 && camera.movement == nil)
        camera.retarget(focused: false, at: finish, pose: .detail, glow: 0.45, reduceMotion: true)
        precondition(camera.progress(at: finish) == 0 && camera.movement == nil)
        print("Camera entry, repeated targets, reversal continuity, stale completion and reduced motion passed.")
    }
}
