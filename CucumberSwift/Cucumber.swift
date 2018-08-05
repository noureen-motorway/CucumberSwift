//
//  Cucumber.swift
//  CucumberSwift
//
//  Created by Tyler Thompson on 4/7/18.
//  Copyright © 2018 Asynchrony Labs. All rights reserved.
//

import Foundation
import XCTest
@objc public class Cucumber: NSObject, XCTestObservation {
    var features = [Feature]()
    var currentStep:Step? = nil
    var reportName:String = ""
    var environment:[String:String] = ProcessInfo.processInfo.environment
    public var BeforeFeature  :((Feature)  -> Void)?
    public var AfterFeature   :((Feature)  -> Void)?
    public var BeforeScenario :((Scenario) -> Void)?
    public var AfterScenario  :((Scenario) -> Void)?
    public var BeforeStep     :((Step)     -> Void)?
    public var AfterStep      :((Step)     -> Void)?

    init(withString string:String) {
        super.init()
        parseIntoFeatures(string)
    }
    
    public func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        currentStep?.result = .failed
        currentStep?.errorMessage = description
    }
    
    public init(withDirectory directory:String, inBundle bundle:Bundle, reportName:String = "CucumberTestResults.json") {
        super.init()
        self.reportName = reportName
        let enumerator:FileManager.DirectoryEnumerator? = FileManager.default.enumerator(at: bundle.bundleURL.appendingPathComponent(directory), includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if (url.pathExtension == "feature") {
                if let string = try? String(contentsOf: url, encoding: .utf8) {
                    parseIntoFeatures(string, uri: url.absoluteString)
                }
            }
        }
        XCTestObservationCenter.shared.addTestObserver(self)
    }
    
    private func parseIntoFeatures(_ string:String, uri:String = "") {
        let tokens = Lexer(input: string).lex()
        let ast = AST(tokens)
        features.append(contentsOf: ast.featureNodes.compactMap { Feature(with: $0, uri:uri) })
    }
    
    @discardableResult func generateUnimplementedStepDefinitions() -> String {
        var generatedSwift = ""
        let stubs = StubGenerator.getStubs(for: features)
        if (!stubs.isEmpty) {
            generatedSwift = stubs.joined(separator: "\n")
            XCTContext.runActivity(named: "Pending Steps") { activity in
                let attachment = XCTAttachment(uniformTypeIdentifier: "swift", name: "GENERATED_Unimplemented_Step_Definitions.swift", payload: generatedSwift.data(using: .utf8), userInfo: nil)
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
        return generatedSwift
    }
    
    public func executeFeatures() {
        generateUnimplementedStepDefinitions()
        var featuresToExecute = features
        if let tagNames = environment["CUCUMBER_TAGS"] {
            let tags = tagNames.components(separatedBy: ",")
            featuresToExecute = features.filter { $0.containsTags(tags) }
        }
        for feature in featuresToExecute {
            XCTContext.runActivity(named: "Feature: \(feature.title)") { _ in
                BeforeFeature?(feature)
                var scenariosToExecute = feature.scenarios
                if let tagNames = environment["CUCUMBER_TAGS"] {
                    let tags = tagNames.components(separatedBy: ",")
                    scenariosToExecute = feature.scenarios.filter { $0.containsTags(tags) }
                }
                for scenario in scenariosToExecute {
                    XCTContext.runActivity(named: "Scenario: \(scenario.title)") { _ in
                        BeforeScenario?(scenario)
                        for step in scenario.steps {
                            BeforeStep?(step)
                            currentStep = step
                            _ = XCTContext.runActivity(named: "\(step.keyword.toString()) \(step.match)") { _ -> String in
                                step.execute?(step.match.matches(for: step.regex), step)
                                if (step.execute != nil && step.result != .failed) {
                                    step.result = .passed
                                }
                                return ""
                            }
                            AfterStep?(step)
                        }
                        AfterScenario?(scenario)
                    }
                }
                AfterFeature?(feature)
            }
        }
        DispatchQueue.main.async {
            if  let documentDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor:nil, create:false),
                let data = try? JSONSerialization.data(withJSONObject: self.features.map { $0.toJSON() }, options: JSONSerialization.WritingOptions.prettyPrinted) {
                let fileURL = documentDirectory.appendingPathComponent(self.reportName)
                try? data.write(to: fileURL)
            }
        }
    }
    
    func attachClosureToSteps(keyword:Step.Keyword? = nil, regex:String, callback:@escaping (([String], Step) -> Void)) {
        features
        .flatMap { $0.scenarios.flatMap { $0.steps } }
        .filter { (step) -> Bool in
            if  let k = keyword,
                step.keyword.contains(k) {
                return !step.match.matches(for: regex).isEmpty
            } else if (keyword == nil) {
                return !step.match.matches(for: regex).isEmpty
            }
            return false
        }.forEach { (step) in
            step.result = .undefined
            step.execute = callback
            step.regex = regex
        }
    }
    
    public func Given(_ regex:String, callback:@escaping (([String], Step) -> Void)) {
        attachClosureToSteps(keyword: .given, regex: regex, callback:callback)
    }
    public func When(_ regex:String, callback:@escaping (([String], Step) -> Void)) {
        attachClosureToSteps(keyword: .when, regex: regex, callback:callback)
    }
    public func Then(_ regex:String, callback:@escaping (([String], Step) -> Void)) {
        attachClosureToSteps(keyword: .then, regex: regex, callback:callback)
    }
    public func And(_ regex:String, callback:@escaping (([String], Step) -> Void)) {
        attachClosureToSteps(keyword: .and, regex: regex, callback:callback)
    }
    public func But(_ regex:String, callback:@escaping (([String], Step) -> Void)) {
        attachClosureToSteps(keyword: .but, regex: regex, callback:callback)
    }
    public func MatchAll(_ regex:String, callback:@escaping (([String], Step) -> Void)) {
        attachClosureToSteps(regex: regex, callback:callback)
    }
    
}
