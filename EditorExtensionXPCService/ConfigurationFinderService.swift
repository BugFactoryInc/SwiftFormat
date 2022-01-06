//
//  ConfigurationFinderService.swift
//  EditorExtensionXPCService
//
//  Created by Shangxin Guo on 2022/1/1.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import AppKit
import Foundation

@objc class ConfigurationFinderService: NSObject, ConfigurationFinderServiceProtocol {
    enum Error: Swift.Error {
        case failedToFetchXcodeFilePath
        case failedToFindConfigurationFile
        case failedToParseConfigurationFile
        case noAccessToAccessabilityAPI
    }
    
    func findConfiguration(withReply reply: @escaping ([String: String]?) -> Void) {
        do {
            let frontMostFileURL = try self.getXcodeFrontWindowFileURL()
            let configurationData = try self.findConfigurationFile(for: frontMostFileURL)
            let configuration = try parseConfigFile(configurationData)
            reply(configuration)
        } catch {
            reply(nil)
        }
    }
    
    func getXcodeFrontWindowFileURL() throws -> URL {
        let activeXcodes = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Xcode")
            .filter(\.isActive)

        // fetch file path of the frontmost window of Xcode through Accessability API.
        for xcode in activeXcodes {
            let application = AXUIElementCreateApplication(xcode.processIdentifier)
            do {
                let frontmostWindow = try application.copyValue(key: kAXFocusedWindowAttribute, ofType: AXUIElement.self)
                let path = try frontmostWindow.copyValue(key: kAXDocumentAttribute, ofType: String.self)
                return URL(fileURLWithPath: path)
            } catch {
                if let axError = error as? AXError, axError == .apiDisabled {
                    throw Error.noAccessToAccessabilityAPI
                }
                continue
            }
        }
        
        throw Error.failedToFetchXcodeFilePath
    }
    
    func findConfigurationFile(for fileURL: URL) throws -> Data {
        var directoryURL = fileURL
        
        while !directoryURL.pathComponents.contains("..") {
            defer { directoryURL.deleteLastPathComponent() }
            let fileURL = directoryURL.appendingPathComponent(swiftFormatConfigurationFile, isDirectory: false)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return try Data(contentsOf: fileURL)
            }
        }
        
        throw Error.failedToFindConfigurationFile
    }
}

func readToEnd(_ pipe: Pipe) throws -> Data? {
    if #available(macOS 10.15.4, *) {
        return try pipe.fileHandleForReading.readToEnd()
    } else {
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }
}

extension AXError: Error {}

extension AXUIElement {
    func copyValue<T>(key: String, ofType: T.Type = T.self) throws -> T {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(self, key as CFString, &value)
        if error == .success {
            return value as! T
        }
        throw error
    }
}