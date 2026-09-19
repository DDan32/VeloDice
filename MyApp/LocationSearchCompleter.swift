import Foundation
import MapKit
import Combine

// MARK: - Location Search Completer for Apple Maps / Google Maps style Autocomplete
@MainActor
public class LocationSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    public static let shared = LocationSearchCompleter()
    
    @Published public var queryFragment: String = ""
    @Published public var suggestions: [MKLocalSearchCompletion] = []
    @Published public var isSearching: Bool = false
    
    private var completer: MKLocalSearchCompleter
    private var cancellables = Set<AnyCancellable>()
    
    override public init() {
        self.completer = MKLocalSearchCompleter()
        super.init()
        
        self.completer.delegate = self
        self.completer.resultTypes = [.address, .pointOfInterest]
        
        // 監聽使用者輸入並設定 debounce，避免高頻重複請求 (大幅節省行動網路流量)
        $queryFragment
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] newQuery in
                guard let self = self else { return }
                let trimmed = newQuery.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed == "目前位置" || trimmed == "當前位置" {
                    self.suggestions = []
                    self.isSearching = false
                } else {
                    self.isSearching = true
                    self.completer.queryFragment = trimmed
                }
            }
            .store(in: &cancellables)
    }
    
    public func updateQuery(_ query: String) {
        self.queryFragment = query
    }
    
    public func updateRegion(center: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
    }
    
    // MARK: - MKLocalSearchCompleterDelegate
    nonisolated public func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.suggestions = Array(completer.results.prefix(8))
            self.isSearching = false
        }
    }
    
    nonisolated public func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
            self.isSearching = false
        }
    }
}
