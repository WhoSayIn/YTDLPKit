import SwiftUI
import YTDLPKit

struct ContentView: View {
  @State private var input = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  @State private var status = "Enter a URL to extract metadata."
  @State private var isExtracting = false

  private let client: YTDLPClient?

  init() {
    client = try? YTDLPClient(configuration: .init())
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Media URL") {
          TextField("https://…", text: $input)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()

          Button("Extract metadata") {
            extract()
          }
          .disabled(isExtracting || URL(string: input) == nil || client == nil)
        }

        Section("Result") {
          if isExtracting {
            ProgressView("Extracting…")
          } else {
            Text(status)
          }
        }

        Section {
          Text("The example does not display, store, or log signed stream URLs.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("YTDLPKit")
    }
  }

  private func extract() {
    guard let url = URL(string: input), let client else { return }
    isExtracting = true

    Task {
      defer { isExtracting = false }
      do {
        let media = try await client.extract(ExtractionRequest(url: url))
        status = media.title
      } catch {
        // YTDLPKit error descriptions are safe for display. The example
        // deliberately avoids dumping arbitrary underlying errors.
        status =
          (error as? YTDLPError).map(String.init(describing:))
          ?? "Extraction failed."
      }
    }
  }
}

#Preview {
  ContentView()
}
