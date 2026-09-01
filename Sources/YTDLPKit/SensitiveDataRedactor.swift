import Foundation

enum SensitiveDataRedactor {
  private static let sensitiveKeys = [
    "authorization", "cookie", "cookies", "set-cookie", "token", "access_token",
    "refresh_token", "password", "passwd", "signature", "sig", "key", "api_key",
    "credential", "credentials",
  ]

  static func redact(_ input: String) -> String {
    var result = input

    // URLs frequently contain signed playback parameters. Preserve only the
    // scheme and host so diagnostics remain useful without exposing them.
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
      let matches = detector.matches(
        in: result,
        range: NSRange(result.startIndex..., in: result)
      )
      for match in matches.reversed() {
        guard let range = Range(match.range, in: result),
          let url = match.url
        else { continue }
        let replacement: String
        if let scheme = url.scheme, let host = url.host {
          replacement = "\(scheme)://\(host)/[REDACTED]"
        } else {
          replacement = "[REDACTED_URL]"
        }
        result.replaceSubrange(range, with: replacement)
      }
    }

    result = replacing(
      pattern:
        #"(?im)(\b(?:authorization|proxy-authorization)\b\s*[:=]\s*["']?(?:bearer|basic)\s+)[^\s,"';}\]]+"#,
      in: result,
      template: "$1[REDACTED]"
    )

    // Cookie headers can contain many semicolon-delimited credentials, so
    // redact the complete header value instead of only its first token.
    result = replacing(
      pattern: #"(?im)(\b(?:cookie|set-cookie)\b\s*:\s*)[^\r\n]+"#,
      in: result,
      template: "$1[REDACTED]"
    )

    for key in sensitiveKeys {
      let escaped = NSRegularExpression.escapedPattern(for: key)
      let pattern =
        "(?i)([\\\"']?\\b\(escaped)\\b[\\\"']?\\s*[:=]\\s*)(?:\\\"[^\\\"]*\\\"|'[^']*'|[^\\s,;&}\\]]+)"
      result = replacing(
        pattern: pattern,
        in: result,
        template: "$1[REDACTED]"
      )
    }

    // Python tracebacks reveal build/user names and sandbox locations. The
    // negative lookbehind avoids matching the path portion of a URL.
    result = replacing(
      pattern: #"(?<![:/A-Za-z0-9])/(?!/)[^\s"'<>]+"#,
      in: result,
      template: "[REDACTED_PATH]"
    )
    return result
  }

  private static func replacing(pattern: String, in input: String, template: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
    return regex.stringByReplacingMatches(
      in: input,
      range: NSRange(input.startIndex..., in: input),
      withTemplate: template
    )
  }
}
