// Demo örneğine DistributedNotification kancası gönderir (bkz. scripts/make-screenshots.sh).
// Kullanım: pikomacv-hook <ad> [nesne]     örn: pikomacv-hook show general
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("Kullanim: pikomacv-hook <ad> [nesne]\n".utf8))
    exit(2)
}
let object: String? = args.count >= 3 ? args[2] : nil
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.pikomacv.app.debug." + args[1]), object: object, userInfo: nil, deliverImmediately: true)
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
