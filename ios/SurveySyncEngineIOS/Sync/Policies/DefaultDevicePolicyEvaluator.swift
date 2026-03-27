//
//  DefaultDevicePolicyEvaluator.swift
//  SurveySyncEngineIOS
//
import Foundation
import CoreData

/// Concrete implementation of the DevicePolicyEvaluator responsible for checking
/// environmental conditions (battery, storage, network) before allowing a sync session to start.
public class DefaultDevicePolicyEvaluator: DevicePolicyEvaluator {
    
    // Providers allow the evaluator to stay decoupled from the actual hardware sensors (good for testing)
    private let batteryPercentProvider: () -> Int
    private let isChargingProvider: () -> Bool
    private let availableStorageBytesProvider: () -> Int64
    private let networkTypeProvider: () -> NetworkType

    // Internal thresholds used to make pass/fail decisions
    private enum Constants {
        static let minBatteryPercent = 15
        static let minStorageBytes: Int64 = 50 * 1024 * 1024   // 50 MB safety margin
        static let meteredMaxBytes: Int64 = 10 * 1024 * 1024   // 10 MB limit for cellular data
        static let lowBatteryDelay: TimeInterval = 0.2         // 200ms throttle between items
    }

    /// Initializes the evaluator with escaping closures to fetch real-time device stats.
    public init(
        batteryPercentProvider: @escaping () -> Int,
        isChargingProvider: @escaping () -> Bool,
        availableStorageBytesProvider: @escaping () -> Int64,
        networkTypeProvider: @escaping () -> NetworkType
    ) {
        self.batteryPercentProvider = batteryPercentProvider
        self.isChargingProvider = isChargingProvider
        self.availableStorageBytesProvider = availableStorageBytesProvider
        self.networkTypeProvider = networkTypeProvider
    }

    /// Runs a series of checks against current device conditions to generate a SyncPolicy.
    public func evaluate() -> SyncPolicy {
        // Capture current snapshots of device state
        let battery = batteryPercentProvider()
        let isCharging = isChargingProvider()
        let availableStorage = availableStorageBytesProvider()
        let networkType = networkTypeProvider()

        // 1. Critical battery check — prevents the app from killing the phone during a long sync
        if battery < Constants.minBatteryPercent && !isCharging {
            return SyncPolicy(
                shouldSync: false,
                skipReason: "Battery critically low (\(battery)%). Sync deferred.",
                networkType: networkType
            )
        }

        // 2. Storage check — ensures Core Data and file operations have room to breathe
        if availableStorage < Constants.minStorageBytes {
            return SyncPolicy(
                shouldSync: false,
                skipReason: "Device storage critically low (\(availableStorage / 1024)KB free).",
                networkType: networkType
            )
        }

        // 3. Throttle/Constraint Calculation
        
        // If battery is moderately low and not on a charger, we add a delay to reduce CPU heat/intensity
        let delayInSeconds: TimeInterval = (battery < 30 && !isCharging) ? Constants.lowBatteryDelay : 0
            
        // Convert to milliseconds for the SyncEngine's internal wait logic
        let itemDelay = Int64(delayInSeconds * 1000)
        
        // Apply data caps if the user is on a metered cellular connection to save their data plan
        let maxBytes = (networkType == .meteredCellular) ? Constants.meteredMaxBytes : nil
        
        // Return a 'Go' signal with the calculated constraints
        return SyncPolicy(
            shouldSync: true,
            maxBytesPerSession: maxBytes,
            itemDelay: itemDelay,
            networkType: networkType
        )
    }
}
