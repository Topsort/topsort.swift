import Foundation
#if canImport(CommonCrypto)
import CommonCrypto

extension String {
    public func hexSha1HashString() -> String {
        let data = self.data(using: .utf8)!
        var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

#endif
