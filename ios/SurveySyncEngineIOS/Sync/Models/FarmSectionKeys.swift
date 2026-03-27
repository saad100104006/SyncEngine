//
//  FarmSectionKeys.swift
//  SurveySyncEngineIOS
//

import Foundation

/// FarmSectionKeys provides the string identifiers for the
/// spec-mandated farm data structure.
/// These constants ensure consistency when saving or retrieving specific data points
/// within the 'farm' section of a survey.
public enum FarmSectionKeys {
    // The top-level key for the agricultural data section
    public static let sectionKey    = "farm"
    
    // Key for the text-based description of the crop (e.g., "Maize", "Cocoa")
    public static let cropType      = "crop_type"       // Associated with AnswerValue.text
    
    // Key for the numeric value representing farm size in hectares
    public static let areaHectares  = "area_hectares"   // Associated with AnswerValue.number
    
    // Key for the numeric value representing the expected harvest amount
    public static let yieldEstimate = "yield_estimate"  // Associated with AnswerValue.number
    
    // Key for the array of GPS points defining the physical perimeter of the farm
    public static let gpsBoundary   = "gps_boundary"    // Associated with AnswerValue.gpsBoundary
}

// MARK: - Supporting Types

/// Represents a single geographical coordinate captured by the device.
/// Conforming to Codable allows this to be serialized into JSON for Core Data storage
/// or network transmission via the SurveySyncEngine.
public struct GpsPoint: Codable {
    // The latitude coordinate in decimal degrees
    public let lat: Double
    
    // The longitude coordinate in decimal degrees
    public let lng: Double
    
    // The estimated horizontal accuracy of the point in meters
    public let accuracyMeters: Float
    
    /// Initializes a new GPS point with specific coordinates and accuracy.
    public init(lat: Double, lng: Double, accuracyMeters: Float) {
        self.lat = lat
        self.lng = lng
        self.accuracyMeters = accuracyMeters
    }
}
