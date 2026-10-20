import Foundation

/// Checks for message notifications' pure inbox logic (`InboxThread`, `InboxBaseline`), driven by a caller-supplied assertion closure.
enum InboxChecks {
    static func run(_ check: (Bool, String) -> Void) {
        func t(_ id: String, _ unread: Bool) -> InboxThread { InboxThread(id: id, unread: unread, name: "N\(id)") }
        func ids(_ threads: [InboxThread]) -> [String] { threads.map(\.id) }

        // newlyUnread: unread now and not unread before (read or unknown).
        check(ids(InboxBaseline.newlyUnread(current: [t("a", true), t("b", false)], previous: [t("a", false), t("b", false)])) == ["a"], "read -> unread announces")
        check(InboxBaseline.newlyUnread(current: [t("a", true)], previous: [t("a", true)]).isEmpty, "still unread does not announce again")
        check(ids(InboxBaseline.newlyUnread(current: [t("c", true)], previous: [t("a", false)])) == ["c"], "a thread unknown before announces")
        check(InboxBaseline.newlyUnread(current: [t("a", false)], previous: [t("a", true)]).isEmpty, "unread -> read announces nothing")
        check(InboxBaseline.newlyUnread(current: [], previous: [t("a", true)]).isEmpty, "a thread scrolled out of the report announces nothing")

        // markingRead: a thread seen in the app is read in the baseline; nothing else changes.
        let previous = [t("a", true), t("b", true), t("c", false)]
        let marked = InboxBaseline.markingRead("a", in: previous)
        check(marked == [t("a", false), t("b", true), t("c", false)], "marking read changes only that thread")
        check(InboxBaseline.markingRead("z", in: previous) == previous, "an absent thread leaves the baseline unchanged")
        check(InboxBaseline.markingRead("c", in: previous) == previous, "an already read thread leaves the baseline unchanged")

        // The walkthrough: a message arrives, a background run announces it, the user reads the thread in the app,
        // backgrounds, and another message arrives in the same thread before any further background run.
        var baseline = [t("a", false)]
        let first = [t("a", true)]
        check(ids(InboxBaseline.newlyUnread(current: first, previous: baseline)) == ["a"], "walkthrough: first message announced")
        baseline = first
        baseline = InboxBaseline.markingRead("a", in: baseline)
        check(ids(InboxBaseline.newlyUnread(current: [t("a", true)], previous: baseline)) == ["a"], "walkthrough: reply after reading in the app announced")
        check(InboxBaseline.newlyUnread(current: [t("a", true)], previous: first).isEmpty, "without the read mark the reply would be missed")

        // Validation of a decoded batch.
        check(InboxThread.isValid([t("a", true), t("b", false)]), "valid batch")
        check(!InboxThread.isValid([t("a", true), t("a", false)]), "duplicate ids rejected")
        check(!InboxThread.isValid([InboxThread(id: "bad id", unread: true, name: "")]), "invalid id rejected")
        check(!InboxThread.isValid([InboxThread(id: "a", unread: true, name: String(repeating: "x", count: 81))]), "long name rejected")
        check(!InboxThread.isValid((0...50).map { t(String($0), false) }), "more than 50 threads rejected")
        check(InboxThread.isValidID("340282366920938463463374607431768211455") && !InboxThread.isValidID("") && !InboxThread.isValidID("a/b"), "thread id shape")
    }
}
