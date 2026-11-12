import CoreTelephony

/// Reads the current radio access technology (5G/LTE/3G...) of the data SIM.
final class RadioInfo {
    private let info = CTTelephonyNetworkInfo()

    var current: Radio {
        let techs = info.serviceCurrentRadioAccessTechnology ?? [:]
        // Prefer the data service when known; otherwise any reported service.
        let tech = info.dataServiceIdentifier.flatMap { techs[$0] } ?? techs.values.first
        return Self.map(tech)
    }

    static func map(_ tech: String?) -> Radio {
        switch tech {
        case CTRadioAccessTechnologyNR: return .nr5gSA
        case CTRadioAccessTechnologyNRNSA: return .nr5gNSA
        case CTRadioAccessTechnologyLTE: return .lte
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB, CTRadioAccessTechnologyeHRPD:
            return .g3
        case CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyCDMA1x:
            return .g2
        default: return .unknown
        }
    }
}
